# TCDD Bilet İzleyicisi - Hızlı Başlangıç

> **ÖNEMLİ**: Bu proje Python backend ve Flutter mobil uygulamadan oluşan tam bir sistemdir. İlk çalıştırma için tüm kurulum adımlarını yapmanız gerekebilir.

## ⚡ Hızlı Başlangıç (5 dakika)

### 1. Python Backend Kurulumu

```bash
# Python ve Playwright yükleyin (min. 3 dakika)
pip install -r requirements.txt
playwright install chromium

# Environment dosyasını oluştur
cp .env.example .env

# .env'i düzenle (Firebase Project ID ve Key Path)
notepad .env
```

### 2. Firebase Projesi Oluşturun (5 dakika)

1. [firebase.google.com](https://console.firebase.google.com/)'a gidin
2. "Create a project" butonuna tıklayın
3. Project Settings → Service Accounts → "Generate New Private Key"
4. JSON dosyasını indirin → `service-account-key.json` olarak kaydedin

> **ÖNEMLİ**: Bu dosyayı asla GitHub'a yüklemeyin!

### 3. Python Script'i Test Edin (2 dakika)

```bash
# Sadece tek seferlik test (cron ile tekrar tekrar çalışmayın)
python tcdd_watcher.py --from "Çiğli" --to "Konya" --date "2026-01-20" --wagon-type YATAKLI
```

### 4. Flutter App'i Çalıştırın (1 dakika)

```bash
cd flutter_app
flutter run
```

> **Not**: Uygulama açıldığında Firebase configuration hatası görebilirsiniz. Bu normaldir - LSP hatasıdır.

## ✅ Tam Kurulum Sonrası

### Python Backend Cron Ayarı:

```bash
# Linux/Mac için (crontab -e)
*/3 * * * * cd /path/to/tcddlisten && /usr/bin/python3 tcdd_watcher.py -f "Çiğli" -t "Konya" -d "2026-01-20" -w ALL -p 1 >> tcdd_watcher.log 2>&1

# Windows için (Task Scheduler)
# Every 3 minutes: python tcdd_watcher.py -f "Çiğli" -t "Konya" -d "2026-01-20" -w ALL -p 1
```

### Flutter App:

Uygulama çalışırken Firebase'den bildirim alırsınız.

## 🎯 Kullanım Özeti

| Bileşen | Komut | Açıklama |
|---------|-------|------------|
| Python | `python tcdd_watcher.py -f "X" -t "Y" -d "YYYY-MM-DD" -w VAGON -p N` | Nereden, Nereye, Tarih, Vagon tipi, Yolcu sayısını belirler |
| Cron | `*/3 * * * *` | Her 3 dakikada bir kontrol |

## 📊 Beklenen Çıktı

Bilet DOLU → MÜSAİT geçişinde:

```
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! YATAKLI BİLET AÇILDI !
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Hat: ÇİĞLİ → KONYA
Tarih: 2026-01-20
Vagon Tipi: YATAKLI
Yolcu Sayısı: 1
Fiyat: ₺1.250,00
Zaman: 2026-01-15T01:45:00.123456
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

[INFO] Bildirim başarıyla gönderildi: projects/your-project/messages/12345
```

## 🔧 Sorun Giderme

| Sorun | Çözüm |
|-------|--------|
| Firebase bildirim gelmiyor | App'i kapatıp tekrar açın, internet bağlantısını kontrol edin |
| Captcha çıkıyor | Biraz bekleyin, tekrar çalıştırın |
| Script çalışmıyor | Log dosyasını kontrol edin (`tcdd_watcher.log`) |
| Python hataları | Dependencies'leri doğru yüklediğinizi kontrol edin (`pip list`) |

## 📞 Destek

Detaylı bilgi için: `README.md`

---

**5 dakikada çalışmaya hazır olmalısınız!** 🚂
