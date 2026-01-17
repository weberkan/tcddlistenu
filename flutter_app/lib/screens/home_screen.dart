import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _fromController = TextEditingController(text: 'Çiğli');
  final TextEditingController _toController = TextEditingController(text: 'Konya');
  final TextEditingController _dateController = TextEditingController(
      text: DateTime.now().add(const Duration(days: 1)).toString().substring(0, 10));

  String _selectedWagonType = 'EKONOMİ';
  int _passengerCount = 1;
  bool _isWatching = false;
  Timer? _statusCheckTimer;
  
  // Aktivite takibi
  int _checkCount = 0;
  String _lastCheckTime = '';
  List<String> _logs = [];  // Log mesajları
  
  final ApiService _apiService = ApiService();

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _startWatching() async {
    if (_fromController.text.isEmpty ||
        _toController.text.isEmpty ||
        _dateController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen tüm alanları doldurun'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      setState(() {
        _isWatching = true;
      });

      final response = await _apiService.startWatching(
        from: _fromController.text,
        to: _toController.text,
        date: _dateController.text,
        wagonType: _selectedWagonType,
        passengers: _passengerCount,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? 'İzleme başlatıldı!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      _statusCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        try {
          final status = await _apiService.getStatus();
          
          // Aktivite bilgilerini güncelle
          if (status['check_count'] != null) {
            setState(() {
              _checkCount = status['check_count'];
            });
          }
          if (status['last_check_time'] != null) {
            setState(() {
              _lastCheckTime = status['last_check_time'];
            });
          }
          // Log mesajlarını güncelle
          if (status['logs'] != null) {
            setState(() {
              _logs = List<String>.from(status['logs']);
            });
          }
          
          bool ticketFound = status['ticket_found'] == true;
          bool wagonNotFound = status['wagon_not_found'] == true;
          bool isServerWatching = status['watching'] == true;

          // Bilet bulundu durumu
          if (ticketFound) {
             timer.cancel();
             setState(() {
               _isWatching = false;
             });
             if (!mounted) return;
             
             // Eğer vagon bulunamadıysa (nadiren çakışırsa) vagon yok dialogu
             if (wagonNotFound) {
                _showWagonNotFoundDialog("$_selectedWagonType");
             } else {
                _showTicketFoundDialog(status['message'] ?? 'Bilet bulundu!');
             }
             return; // Çıkış
          }

          // Vagon bulunamadı ama ticketFound gelmediyse (Normalde watching false olur)
          // Eğer server durmuşsa ve biz hala izliyorsak
          if (!isServerWatching && _isWatching) {
             timer.cancel();
             setState(() {
                _isWatching = false;
                // Logları temizleme kalsın ki son loglar görünsün
             });
             
             if (!mounted) return;
             
             if (wagonNotFound) {
                _showWagonNotFoundDialog("$_selectedWagonType");
             } else {
                // İzleme tamamlandı (zaman aşımı veya manuel durdurma değil, sistem durmuş)
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.info, color: Colors.white),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            status['message'] ?? 'İzleme tamamlandı.',
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.orange[700],
                    duration: const Duration(seconds: 5),
                  ),
                );
             }
          }
        } catch (e) {
          print('Status check error: $e');
        }
      });

    } catch (e) {
      setState(() {
        _isWatching = false;
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backend bağlantı hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopWatching() async {
    try {
      await _apiService.stopWatching();
      _statusCheckTimer?.cancel();
      
      setState(() {
        _isWatching = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İzleme durduruldu'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showTicketFoundDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.celebration, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Text('BİLET BULUNDU!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            Text(
              '${_fromController.text} → ${_toController.text}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700]),
            ),
            const SizedBox(height: 8),
            Text(_dateController.text, style: const TextStyle(fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _stopWatching();
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TCDD Bilet İzleyicisi'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Vagon Tipi
            const Text('Vagon Tipi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['EKONOMİ', 'BUSINESS', 'YATAKLI', 'ALL'].map((type) {
                return ChoiceChip(
                  label: Text(type),
                  selected: _selectedWagonType == type,
                  onSelected: _isWatching ? null : (selected) {
                    if (selected) {
                      setState(() {
                        _selectedWagonType = type;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Yolcu Sayısı
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Text('Yolcu Sayısı:', style: TextStyle(fontSize: 16)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _isWatching || _passengerCount <= 1 ? null : () {
                        setState(() => _passengerCount--);
                      },
                    ),
                    Text('$_passengerCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _isWatching || _passengerCount >= 6 ? null : () {
                        setState(() => _passengerCount++);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Rota
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _fromController,
                      enabled: !_isWatching,
                      decoration: const InputDecoration(
                        labelText: 'Nereden',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _toController,
                      enabled: !_isWatching,
                      decoration: const InputDecoration(
                        labelText: 'Nereye',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dateController,
                      enabled: !_isWatching,
                      decoration: const InputDecoration(
                        labelText: 'Tarih (YYYY-MM-DD)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Durum
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isWatching ? Colors.green[50] : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _isWatching ? Icons.notifications_active : Icons.notifications_off,
                        color: _isWatching ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isWatching ? 'İzleme Aktif' : 'İzleme Pasif',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _isWatching ? Colors.green[900] : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  if (_isWatching && _checkCount > 0) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text(
                              _checkCount.toString(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                            Text(
                              'Kontrol',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        if (_lastCheckTime.isNotEmpty)
                          Column(
                            children: [
                              Text(
                                _lastCheckTime,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                              Text(
                                'Son Kontrol',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            // Log mesajları (izleme bitmiş olsa bile loglar varsa göster)
            if (_logs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _logs.map((log) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        log,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: log.contains('WARNING') || log.contains('⚠️')
                              ? Colors.orange
                              : log.contains('ERROR')
                                  ? Colors.red
                                  : log.contains('MÜSAİT')
                                      ? Colors.green
                                      : Colors.green[300],
                        ),
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Buton
            ElevatedButton(
              onPressed: _isWatching ? _stopWatching : _startWatching,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isWatching ? Colors.grey : Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _isWatching ? 'İzlemeyi Durdur' : 'İzlemeyi Başlat',
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 16),

            // Bilgi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Backend server çalışmalı. Bilet bulunca bildirim gelecek!',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTicketFoundDialog(String message) {
     showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 10),
            Text('Bilet Bulundu!'),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  void _showWagonNotFoundDialog(String wagonType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 10),
            Text('Vagon Tipi Bulunamadı'),
          ],
        ),
        content: Text(
          'Bu güzergahta $wagonType koltuk bulunmamaktadır.',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red[50],
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
