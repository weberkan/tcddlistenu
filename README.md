# TCDD Taşımacılık E-Bilet İzleyicisi

Bu proje, TCDD Taşımacılık e-bilet sitesinde belirli bir hat, tarih ve vagon türü (özellikle YATAKLI) için bilet durumunu periyodik olarak kontrol eden ve DOLU → MÜSAİT geçişinde mobil uygulamaya bildirim gönderen bir sistemdir.

## 🎯 Özellikler

- **Otomatik Durum Takibi**: Yataklı vagon bilet durumunu sürekli izler
- **Çoklu Vagon Tipi Desteği**: EKONOMİ, BUSINESS, YATAKLI veya TÜMÜ (ALL)
- **Yolcu Sayısı Seçimi**: 1-6 arası yolcu sayısı belirtebilir
- **Akıllı Bildirim**: Sadece DOLU → MÜSAİT geçişinde bildirim gönderir
- **Firebase Cloud Messaging**: Mobil uygulamaya push notification gönderir (her vagon tipi için ayrı bildirim)
- **State Yönetimi**: Önceki durumu JSON dosyasında saklar (her vagon tipi ve yolcu sayısı için ayrı state key)
- **Cron Uyumlu**: Sürekli while loop yerine tek seferlik kontrol mantığı
- **Güvenli**: Otomatik satın alma YAPMAZ, sadece bilgilendirme yapar
- **Cross-Platform**: Firebase sayesinde hem iOS hem Android için çalışır
- **Retry Mekanizması**: Sayfa yüklenmesi için bekleme süreleri

## ⚙️ Gereksinimler

- Python 3.8+
- Playwright
- Firebase Projesi (mobil bildirim için)
- Flutter 3.0+
- Firebase Service Account Key (backend için)

## 📦 Kurulum

### 1. Depoyu Klonlayın veya Oluşturun

```bash
# Yeni proje oluşturun
git clone <repo-url>
cd tcddlisten

# Veya mevcut projeye gidin
cd tcddlisten
```

### 2. Python Backend Kurulumu

```bash
# Sanal ortam oluşturun (opsiyonel)
python -m venv venv
# Windows
venv\Scripts\activate
# Linux/Mac
source venv/bin/activate

# Bağımlılıkları yükleyin
pip install -r requirements.txt
playwright install chromium
```

### 3. Firebase Kurulumu (Backend + Mobil Bildirim için)

#### A. Firebase Projesi Oluşturun

1. [Firebase Console](https://console.firebase.google.com/)'a gidin
2. Yeni proje oluşturun veya mevcut projeyi seçin
3. **Cloud Messaging** API'yi etkinleştirin
4. Project Settings'den proje bilgilerini not alın (Project ID)

#### B. Service Account Key Alın (Backend için)

1. Firebase Console → Project Settings → Service Accounts
2. "Generate New Private Key" butonuna tıklayın
3. JSON dosyasını indirin
4. Dosyayı proje dizinine `service-account-key.json` olarak kaydedin
5. **ÖNEMLİ**: Bu dosyayı asla GitHub'a yüklemeyin! `.gitignore`'a ekledim

#### C. Environment Dosyası Oluşturun

```bash
cp .env.example .env
```

`.env` dosyasını düzenleyin:

```env
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_PRIVATE_KEY_PATH=./service-account-key.json
FIREBASE_NOTIFICATION_TOPIC=tcdd-bilet-alerts

BASE_URL=https://ebilet.tcddtasimacilik.gov.tr
STATE_FILE=state.json
CHECK_INTERVAL_MINUTES=3
```

### 4. Flutter Mobil App Kurulumu

```bash
cd flutter_app
flutter pub get
```

#### Android Konfigürasyonu

1. Firebase Console → Project Settings → Your Apps → Android App
2. `google-services.json` dosyasını indirin
3. Dosyayı `android/app/` dizinine kopyalayın
4. `android/app/build.gradle` dosyasına Firebase dependency'sini ekleyin:

```gradle
dependencies {
    implementation 'com.google.firebase:firebase-messaging:23.0.0'
}
```

#### iOS Konfigürasyonu

1. Firebase Console → Project Settings → Your Apps → iOS App
2. `GoogleService-Info.plist` dosyasını indirin
3. Dosyayı `ios/Runner/` dizinine kopyalayın
4. `ios/Podfile`'e Firebase'i ekleyin:

```ruby
pod 'Firebase/Messaging'
```

```bash
cd ios
pod install
```

## 🚀 Kullanım

### Python Backend Kullanım

#### Tek Vagon Tipi Kontrolü:

```bash
# Yataklı vagon izle
python tcdd_watcher.py --from "Çiğli" --to "Konya" --date "2026-01-20" --wagon-type YATAKLI

# Ekonomi vagon izle
python tcdd_watcher.py --from "Çiğli" --to "Konya" --date "2026-01-20" --wagon-type EKONOMİ

# Business vagon izle
python tcdd_watcher.py --from "Çiğli" --to "Konya" --date "2026-01-20" --wagon-type BUSINESS

# Tüm vagon tiplerini izle
python tcdd_watcher.py --from "Çiğli" --to "Konya" --date "2026-01-20" --wagon-type ALL
```

#### 2 Yolcu Bileti:

```bash
# 2 kişilik bilet
python tcdd_watcher.py --from "Çiğli" --to "Konya" --date "2026-01-20" --passengers 2
```

### Cron ile Periyodik Kontrol

**Linux/Mac:**

```bash
# crontab -e ile cron düzenleyicisini açın

# Her 3 dakikada bir kontrol
*/3 * * * * cd /path/to/tcddlisten && /usr/bin/python3 tcdd_watcher.py -f "Çiğli" -t "Konya" -d "2026-01-20" --wagon-type ALL -p 1 >> tcdd_watcher.log 2>&1

# Her 5 dakikada bir kontrol
*/5 * * * * cd /path/to/tcddlisten && /usr/bin/python3 tcdd_watcher.py -f "Çiğli" -t "Konya" -d "2026-01-20" --wagon-type YATAKLI -p 1 >> tcdd_watcher.log 2>&1
```

**Windows (Task Scheduler):**

1. Task Scheduler'ı açın
2. Create Task
3. Trigger: "Every 3 minutes"
4. Action: Start a program
5. Program/script: `python` (path to python.exe)
6. Arguments: `tcdd_watcher.py -f "Çiğli" -t "Konya" -d "2026-01-20" --wagon-type ALL`
7. Save

### Flutter Mobil App Kullanım

```bash
cd flutter_app
flutter run
```

> **Not**: Firebase yapılandırma dosyaları (`google-services.json` ve `GoogleService-Info.plist`) Flutter SDK yüklendikten sonra düzgün çalışacaktır. LSP hataları yüklenmediği içindir.

## 📊 Çıktı Örnekleri

### Python Backend Çıktısı:

```
============================================================
TCDD BİLET İZLEYİCİSİ
============================================================
Hat: ÇİĞLİ → KONYA
Tarih: 2026-01-20
Vagon Tipi: ALL
Yolcu Sayısı: 1
Önceki Durum: Yok
============================================================

[INFO] Firebase başarıyla başlatıldı
[INFO] Ana sayfaya gidiliyor: https://ebilet.tcddtasimacilik.gov.tr
[INFO] Nereden alanına 'ÇİĞLİ' yazılıyor...
[INFO] 'ÇİĞLİ' istasyonu seçildi
[INFO] Nereye alanına 'KONYA' yazılıyor...
[INFO] 'KONYA' istasyonu seçildi
[INFO] Gidiş tarihi seçiliyor: 2026-01-20
[INFO] Tarih 2026-01-20 seçildi
[INFO] Seferler aranıyor...
[INFO] Seferler yükleniyor...
[INFO] Seferler yüklendi
[INFO] Tüm vagon tipleri durumu kontrol ediliyor (TÜMÜ)...

[INFO] EKONOMİ vagon durumu: DOLU
[INFO] BUSINESS vagon durumu: MÜSAİT - Fiyat: ₺850,00
[INFO] YATAKLI vagon durumu: DOLU

[INFO] Henüz TÜMÜ vagon açılmadı
```

### DOLU → MÜSAİT Geçişi:

```
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! EKONOMİ BİLET AÇILDI !
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Hat: ÇİĞLİ → KONYA
Tarih: 2026-01-20
Yolcu Sayısı: 1
Fiyat: ₺850,00
Zaman: 2026-01-15T01:45:00.123456
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

[INFO] Bildirim başarıyla gönderildi: projects/your-project/messages/12345
```

## 📁 Dosya Yapısı

```
tcddlisten/
├── tcdd_watcher.py              # Python backend (cron ile çalışır)
├── state.json                  # Bilet durumu cache
├── requirements.txt             # Python bağımlılıkları
├── .env.example               # Konfigürasyon template
├── .gitignore                 # Güvenlik ignore
│
└── flutter_app/               # Mobil uygulama
    ├── lib/
    │   ├── main.dart           # Firebase başlatma
    │   ├── services/
    │   │   └── notification_service.dart  # Firebase bildirim alma
    │   └── screens/
    │       └── home_screen.dart      # Ana UI
    ├── pubspec.yaml            # Flutter dependencies
    ├── android/                # Android yapılandırması
    │   └── app/
    │       └── build.gradle     # Firebase dependency
    └── ios/                    # iOS yapılandırması
        └── Runner/               # GoogleService-Info.plist
```

## 🎨 CLI Argümanları

| Argüman | Kısa | Varsayılan | Açıklama |
|-----------|-------|------------|------------|
| `-f` | --from | Yok | Kalkış istasyonu (ör: Çiğli) |
| `-t` | --to | Yok | Varış istasyonu (ör: Konya) |
| `-d` | --date | Yok | Tarih (ör: 2026-01-20) |
| `-w` | --wagon-type | ALL | Vagon tipi: EKONOMİ, BUSINESS, YATAKLI, ALL |
| `-p` | --passengers | 1 | Yolcu sayısı (1-6) |

## 🔐 Güvenlik Notları

- `service-account-key.json` dosyasını asla GitHub'a yüklemeyin!
- `.env` dosyasını `.gitignore`'a ekledim (gerçek `service-account-key.json` hariç)
- Firebase Project ID'sini paylaşmayın
- TCDD rate limit'ine dikkat edin (min. 2-3 dakika aralık)
- Captcha çıkarsa manuel müdahale gerekebilir
- Otomatik satın alma YAPILMAZ, sadece bilgilendirme yapar

## ⚠️ Dikkat Edilecekler

1. **Captcha**: TCDD captcha kullanırsa, script manuel müdahale gerektirir
2. **Rate Limit**: Aşırı sık istek göndermeyin (min. 2-3 dakika)
3. **DOM Değişiklikleri**: TCDD site yapısını değiştirirse selector'ları güncellemeli
4. **Firebase Key**: Service account key'i güvenli tutun, asla paylaşmayın
5. **Önceki Durum**: `state.json` dosyası kontrol için, silmeyin

## 🚧 Gelecek Özellikler

- [ ] REST API endpoint (mobil app için)
- [ ] E-posta bildirimi
- [ ] Telegram bot bildirimi
- [ ] SMS bildirimi
- [ ] Kullanıcı authentication (Firebase Auth)
- [ ] Bilet izleme history
- [ ] Multi-sefer desteği
- [ ] Web dashboard
- [ ] Vagon tipine göre otomatik seçim

## 🤝 Katkıda Bulunma

1. Fork yapın
2. Feature branch oluşturun (`git checkout -b feature/AmazingFeature`)
3. Commit yapın (`git commit -m 'Add some AmazingFeature'`)
4. Push edin (`git push origin feature/AmazingFeature`)
5. Pull Request açın

## 📄 Lisans

Bu proje eğitim ve kişisel kullanım amaçlıdır. TCDD'nin kullanım koşullarına uygun olarak kullanılmalıdır.

## ⚠️ Sorumluluk Reddi

Bu script ile yaptığınız tüm işlemlerden kendiniz sorumlusunuz. Yazar, TCDD'nin kullanım koşullarını ihlal edebilecek kullanımlardan sorumlu değildir. Script'ı sorumlu bir şekilde ve yasal sınırlar içinde kullanın.

## 📞 Destek

Sorun yaşarsanız veya öneriniz varsa issue açabilirsiniz.

---

**Made with ❤️ for Turkish Railway Enthusiasts**
