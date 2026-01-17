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
        
        # Arkaplan süreciyle başlat - PIPE kullanarak
        watching_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding='utf-8',
            errors='replace',
            bufsize=1,  # Line buffered
            cwd=os.path.dirname(os.path.abspath(__file__)),
            env=env
        )
        
        # Thread ile watcher process'ini izle
        def read_output():
            global last_status
            check_count = 0
            logs = []
            
            try:
                print(f"[INFO] Watcher process başlatıldı, stdout okunuyor...")
                
                # Stdout'u satır satır oku - readline ile
                for line in iter(watching_process.stdout.readline, ''):
                    line = line.strip()
                    if line:
                        print(f"[WATCHER] {line}")
                        # Log listesine ekle
                        logs.append(line)
                        if len(logs) > 20:
                            logs.pop(0)
                        last_status["logs"] = logs.copy()
                        
                        # Kontrol sayısını ve zamanı takip et
                        if "Kontrol #" in line:
                            check_count += 1
                            if " - " in line:
                                time_part = line.split(" - ")[-1].strip()
                                last_status["last_check_time"] = time_part
                            last_status["check_count"] = check_count
                            
                        # Bilet bulundu kontrolü (Log üzerinden)
                        if "BİLET BULUNDU" in line or "MÜSAİT durumunda" in line or "BİLET AÇILDI" in line:
                            print(f"[INFO] Logdan tespit edildi: Bilet Bulundu!")
                            last_status["ticket_found"] = True
                            
                            # Detaylı vagon bilgisi parse et
                            if "BİLET BULUNDU" in line and "(" in line and ")" in line:
                                try:
                                    start = line.find("(") + 1
                                    end = line.find(")")
                                    wagons_str = line[start:end]
                                    last_status["message"] = f"Bilet Bulundu! ({wagons_str})"
                                except:
                                    last_status["message"] = f"Bilet Bulundu! ({watching_params['wagon_type']})"
                            elif watching_params['wagon_type'] != 'ALL':
                                last_status["message"] = f"Bilet Bulundu! ({watching_params['wagon_type']})"
                            else:
                                last_status["message"] = "Bilet Bulundu! (Detaylar logda)"
                            
                        # Vagon bulunamadı kontrolü (Log üzerinden) - Sadece watcher uyarısı ile
                        if "Vagon tipi mevcut değil" in line or "State'e vagon bulunamadı durumu kaydedildi" in line:
                            if watching_params['wagon_type'] != 'ALL':
                                last_status["wagon_not_found"] = True
                
                print(f"[INFO] Watcher process tamamlandı!")
                last_status["watching"] = False
                
                # Process bittikten sonra state dosyasını oku ve sonucu işle
                print(f"[INFO] State dosyası okunuyor...")
                try:
                    import json
                    import time
                    time.sleep(1)  # State dosyasının yazılmasını bekle
                    state_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'state.json')
                    if os.path.exists(state_file):
                        with open(state_file, 'r', encoding='utf-8') as f:
                            state_data = json.load(f)
                            
                            # state_key formatı: FROM_TO_DATE_WAGONTYPE_Np
                            # Watcher orijinal haliyle (upper olmadan) kaydediyor olabilir, o yüzden önce direkt dene
                            state_key = f"{watching_params['from']}_{watching_params['to']}_{watching_params['date']}_{watching_params['wagon_type']}_{watching_params['passengers']}p"
                            
                            print(f"[DEBUG] read_output - Aranan key (orijinal): {state_key}")
                            
                            # Önce direkt eşleşme dene
                            wagon_state = None
                            if state_key in state_data:
                                wagon_state = state_data[state_key]
                                print(f"[DEBUG] read_output - Direkt eşleşme bulundu: {state_key}")
                            else:
                                # Bulunamazsa normalizasyon ile dene (eski kayıtlar için)
                                # Türkçe karakter normalizasyonu
                                def normalize_turkish(s):
                                    replacements = {
                                        'ı': 'I', 'İ': 'I', 'i': 'I',
                                        'ğ': 'G', 'Ğ': 'G',
                                        'ü': 'U', 'Ü': 'U',
                                        'ş': 'S', 'Ş': 'S',
                                        'ö': 'O', 'Ö': 'O',
                                        'ç': 'C', 'Ç': 'C'
                                    }
                                    result = s.upper()
                                    for old, new in replacements.items():
                                        result = result.replace(old, new)
                                    return result
                                
                                # Normalize edilmiş state key oluştur
                                from_normalized = normalize_turkish(watching_params['from'])
                                to_normalized = normalize_turkish(watching_params['to'])
                                search_key = f"{from_normalized}_{to_normalized}_{watching_params['date']}_{watching_params['wagon_type']}_{watching_params['passengers']}p"
                                
                                print(f"[DEBUG] read_output - Aranan key (normalize): {search_key}")
                                
                                # Fuzzy match ile state'den bul
                                for key in state_data.keys():
                                    normalized_key = normalize_turkish(key)
                                    if normalized_key == search_key:
                                        wagon_state = state_data[key]
                                        print(f"[DEBUG] read_output - Fuzzy match bulundu: {key}")
                                        break
                            
                            if wagon_state:
                                print(f"[DEBUG] State data: {wagon_state}")
                                # Önce wagon_not_found flag'ini kontrol et
                                if wagon_state.get('wagon_not_found') == True:
                                    print(f"[INFO] ✅ State'de wagon_not_found=True - {watching_params['wagon_type']} vagonu bu hatta yok!")
                                    last_status["wagon_not_found"] = True
                                    wagon_display = watching_params['wagon_type'] if watching_params['wagon_type'] != 'ALL' else 'İstenen'
                                    last_status["message"] = f"Bu güzergahta {wagon_display} koltuk bulunmamaktadır."
                                # Eğer status DOLU ve price None ise, vagon bulunamadı demektir
                                elif wagon_state.get('status') == 'DOLU' and wagon_state.get('price') is None:
                                    print(f"[INFO] ✅ State'e göre {watching_params['wagon_type']} vagonu bu hatta yok!")
                                    last_status["wagon_not_found"] = True
                                    wagon_display = watching_params['wagon_type'] if watching_params['wagon_type'] != 'ALL' else 'İstenen'
                                    last_status["message"] = f"Bu güzergahta {wagon_display} koltuk bulunmamaktadır."
                                else:
                                    print(f"[INFO] Vagon mevcut: status={wagon_state.get('status')}, price={wagon_state.get('price')}")
                            else:
                                # State'de key bulunamadı = vagon yok (ANCAK ALL değilse)
                                if watching_params['wagon_type'] != 'ALL':
                                    print(f"[INFO] ✅ State'de eşleşen key bulunamadı - vagon bu güzergahta mevcut değil!")
                                    last_status["wagon_not_found"] = True
                                    wagon_display = watching_params['wagon_type']
                                    last_status["message"] = f"Bu güzergahta {wagon_display} koltuk bulunmamaktadır."
                                else:
                                    print(f"[INFO] State'de ALL key'i yok ama normal, tek tek vagonlar kontrol ediliyor.")
                except Exception as e:
                    print(f"[WARNING] State dosyası okunamadı: {e}")
                    import traceback
                    traceback.print_exc()
                
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
            "params": watching_params,
            "check_count": 0,
            "last_check_time": "",
            "logs": []
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
    global last_status, watching_process, watching_params
    
    # Process hala çalışıyor mu kontrol et
    if watching_process:
        is_running = watching_process.poll() is None
        last_status["watching"] = is_running
        
        # Process bitti ve henüz wagon_not_found/ticket_found set edilmediyse
        # State dosyasını doğrudan kontrol et (race condition fix)
        if not is_running and watching_params:
            if not last_status.get("wagon_not_found") and not last_status.get("ticket_found"):
                try:
                    state_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'state.json')
                    if os.path.exists(state_file):
                        with open(state_file, 'r', encoding='utf-8') as f:
                            state_data = json.load(f)
                            
                            # Önce direkt eşleşme dene (upper olmadan)
                            state_key = f"{watching_params['from']}_{watching_params['to']}_{watching_params['date']}_{watching_params['wagon_type']}_{watching_params['passengers']}p"
                            wagon_state = None
                            
                            if state_key in state_data:
                                wagon_state = state_data[state_key]
                                print(f"[DEBUG] get_status - Direkt eşleşme bulundu: {state_key}")
                            else:
                                # Türkçe karakter normalizasyonu fallback
                                def normalize_turkish(s):
                                    replacements = {
                                        'ı': 'I', 'İ': 'I', 'i': 'I',
                                        'ğ': 'G', 'Ğ': 'G',
                                        'ü': 'U', 'Ü': 'U',
                                        'ş': 'S', 'Ş': 'S',
                                        'ö': 'O', 'Ö': 'O',
                                        'ç': 'C', 'Ç': 'C'
                                    }
                                    result = s.upper()
                                    for old, new in replacements.items():
                                        result = result.replace(old, new)
                                    return result
                            
                                # Normalize edilmiş state key oluştur
                                from_normalized = normalize_turkish(watching_params['from'])
                                to_normalized = normalize_turkish(watching_params['to'])
                                search_key = f"{from_normalized}_{to_normalized}_{watching_params['date']}_{watching_params['wagon_type']}_{watching_params['passengers']}p"
                                
                                print(f"[DEBUG] Aranan key (normalize): {search_key}")
                                
                                # Fuzzy match ile state'den bul
                                for key in state_data.keys():
                                    normalized_key = normalize_turkish(key)
                                    if normalized_key == search_key:
                                        wagon_state = state_data[key]
                                        print(f"[DEBUG] read_output - Fuzzy match bulundu: {key}")
                                        break
                            
                            if wagon_state:
                                print(f"[DEBUG] State data: {wagon_state}")
                                # wagon_not_found flag'ini kontrol et
                                if wagon_state.get('wagon_not_found') == True:
                                    last_status["wagon_not_found"] = True
                                    wagon_display = watching_params['wagon_type'] if watching_params['wagon_type'] != 'ALL' else 'İstenen'
                                    last_status["message"] = f"Bu güzergahta {wagon_display} koltuk bulunmamaktadır."
                                elif wagon_state.get('status') == 'DOLU' and wagon_state.get('price') is None:
                                    last_status["wagon_not_found"] = True
                                    wagon_display = watching_params['wagon_type'] if watching_params['wagon_type'] != 'ALL' else 'İstenen'
                                    last_status["message"] = f"Bu güzergahta {wagon_display} koltuk bulunmamaktadır."
                            else:
                                print(f"[WARNING] State'de eşleşen key bulunamadı!")
                except Exception as e:
                    print(f"[WARNING] get_status - State dosyası okunamadı: {e}")
                    import traceback
                    traceback.print_exc()
                
                # Hala wagon_not_found yoksa varsayılan mesaj
                if not last_status.get("wagon_not_found") and not last_status.get("ticket_found"):
                    if not last_status.get("message") or "başlatıldı" in last_status.get("message", ""):
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
