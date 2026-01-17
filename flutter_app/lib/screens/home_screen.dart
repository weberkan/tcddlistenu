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

      _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
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
          
          // Bilet bulundu mu?
          if (status['ticket_found'] == true) {
            timer.cancel();
            if (!mounted) return;
            _showTicketFoundDialog(status['message'] ?? 'Bilet bulundu!');
          }
          
          // İzleme durumu değişti mi?
        if (status['watching'] == false && _isWatching) {
          if (!mounted) return;
          
          bool ticketFound = status['ticket_found'] == true;
          bool wagonNotFound = status['wagon_not_found'] == true;
          
          setState(() {
            _isWatching = false;
            _checkCount = 0;
            _lastCheckTime = '';
          });
          timer.cancel();
          
          // Vagon tipi bulunamadıysa özel uyarı göster
          if (wagonNotFound) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        status['message'] ?? 'Seçilen vagon tipi bu güzergahta bulunmuyor',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.red[700],
                duration: const Duration(seconds: 8),
              ),
            );
          }
          // İzleme sonuç mesajı göster (vagon bulunmadıysa zaten üstte gösterildi)
          else if (!ticketFound) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        status['message'] ?? 'İzleme tamamlandı - Bilet bulunamadı',
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
}
