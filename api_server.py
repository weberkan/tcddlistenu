from flask import Flask, request, jsonify
from flask_cors import CORS
import subprocess
import threading
import json
import os
from datetime import datetime

app = Flask(__name__)
CORS(app)  # Flutter uygulamasından gelen isteklere izin ver

# Global değişkenler
watching_process = None
watching_params = None
last_status = {"watching": False, "ticket_found": False, "wagon_not_found": False, "message": ""}

@app.route('/api/watch', methods=['POST'])
def start_watching():
    """İzlemeyi başlat"""
    global watching_process, watching_params, last_status
    
    try:
        data = request.json
        from_station = data.get('from')
        to_station = data.get('to')
        date = data.get('date')
        wagon_type = data.get('wagon_type', 'ALL')
        passengers = data.get('passengers', 1)
        
        if not all([from_station, to_station, date]):
            return jsonify({
                'status': 'error',
                'message': 'Eksik parametreler'
            }), 400
        
        # Önceki izleme varsa durdur
        if watching_process and watching_process.poll() is None:
            watching_process.terminate()
        
        # Yeni izlemeyi başlat
        watching_params = {
            'from': from_station,
            'to': to_station,
            'date': date,
            'wagon_type': wagon_type,
            'passengers': passengers
        }
        
        # Python scriptini çalıştır
        python_path = r"C:\Users\weberkan\AppData\Local\Programs\Python\Python312\python.exe"
        script_path = "tcdd_watcher.py"
        
        cmd = [
            python_path,
            '-u',  # Unbuffered output
            script_path,
            '--from', from_station,
            '--to', to_station,
            '--date', date,
            '--wagon-type', wagon_type,
            '--passengers', str(passengers),
            '--watch',  # Sürekli izleme modu
            '--interval', '1.5'  # 1.5 dakika (90 saniye) - artık float destekli
        ]
        
        # UTF-8 encoding için environment variable
        env = os.environ.copy()
        env['PYTHONIOENCODING'] = 'utf-8'
        
        # Arkaplan süreciyle başlat
        watching_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # stderr'ı da yakala
            text=True,
            encoding='utf-8',
            errors='replace',  # Encoding hatalarını görmezden gel
            bufsize=1,  # Line buffered
            cwd=os.path.dirname(os.path.abspath(__file__)),
            env=env
        )
        
        # Thread ile output'u oku
        def read_output():
            global last_status
            check_count = 0
            try:
                for line in watching_process.stdout:
                    line_clean = line.strip()
                    print(f"[BACKEND] {line_clean}")
                    
                    # Vagon tipi bu seferde yok mu kontrol et (case-insensitive)
                    if 'vagon tipi bu seferde bulunmuyor' in line_clean.lower():
                        last_status["watching"] = False
                        last_status["ticket_found"] = False
                        last_status["wagon_not_found"] = True
                        wagon_display = wagon_type if wagon_type != 'ALL' else 'İstenen'
                        last_status["message"] = f"Bu güzergahta {wagon_display} koltuk bulunmamaktadır."
                        print(f"[INFO] ⚠️ VAGON TİPİ BULUNAMADI: {wagon_type} bu hatta mevcut değil!")
                        print(f"[INFO] İzleme otomatik olarak durduruluyor...")
                        break
                    
                    # Kontrol sayısını yakala
                    if 'Kontrol #' in line_clean:
                        import re
                        match = re.search(r'Kontrol #(\d+)', line_clean)
                        if match:
                            check_count = int(match.group(1))
                            last_status["check_count"] = check_count
                            last_status["last_check_time"] = datetime.now().strftime('%H:%M:%S')
                    
                    # Sadece seçilen vagon tipini kontrol et
                    line_upper = line_clean.upper()
                    
                    # Vagon tipi bilgisi var mı kontrol et
                    if 'VAGON DURUMU' in line_upper or 'WAGON STATUS' in line_upper:
                        # Seçilen vagon tipi bu satırda mı?
                        if wagon_type.upper() in line_upper or wagon_type == 'ALL':
                            # MÜSAİT mi kontrol et
                            if any(keyword in line_upper for keyword in ['MÜSAİT', 'MUSAIT', 'AVAILABLE']):
                                # DOLU değilse gerçekten müsait
                                if 'DOLU' not in line_upper and 'FULL' not in line_upper:
                                    # Gerçekten bulunan vagon tipini tespit et
                                    found_wagon = wagon_type
                                    if wagon_type == 'ALL':
                                        # ALL seçiliyse, satırdan vagon tipini çıkar
                                        if 'EKONOMİ' in line_upper or 'EKONOMI' in line_upper:
                                            found_wagon = 'EKONOMİ'
                                        elif 'BUSINESS' in line_upper:
                                            found_wagon = 'BUSINESS'
                                        elif 'YATAKLI' in line_upper:
                                            found_wagon = 'YATAKLI'
                                    
                                    last_status["ticket_found"] = True
                                    last_status["found_wagon_type"] = found_wagon
                                    last_status["message"] = f"Bu güzergahta {found_wagon} bilet bulundu."
                                    print(f"[INFO] BİLET BULUNDU! Vagon: {found_wagon}, Mesaj: {last_status['message']}")
                    
                    # Fiyat bilgisi varsa ekle
                    if '₺' in line_clean or 'TL' in line_clean.upper():
                        if 'Fiyat' in line_clean or 'Price' in line_clean:
                            last_status["price"] = line_clean
                
                # Process tamamlandı
                last_status["watching"] = False
                
                # State dosyasını oku - watcher'ın sonucunu buradan al (daha güvenilir)
                try:
                    import json
                    state_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'state.json')
                    if os.path.exists(state_file):
                        with open(state_file, 'r', encoding='utf-8') as f:
                            state_data = json.load(f)
                            # state_key formatı: FROM_TO_DATE_WAGONTYPE_Np
                            state_key = f"{watching_params['from'].upper()}_{watching_params['to'].upper()}_{watching_params['date']}_{watching_params['wagon_type']}_{watching_params['passengers']}p"
                            if state_key in state_data:
                                wagon_state = state_data[state_key]
                                # Eğer status DOLU değilse ve price None ise, vagon bulunamadı demektir
                                if wagon_state.get('status') == 'DOLU' and wagon_state.get('price') is None:
                                    print(f"[INFO] State'e göre {watching_params['wagon_type']} vagonu bu hatta yok!")
                                    last_status["wagon_not_found"] = True
                                    wagon_display = watching_params['wagon_type'] if watching_params['wagon_type'] != 'ALL' else 'İstenen'
                                    last_status["message"] = f"Bu güzergahta {wagon_display} koltuk bulunmamaktadır."
                except Exception as e:
                    print(f"[WARNING] State dosyası okunamadı: {e}")
                
                # wagon_not_found zaten set edilmişse, mesajı ASLA değiştirme
                if not last_status.get("wagon_not_found"):
                    # Sadece vagon bulundu AMA bilet bulunamadıysa genel mesaj göster
                    if not last_status.get("ticket_found") and not last_status.get("message"):
                        last_status["message"] = "İzleme tamamlandı."
                        print(f"[INFO] İzleme bitti. {wagon_type} için bilet kontrolü tamamlandı.")
                    
            except Exception as e:
                print(f"[ERROR] Output okuma hatası: {e}")
                last_status["watching"] = False
        
        threading.Thread(target=read_output, daemon=True).start()
        
        last_status = {
            "watching": True,
            "ticket_found": False,
            "wagon_not_found": False,
            "message": f"İzleme başlatıldı: {from_station} → {to_station}",
            "params": watching_params
        }
        
        return jsonify({
            'status': 'success',
            'message': 'İzleme başlatıldı',
            'params': watching_params
        })
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/api/watch', methods=['DELETE'])
def stop_watching():
    """İzlemeyi durdur"""
    global watching_process, last_status
    
    try:
        if watching_process and watching_process.poll() is None:
            watching_process.terminate()
            watching_process = None
        
        last_status = {
            "watching": False,
            "ticket_found": False,
            "wagon_not_found": False,
            "message": "İzleme durduruldu"
        }
        
        return jsonify({
            'status': 'success',
            'message': 'İzleme durduruldu'
        })
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/api/status', methods=['GET'])
def get_status():
    """Mevcut durumu döndür"""
    global last_status, watching_process
    
    # Process hala çalışıyor mu kontrol et
    if watching_process:
        is_running = watching_process.poll() is None
        last_status["watching"] = is_running
        if not is_running:
            last_status["message"] = "İzleme tamamlandı"
    
    return jsonify(last_status)

@app.route('/api/health', methods=['GET'])
def health_check():
    """Sunucu sağlık kontrolü"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat()
    })

if __name__ == '__main__':
    print("=" * 60)
    print("TCDD Backend API Server")
    print("=" * 60)
    print("Server başlatılıyor: http://localhost:5000")
    print("Endpoints:")
    print("  POST   /api/watch   - İzleme başlat")
    print("  DELETE /api/watch   - İzlemeyi durdur")
    print("  GET    /api/status  - Durum sorgula")
    print("  GET    /api/health  - Sağlık kontrolü")
    print("=" * 60)
    
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)
