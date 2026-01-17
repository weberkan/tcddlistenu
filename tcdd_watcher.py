#!/usr/bin/env python3
"""
TCDD Taşımacılık E-Bilet İzleyicisi

Bu script, belirli bir hat, tarih ve vagon türü (özellikle YATAKLI) için
bilet durumunu periyodik olarak kontrol eder. DOLU → MÜSAİT geçişinde
bilgilendirme yapar.

KULLANIM:
    python tcdd_watcher.py --from "Çiğli" --to "Konya" --date "2026-01-20"

KRİTERLER:
    - Sadece DOLU → MÜSAİT geçişinde aksiyon alınır
    - Otomatik satın alma yapılmaz
    - State dosyası ile önceki durum takibi
    - Cron/zamanlanmış çalışmaya uygun (while loop yok)
"""

import asyncio
import sys

# stdout flush et
sys.stdout.reconfigure(line_buffering=True)
print("Watcher script başlatılıyor...", flush=True)

import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, List
import argparse
from enum import Enum
from dataclasses import dataclass

from playwright.async_api import async_playwright, Page, Browser


class WagonType(str, Enum):
    """Vagon tipleri"""
    EKONOMI = "EKONOMİ"
    BUSINESS = "BUSINESS"
    YATAKLI = "YATAKLI"
    ALL = "ALL"

try:
    from firebase_admin import credentials, messaging, initialize_app, get_app
    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False
    print("[WARNING] Firebase Admin SDK yüklü değil. Bildirim özelliği devre dışı.")

try:
    from dotenv import load_dotenv
    load_dotenv()
    ENV_AVAILABLE = True
except ImportError:
    ENV_AVAILABLE = False
    print("[WARNING] python-dotenv yüklü değil. .env dosyası okunamayacak.")


# Konfigürasyon
BASE_URL = os.getenv("BASE_URL", "https://ebilet.tcddtasimacilik.gov.tr")
STATE_FILE = os.getenv("STATE_FILE", "state.json")
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"


@dataclass
class TicketStatus:
    """Bilet durumu bilgisi"""
    from_station: str
    to_station: str
    date: str
    status: str  # 'DOLU' | 'MUSAIT' | 'UNKNOWN'
    price: Optional[str]
    timestamp: str


class NotificationService:
    """
    Firebase Cloud Messaging Bildirim Servisi

    TCDD bilet durumu MÜSAİT olduğunda mobil uygulamaya bildirim gönderir.
    """

    def __init__(self):
        self.enabled = FIREBASE_AVAILABLE and ENV_AVAILABLE
        self._app_initialized = False
        self.fcm_topic = os.getenv("FIREBASE_NOTIFICATION_TOPIC", "tcdd-bilet-alerts")

        if self.enabled:
            self._initialize_firebase()

    def _initialize_firebase(self):
        """Firebase'i başlat"""
        try:
            project_id = os.getenv("FIREBASE_PROJECT_ID")
            private_key_path = os.getenv("FIREBASE_PRIVATE_KEY_PATH")

            if not project_id or not private_key_path:
                print("[WARNING] Firebase credentials eksik. .env dosyasını kontrol edin.")
                self.enabled = False
                return

            # Firebase app başlat
            cred = credentials.Certificate(private_key_path)
            try:
                initialize_app(cred, {'projectId': project_id})
                self._app_initialized = True
                print("[INFO] Firebase başarıyla başlatıldı")
            except ValueError:
                # App zaten başlatılmış
                self._app_initialized = True
                print("[INFO] Firebase zaten başlatılmış")

        except Exception as e:
            print(f"[ERROR] Firebase başlatma hatası: {e}")
            self.enabled = False

    async def send_ticket_available_notification(self, ticket_status: TicketStatus, wagon_type: str) -> bool:
        """
        Bilet MÜSAİT olduğunda bildirim gönder

        Args:
            ticket_status: Bilet durumu bilgisi

        Returns:
            bool: Bildirim başarılı mı?
        """
        if not self.enabled or not self._app_initialized:
            print("[INFO] Firebase bildirim devre dışı")
            return False

        try:
            # FCM mesajı oluştur
            message = messaging.Message(
                notification=messaging.Notification(
                    title=f"🚂 {wagon_type} BİLET AÇILDI!",
                    body=f"{ticket_status.from_station} → {ticket_status.to_station}\n"
                         f"Tarih: {ticket_status.date}\n"
                         f"Vagon: {wagon_type}\n"
                         f"Fiyat: {ticket_status.price or 'Belirtilmedi'}"
                ),
                data={
                    'type': 'ticket_available',
                    'from_station': ticket_status.from_station,
                    'to_station': ticket_status.to_station,
                    'date': ticket_status.date,
                    'wagon_type': wagon_type,
                    'price': ticket_status.price or '',
                    'timestamp': ticket_status.timestamp
                },
                topic=self.fcm_topic,
                android=messaging.AndroidConfig(
                    priority='high',
                    notification=messaging.AndroidNotification(
                        channel_id='tcdd_bilet_alerts',
                        sound='default',
                        click_action='FLUTTER_NOTIFICATION_CLICK'
                    )
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(
                            alert=messaging.ApsAlert(
                                title='🚂 YATAKLI BİLET AÇILDI!',
                                body=f'{ticket_status.from_station} → {ticket_status.to_station}\n'
                                     f'Tarih: {ticket_status.date}'
                            ),
                            sound='default',
                            badge=1
                        )
                    )
                )
            )

            # Mesajı gönder
            response = messaging.send(message)
            print(f"[INFO] Bildirim başarıyla gönderildi: {response}")
            return True

        except Exception as e:
            print(f"[ERROR] Bildirim gönderme hatası: {e}")
            return False


class TCDDWatcher:
    """TCDD e-bilet izleyicisi"""

    def __init__(self, from_station: str, to_station: str, date: str, wagon_type: WagonType = WagonType.ALL, passengers: int = 1):
        self.from_station = from_station
        self.to_station = to_station
        self.date = date
        self.wagon_type = wagon_type
        self.passengers = passengers
        self.state = self._load_state()
        self.notification_service = NotificationService()

    def _load_state(self) -> Dict:
        """State dosyasından önceki durumu yükle"""
        if os.path.exists(STATE_FILE):
            try:
                with open(STATE_FILE, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"[WARNING] State dosyası okunamadı: {e}")
        return {}

    def _save_state(self, new_state: Dict):
        """Yeni durumu state dosyasına kaydet"""
        try:
            with open(STATE_FILE, 'w', encoding='utf-8') as f:
                json.dump(new_state, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"[ERROR] State dosyası kaydedilemedi: {e}")

    def _get_state_key(self) -> str:
        """Bu sefer için benzersiz state anahtarı"""
        return f"{self.from_station}_{self.to_station}_{self.date}_{self.wagon_type.value}_{self.passengers}p"

    def _get_state_key_for_wagon(self, wagon_type: WagonType, passengers: int) -> str:
        """Belirli bir vagon tipi için state anahtarı"""
        return f"{self.from_station}_{self.to_station}_{self.date}_{wagon_type.value}_{passengers}p"

    async def _fill_from_station(self, page: Page):
        """
        Nereden alanını doldur
        """
        print(f"[INFO] Nereden alanına '{self.from_station}' yazılıyor...")
        # Input alanını bul ve temizle
        from_input = page.locator('#fromTrainInput')
        await from_input.click()
        await from_input.fill('')
        await from_input.type(self.from_station, delay=100)
        await asyncio.sleep(2)  # Dropdown listesinin yüklenmesi için bekleme

        # Dropdown'tan doğru istasyonu seç (.dropdown-item.station)
        # İstasyon adını içeren butonu bul
        station_found = False
        dropdown_items = await page.query_selector_all('.dropdown-item.station')
        for item in dropdown_items:
            text = await item.text_content()
            # Türkçe karakter duyarlı karşılaştırma
            text_val = text.strip() if text else ""
            
            # Basit lower() dönüşümü (tr karakterler için replace gerekebilir ama şimdilik basic)
            def simple_normalize(s):
                return s.replace('İ', 'i').replace('I', 'ı').lower()
            
            if simple_normalize(self.from_station) in simple_normalize(text_val):
                await item.click()
                print(f"[INFO] '{text.strip()}' istasyonu seçildi")
                station_found = True
                break
        
        if not station_found:
            print(f"[WARNING] '{self.from_station}' için uygun istasyon bulunamadı, ilk seçenek deneniyor...")
            first_item = await page.query_selector('.dropdown-item.station')
            if first_item:
                await first_item.click()

        await asyncio.sleep(1)

    async def _fill_to_station(self, page: Page):
        """
        Nereye alanını doldur
        """
        print(f"[INFO] Nereye alanına '{self.to_station}' yazılıyor...")
        to_input = page.locator('#toTrainInput')
        await to_input.click()
        await to_input.fill('')
        await to_input.type(self.to_station, delay=100)
        await asyncio.sleep(2)

        station_found = False
        dropdown_items = await page.query_selector_all('.dropdown-item.station')
        for item in dropdown_items:
            text = await item.text_content()
            # Türkçe karakter duyarlı karşılaştırma
            text_val = text.strip() if text else ""
            
            # Basit lower() dönüşümü
            def simple_normalize(s):
                return s.replace('İ', 'i').replace('I', 'ı').lower()
                
            if simple_normalize(self.to_station) in simple_normalize(text_val):
                await item.click()
                print(f"[INFO] '{text.strip()}' istasyonu seçildi")
                station_found = True
                break
        
        if not station_found:
            print(f"[WARNING] '{self.to_station}' için uygun istasyon bulunamadı, ilk seçenek deneniyor...")
            first_item = await page.query_selector('.dropdown-item.station')
            if first_item:
                await first_item.click()

        await asyncio.sleep(1)

    async def _select_date(self, page: Page):
        """
        Gidiş tarihi seç
        """
        print(f"[INFO] Gidiş tarihi seçiliyor: {self.date}")

        try:
            # Önce varsa açık bir takvimi kapatmayı veya alanı tıklamayı dene
            date_display = page.locator('.reportrange-text')
            await date_display.click()
            await asyncio.sleep(2)

            from datetime import datetime
            date_obj = datetime.strptime(self.date, "%Y-%m-%d")
            day = str(date_obj.day)

            # JavaScript ile daha sağlam bir tıklama denemesi
            print(f"[INFO] Takvimde gün aranıyor: {day}")
            clicked = await page.evaluate(f'''(targetDay) => {{
                // daterangepicker içindeki hücreleri bul
                const cells = Array.from(document.querySelectorAll('.calendar-table td:not(.off)'));
                const cell = cells.find(c => c.textContent.trim() === targetDay);
                if (cell) {{
                    cell.click();
                    return true;
                }}
                return false;
            }}''', day)
            
            if clicked:
                print(f"[INFO] Gün {day} seçildi")
                # Eğer 'Uygula' butonu gerekiyorsa
                apply_btn = page.locator('button:has-text("Uygula")')
                if await apply_btn.is_visible():
                    await apply_btn.click()
                    print("[INFO] 'Uygula' butonuna tıklandı")
            else:
                print(f"[WARNING] Takvimde {day} günü bulunamadı!")
                
            print(f"[INFO] Tarih {self.date} seçildi")
        except Exception as e:
            print(f"[ERROR] Tarih seçim hatası: {e}")

        await asyncio.sleep(1)

        await asyncio.sleep(1)

    async def _search_trips(self, page: Page):
        """
        Sefer ara butonuna tıkla

        Selector Stratejisi:
        - Text ile buton bulunur: button:has-text("Sefer Ara")
        - Neden: UI'de değişmeyecek olan text kullanılır
        """
        print("[INFO] Seferler aranıyor...")
        search_button = page.locator('#searchSeferButton')
        await search_button.click()

        # Seferlerin yüklenmesi için bekleme (JS-rendered content)
        print("[INFO] Seferler yükleniyor...")
        try:
            # Hem vagon butonlarını hem de fiyat bilgilerini içeren bir selector bekle
            await page.wait_for_selector('.price', timeout=20000)
            print("[INFO] Seferler yüklendi")
        except Exception:
            print("[WARNING] Sefer listesi yüklenirken beklenenden uzun sürdü veya boş sonuç döndü.")

    async def _check_all_wagon_availability(self, page: Page) -> Dict:
        """
        Tüm vagon tiplerinin durumunu kontrol et
        """
        if self.wagon_type == WagonType.ALL:
            print(f"[INFO] Tüm vagon tipleri durumu kontrol ediliyor...")
        else:
            print(f"[INFO] {self.wagon_type.value} vagon durumu kontrol ediliyor...")

        # JavaScript ile durum kontrolü
        status_data = await page.evaluate('''() => {
            const results = {
                'EKONOMİ': null,
                'BUSINESS': null,
                'YATAKLI': null
            };

            const buttons = document.querySelectorAll('button');
            buttons.forEach(btn => {
                const text = (btn.textContent || '').toUpperCase();

                let type = null;
                if (text.includes('EKONOMİ')) type = 'EKONOMİ';
                else if (text.includes('BUSINESS')) type = 'BUSINESS';
                else if (text.includes('YATAKLI')) type = 'YATAKLI';

                if (type) {
                    const isDisabled = btn.classList.contains('disabled') || btn.hasAttribute('disabled');
                    const priceElement = btn.closest('.col-md-12') ? btn.closest('.col-md-12').querySelector('.price') : null;
                    const price = priceElement ? priceElement.textContent.trim() : '';
                    const passengersElement = btn.closest('.col-md-12') ? btn.closest('.col-md-12').querySelector('[class*="passenger"]') : null;
                    const passengers = passengersElement ? (parseInt(passengersElement.textContent.trim()) || 1) : 1;

                    results[type] = {
                        isDisabled,
                        price,
                        passengers,
                        buttonText: text.trim()
                    };
                }
            });

            return results;
        }''')

        if not status_data or not any(status_data.values()):
            print("[WARNING] Vagon tipleri bulunamadı!")
            return {
                'wagons': {},
                'timestamp': datetime.now().isoformat()
            }

        # Sonuçları formatla
        wagons = {}
        for wagon_name, wagon_data in status_data.items():
            if wagon_data is None:
                continue

            # Erken filtreleme: Eğer ALL değilse ve bu vagon aranan değilse atla
            if self.wagon_type != WagonType.ALL and wagon_name != self.wagon_type.value:
                continue

            is_disabled = wagon_data['isDisabled']
            price = wagon_data['price']
            passengers = wagon_data.get('passengers', 1)

            if is_disabled or price == 'DOLU':
                status = 'DOLU'
                print(f"[INFO] {wagon_name} vagon durumu: DOLU")
            else:
                status = 'MUSAIT'
                print(f"[INFO] {wagon_name} vagon durumu: MÜSAİT - Fiyat: {price} - Yolcu: {passengers}")



            # NOT: Yolcu sayısı kontrolü kaldırıldı - web sitesinden gelen değer güvenilir değil

            wagons[WagonType(wagon_name)] = {
                'status': status,
                'price': price if price != 'DOLU' else None,
                'passengers': self.passengers  # Kullanıcının girdiği yolcu sayısını kullan
            }

        return {
            'wagons': wagons,
            'timestamp': datetime.now().isoformat()
        }

    async def check(self) -> Optional[Dict]:
        """
        Tek seferlik kontrol gerçekleştir

        Returns:
            Dict: Kontrol sonucu
        """
        state_key = self._get_state_key()
        previous_status = self.state.get(state_key, {}).get('status')

        print(f"\n{'='*60}")
        print(f"TCDD BİLET İZLEYİCİSİ")
        print(f"{'='*60}")
        print(f"Hat: {self.from_station} → {self.to_station}")
        print(f"Tarih: {self.date}")
        print(f"Hat: {self.from_station} → {self.to_station}")
        print(f"Tarih: {self.date}")
        print(f"Vagon Tipi: {self.wagon_type.value if self.wagon_type != WagonType.ALL else 'TÜMÜ'}")
        print(f"Yolcu Sayısı: {self.passengers}")
        print(f"Önceki Durum: {previous_status or 'Yok'}")
        print(f"{'='*60}\n")

        async with async_playwright() as p:
            # Browser başlat (headless=False - gerçek kullanıcıya benzer)
            # User-Agent ve diğer başlıklar ayarla
            browser = await p.chromium.launch(
                headless=True,  # Sunucu ortamında True olmalı
                args=[
                    '--disable-blink-features=AutomationControlled',
                ]
            )

            context = await browser.new_context(
                user_agent=USER_AGENT,
                viewport={'width': 1920, 'height': 1080},
                locale='tr-TR'
            )

            page = await context.new_page()

            try:
                # 1. Ana sayfaya git
                print(f"[INFO] Ana sayfaya gidiliyor: {BASE_URL}")
                await page.goto(BASE_URL, wait_until='domcontentloaded')
                await asyncio.sleep(2)

                # 2. İstasyonları seç
                await self._fill_from_station(page)
                await self._fill_to_station(page)

                # 2.5. Tarih seç
                await self._select_date(page)

                # 3. Sefer ara
                await self._search_trips(page)

                # 4. Tüm vagon durumlarını kontrol et
                current_status_data = await self._check_all_wagon_availability(page)
                wagons = current_status_data['wagons']
                current_timestamp = current_status_data['timestamp']

                # 5. Durum karşılaştırma ve aksiyon
                result = {
                    'from': self.from_station,
                    'to': self.to_station,
                    'date': self.date,
                    'wagon_type': self.wagon_type.value if self.wagon_type != WagonType.ALL else 'ALL',
                    'passengers': self.passengers,
                    'wagons': wagons,
                    'timestamp': current_timestamp,
                    'notification_sent': False,
                    'wagon_not_found': False  # Yeni: Vagon tipi bu seferde yok mu?
                }

                # Önemli: Eğer aranan vagon tipi bu seferde hiç yoksa, izlemeyi durdur
                if self.wagon_type != WagonType.ALL:
                    wagon_exists = self.wagon_type.value in [w.value for w in wagons.keys()] # Check against enum values
                    if not wagon_exists:
                        print(f"\n⚠️  [WARNING] {self.wagon_type.value} vagon tipi bu seferde bulunmuyor!")
                        print(f"[INFO] Bu hat için {self.wagon_type.value} vagonu mevcut değil.")
                        print(f"[INFO] İzleme sonlandırılıyor...\n")
                        result['wagon_not_found'] = True
                        result['ticket_found'] = False
                        
                        # State dosyasına vagon bulunamadı durumunu kaydet
                        state_key = self._get_state_key()
                        self.state[state_key] = {
                            'status': 'DOLU',
                            'price': None,
                            'passengers': self.passengers,
                            'last_checked': current_timestamp,
                            'wagon_not_found': True  # Özel flag
                        }
                        self._save_state(self.state)
                        print(f"[INFO] State'e vagon bulunamadı durumu kaydedildi: {state_key}")
                        
                        return result

                # Her vagon tipi için kontrol
                notification_sent_count = 0
                found_wagon_types = []

                for wagon_type_name, wagon_data in wagons.items():
                    # Eğer spesifik bir vagon tipi aranıyorsa ve bu o değilse, loglama ve işlem yapma
                    # Ancak ALL ise hepsini işle
                    if self.wagon_type != WagonType.ALL and wagon_type_name != self.wagon_type.value:
                        continue

                    wagon_type_enum = WagonType(wagon_type_name)
                    current_status = wagon_data['status']
                    current_price = wagon_data['price']
                    current_passengers = wagon_data.get('passengers', 1)

                    # Önceki durumu state'den al
                    state_key = self._get_state_key_for_wagon(wagon_type_enum, current_passengers)
                    previous_status = self.state.get(state_key, {}).get('status')

                    # Sadece DOLU → MÜSAİT geçişinde aksiyon al
                    if previous_status == 'DOLU' and current_status == 'MUSAIT':
                        print("\n" + "!"*60)
                        print(f"! {wagon_type_enum.value} BİLET AÇILDI !")
                        print("!"*60)
                        print(f"Hat: {self.from_station} → {self.to_station}")
                        print(f"Tarih: {self.date}")
                        print(f"Yolcu Sayısı: {current_passengers}")
                        print(f"Fiyat: {current_price}")
                        print(f"Zaman: {current_timestamp}")
                        print("!"*60 + "\n")

                        # Firebase bildirimi gönder
                        ticket_status = TicketStatus(
                            from_station=self.from_station,
                            to_station=self.to_station,
                            date=self.date,
                            status=current_status,
                            price=current_price,
                            timestamp=current_timestamp
                        )

                        notification_sent = await self.notification_service.send_ticket_available_notification(
                            ticket_status, wagon_type=wagon_type_enum.value
                        )
                        result['notification_sent'] = True
                        result['ticket_found'] = True # Bilet bulundu
                        found_wagon_types.append(wagon_type_name)
                        notification_sent_count += 1

                    elif current_status == 'MUSAIT':
                        print(f"\n[INFO] {wagon_type_enum.value} bilet zaten MÜSAİT durumunda")
                        if current_price:
                            print(f"[INFO] Fiyat: {current_price}")
                        # Geriye dönük uyumluluk veya sürekli bulma için ticket_found işaretle
                        result['ticket_found'] = True
                        found_wagon_types.append(wagon_type_name)
                    elif current_status == 'DOLU':
                        print(f"\n[INFO] {wagon_type_enum.value} bilet DOLU durumunda")

                # Bilet bulunduysa ve watching modundaysak çıkış yapmadan önce özel mesaj bas
                if result.get('ticket_found') and found_wagon_types:
                    # Tekrar edenleri temizle
                    unique_types = list(set(found_wagon_types))
                    types_str = ", ".join(unique_types)
                    print(f"[SUCCESS] BİLET BULUNDU! ({types_str}) Kontrol sonlandırılıyor.")
                    sys.exit(1)

                # Hiç bilet açılmadıysa bilgi ver
                if notification_sent_count == 0 and not result.get('ticket_found'):
                    print(f"\n[INFO] Henüz {self.wagon_type.value if self.wagon_type != WagonType.ALL else 'TÜMÜ'} vagon açılmadı")

                # 6. State'i güncelle
                for wagon_type_enum, wagon_data in wagons.items():
                    # State güncellemede de filtre uygula
                    if self.wagon_type != WagonType.ALL and wagon_type_enum.value != self.wagon_type.value:
                        continue 
                        
                    state_key = self._get_state_key_for_wagon(wagon_type_enum, wagon_data.get('passengers', 1))
                    self.state[state_key] = {
                        'status': wagon_data['status'],
                        'price': wagon_data['price'],
                        'passengers': wagon_data.get('passengers', 1),
                        'last_checked': current_timestamp
                    }
                self._save_state(self.state)

                return result

            except Exception as e:
                print(f"[ERROR] Beklenmedik hata: {e}")
                import traceback
                traceback.print_exc()
                return None

            finally:
                # Browser'ı kapat
                await asyncio.sleep(2)  # Son görüntüleme için bekleme
                await browser.close()


def main():
    """Ana fonksiyon - CLI argümanlarını işler"""
    parser = argparse.ArgumentParser(
        description='TCDD Taşımacılık E-Bilet İzleyicisi',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
ÖRNEKLER:
  python tcdd_watcher.py --from "Çiğli" --to "Konya" --date "2026-01-20"
  python tcdd_watcher.py -f "Çiğli" -t "Konya" -d "2026-01-20"

CRON KULLANIMI:
  # Her 3 dakikada bir kontrol
  */3 * * * * cd /path/to/tcddlisten && /usr/bin/python3 tcdd_watcher.py -f "Çiğli" -t "Konya" -d "2026-01-20" >> tcdd_watcher.log 2>&1

NOTLAR:
  - Sadece DOLU → MÜSAİT geçişinde bildirim gönderilir
  - Otomatik satın alma yapılmaz
  - State dosyası ile önceki durum takip edilir
  - Cron ile periyodik çalışmaya uygundur (while loop yok)
        """
    )

    parser.add_argument('-f', '--from', dest='from_station', required=True,
                        help='Kalkış istasyonu (ör: Çiğli)')
    parser.add_argument('-t', '--to', dest='to_station', required=True,
                        help='Varış istasyonu (ör: Konya)')
    parser.add_argument('-d', '--date', required=True,
                        help='Tarih (ör: 2026-01-20)')
    parser.add_argument('-w', '--wagon-type', dest='wagon_type',
                        choices=['EKONOMİ', 'BUSINESS', 'YATAKLI', 'ALL'],
                        default='ALL',
                        help='Vagon tipi (varsayılan: ALL)')
    parser.add_argument('-p', '--passengers', dest='passengers',
                        type=int,
                        default=1,
                        help='Yolcu sayısı (varsayılan: 1)')
    
    parser.add_argument('--watch', dest='watch_mode',
                        action='store_true',
                        help='Sürekli izleme modu (bulana kadar kontrol eder)')
    
    parser.add_argument('--interval', dest='interval_minutes',
                        type=float,  # float - 1.5, 2.0, etc.
                        default=10,
                        help='İzleme aralığı (dakika, varsayılan: 10)')

    args = parser.parse_args()

    # Vagon tipi enum'a çevir
    wagon_type_map = {
        'EKONOMİ': WagonType.EKONOMI,
        'BUSINESS': WagonType.BUSINESS,
        'YATAKLI': WagonType.YATAKLI,
        'ALL': WagonType.ALL
    }
    wagon_type = wagon_type_map[args.wagon_type]

    # Watcher oluştur ve kontrol et
    watcher = TCDDWatcher(
        from_station=args.from_station,
        to_station=args.to_station,
        date=args.date,
        wagon_type=wagon_type,
        passengers=args.passengers
    )

    if args.watch_mode:
        # Sürekli izleme modu
        print(f"[INFO] Sürekli izleme başlatıldı (Her {args.interval_minutes} dakikada kontrol)")
        print(f"[INFO] Hat: {args.from_station} → {args.to_station}, Tarih: {args.date}, Vagon: {wagon_type.value}")
        
        import time
        check_count = 0
        
        while True:
            check_count += 1
            print(f"\n[INFO] ===== Kontrol #{check_count} - {datetime.now().strftime('%H:%M:%S')} =====")
            
            try:
                result = asyncio.run(watcher.check())
                
                # Vagon tipi bu seferde yoksa dur
                if result and result.get('wagon_not_found'):
                    print(f"[INFO] İzleme sonlandırıldı - Vagon tipi mevcut değil.")
                    sys.exit(0)
                
                if result and result.get('ticket_found'):
                    print(f"[SUCCESS] BİLET BULUNDU! Kontrol sonlandırılıyor.")
                    sys.exit(1)  # Bilet bulundu
                else:
                    print(f"[INFO] Bilet bulunamadı. {args.interval_minutes} dakika sonra tekrar kontrol edilecek...")
                    
            except KeyboardInterrupt:
                print("\n[INFO] Kullanıcı tarafından durduruldu.")
                sys.exit(0)
            except Exception as e:
                print(f"[ERROR] Hata oluştu: {e}")
                print(f"[INFO] 1 dakika sonra tekrar denenecek...")
                time.sleep(60)
                continue
            
            # Interval kadar bekle
            time.sleep(args.interval_minutes * 60)
    else:
        # Tek seferlik kontrol
        result = asyncio.run(watcher.check())

        if result:
            # Exit code: 0 = normal, 1 = bilet açıldı (notification için)
            if result['notification_sent']:
                sys.exit(1)  # Cron job notification için
            else:
                sys.exit(0)
        else:
            sys.exit(2)  # Hata durumunda


if __name__ == "__main__":
    main()
