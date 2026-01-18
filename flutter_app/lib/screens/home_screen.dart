import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  // Renk tanımları
  static const Color tcddRed = Color(0xFFE30613);
  static const Color backgroundLight = Color(0xFFF2F4F7);
  static const Color backgroundDark = Color(0xFF0F1115); // Log panel arka planı
  static const Color textDark = Color(0xFF121617);
  static const Color textGray = Color(0xFF9CA3AF);

  final TextEditingController _fromController = TextEditingController(text: 'Çiğli');
  final TextEditingController _toController = TextEditingController(text: 'Konya');
  final TextEditingController _dateController = TextEditingController(
      text: DateTime.now().add(const Duration(days: 1)).toString().substring(0, 10));

  String _selectedWagonType = 'EKONOMİ'; // UI Display Value
  int _passengerCount = 1;
  bool _isWatching = false;
  Timer? _statusCheckTimer;
  
  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Aktivite takibi
  int _checkCount = 0;
  String _lastCheckTime = '--:--:--';
  List<String> _logs = [];
  
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(_pulseController);
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startWatching() async {
    if (_fromController.text.isEmpty ||
        _toController.text.isEmpty ||
        _dateController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları doldurun')),
      );
      return;
    }

    try {
      setState(() => _isWatching = true);

      // Backend expects 'ALL', 'EKONOMİ', etc.
      // If UI is 'TÜMÜ', convert to 'ALL'.
      String backendWagonType = _selectedWagonType == 'TÜMÜ' ? 'ALL' : _selectedWagonType;

      final response = await _apiService.startWatching(
        from: _fromController.text,
        to: _toController.text,
        date: _dateController.text,
        wagonType: backendWagonType,
        passengers: _passengerCount,
      );

      if (!mounted) return;
      
      _statusCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        try {
          final status = await _apiService.getStatus();
          
          if (!mounted) return;

          setState(() {
            if (status['check_count'] != null) _checkCount = status['check_count'];
            
            // Clean up time string (remove artifacts if any)
            if (status['last_check_time'] != null) {
              String rawTime = status['last_check_time'].toString();
              // Try to find HH:MM:SS pattern
              RegExp timeRegExp = RegExp(r'\d{2}:\d{2}:\d{2}');
              var match = timeRegExp.firstMatch(rawTime);
              _lastCheckTime = match != null ? match.group(0)! : rawTime;
            }
            
            if (status['logs'] != null) _logs = List<String>.from(status['logs']);
          });

          bool ticketFound = status['ticket_found'] == true;
          bool wagonNotFound = status['wagon_not_found'] == true;
          bool isServerWatching = status['watching'] == true;

          if (ticketFound) {
             timer.cancel();
             
             // Parse actual wagon type from message if available
             // Format: "Bilet Bulundu! (EKONOMİ)" or "(EKONOMİ, BUSINESS)"
             String actualWagonType = _selectedWagonType;
             if (status['message'] != null) {
                String msg = status['message'].toString();
                if (msg.contains('(') && msg.contains(')')) {
                    final startIndex = msg.indexOf('(') + 1;
                    final endIndex = msg.indexOf(')');
                    if (startIndex > 0 && endIndex > startIndex) {
                       actualWagonType = msg.substring(startIndex, endIndex);
                    }
                }
             }

             setState(() {
               _isWatching = false;
               _logs.clear(); // Clear logs on success as requested
             });
             
             if (wagonNotFound) {
                _showWagonNotFoundDialog("$_selectedWagonType");
             } else {
                _showTicketFoundDialog(actualWagonType);
             }
             return;
          }

          if (!isServerWatching && _isWatching) {
             timer.cancel();
             setState(() => _isWatching = false);
             
             if (wagonNotFound) {
                _showWagonNotFoundDialog("$_selectedWagonType");
             } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(status['message'] ?? 'İzleme tamamlandı.'),
                    backgroundColor: Colors.orange[700],
                  ),
                );
             }
          }
        } catch (e) {
          print('Status check error: $e');
        }
      });

    } catch (e) {
      setState(() => _isWatching = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backend bağlantı hatası: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _stopWatching() async {
    try {
      await _apiService.stopWatching();
      _statusCheckTimer?.cancel();
      setState(() {
        _isWatching = false;
        // Reset UI to clean state
        _checkCount = 0;
        _lastCheckTime = '--:--:--';
        _logs.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  void _showTicketFoundDialog(String foundWagonType) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => TicketFoundDialog(
        from: _fromController.text,
        to: _toController.text,
        date: _dateController.text,
        wagonType: foundWagonType,
      ),
    );
  }

  void _showWagonNotFoundDialog(String wagonType) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => WagonNotFoundDialog(
        from: _fromController.text,
        to: _toController.text,
        date: _dateController.text,
        wagonType: wagonType,
        onEditCriteria: () {
          Navigator.pop(context);
          setState(() {
            _isWatching = false;
            _checkCount = 0;
            _lastCheckTime = '--:--:--';
            _logs.clear();
          });
        },
      ),
    );
  }

  // ... (rest of the file)

  Future<void> _selectDate(BuildContext context) async {
    if (_isWatching) return;
    
    // Minimal Custom Date Picker Dialog
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 300, // Fixed width for minimal look
            height: 380, // Fixed height
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Tarih Seçiniz',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textDark),
                ),
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: tcddRed, 
                        onPrimary: Colors.white, 
                        onSurface: textDark, 
                      ),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(foregroundColor: tcddRed),
                      ),
                    ),
                    child: CalendarDatePicker(
                      initialDate: DateTime.tryParse(_dateController.text) ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                      onDateChanged: (DateTime date) {
                        Navigator.of(context).pop(date);
                      },
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İPTAL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dateController.text = picked.toString().substring(0, 10);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // ÜST BÖLÜM (MAIN UI)
            Expanded(
              flex: 70, // %70 Main UI
              child: Container(
                color: Colors.white,
                child: Column(
                  children: [
                     // HEADER
                    _buildHeader(),
                    // STATUS BAR
                    _buildStatusBar(),
                    // FORM AREA
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            // ROUTE INPUTS
                            _buildRouteInputs(),
                            const SizedBox(height: 20),
                            // DATE & PASSENGER
                            _buildDetailsGrid(),
                            const SizedBox(height: 20),
                            // WAGON PREFERENCE
                            _buildWagonSelector(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    // ACTION BUTTON
                    _buildActionButton(),
                  ],
                ),
              ),
            ),
            
            // ALT BÖLÜM (LOGS)
            Expanded(
              flex: 30, // %30 Log Section
              child: _buildLogSection(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tcddRed,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: tcddRed.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: const Icon(Icons.train, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bilet Takip', style: TextStyle(color: textDark, fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('CANLI İZLEME PANELİ', style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ],
              ),
            ],
          ),
          InkWell(
            onTap: () {
              showDialog(
                context: context,
                barrierColor: Colors.transparent,
                builder: (context) {
                  Future.delayed(const Duration(seconds: 1), () {
                    if (context.mounted) Navigator.of(context).pop();
                  });
                  return Dialog(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    insetPadding: EdgeInsets.zero,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Yakında!',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                }
              );
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.settings, color: textGray, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isWatching ? const Color(0xFFECFDF5) : Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _isWatching ? const Color(0xFFD1FAE5) : Colors.grey[300]!),
            ),
            child: Row(
              children: [
                _isWatching 
                ? FadeTransition(
                    opacity: _pulseAnimation,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  _isWatching ? 'TAKİP AKTİF' : 'TAKİP PASİF',
                  style: TextStyle(
                    color: _isWatching ? Colors.green[700] : Colors.grey[600],
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _buildStatusItem('SORGULAMA', '$_checkCount'),
              Container(height: 24, width: 1, color: Colors.grey[300], margin: const EdgeInsets.symmetric(horizontal: 16)),
              _buildStatusItem('SON KONTROL', _lastCheckTime),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(color: textGray, fontSize: 9, fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(color: textDark, fontSize: 13, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildRouteInputs() {
    return Stack(
      children: [
        Column(
          children: [
            _buildInputCard('Kalkış İstasyonu', Icons.my_location, _fromController),
            const SizedBox(height: 12),
            _buildInputCard('Varış İstasyonu', Icons.location_on, _toController),
          ],
        ),
        Positioned(
          left: 28,
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.swap_vert, size: 18, color: tcddRed),
                onPressed: _isWatching ? null : () {
                  final temp = _fromController.text;
                  _fromController.text = _toController.text;
                  _toController.text = temp;
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputCard(String label, IconData icon, TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tcddRed, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                TextField(
                  controller: controller,
                  enabled: !_isWatching,
                  textCapitalization: TextCapitalization.words, // Capitalize words
                  style: const TextStyle(color: textDark, fontSize: 14, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: 'Seçiniz',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsGrid() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _selectDate(context),
            child: _buildSimpleCard(
                'Seyahat Tarihi',
                Icons.calendar_month,
                Text(
                  _dateController.text,
                  style: const TextStyle(color: textDark, fontSize: 13, fontWeight: FontWeight.w800),
                )
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSimpleCard(
              'Yolcu Sayısı',
              Icons.person,
              Row(
                children: [
                  InkWell(
                    onTap: _isWatching || _passengerCount <= 1 ? null : () => setState(() => _passengerCount--),
                    child: const Icon(Icons.remove, size: 16, color: textGray),
                  ),
                  const SizedBox(width: 8),
                  Text('$_passengerCount Yetişkin', style: const TextStyle(color: textDark, fontSize: 13, fontWeight: FontWeight.w800)),
                   const SizedBox(width: 8),
                  InkWell(
                    onTap: _isWatching || _passengerCount >= 6 ? null : () => setState(() => _passengerCount++),
                    child: const Icon(Icons.add, size: 16, color: textGray),
                  ),
                ],
              )
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleCard(String label, IconData icon, Widget content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, color: tcddRed, size: 18),
              const SizedBox(width: 8),
              Expanded(child: content),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWagonSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('VAGON TERCİHİ', style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: ['EKONOMİ', 'BUSINESS', 'YATAKLI', 'LOCA'].map((type) => _buildWagonCard(type)).toList(),
          ),
        ),
        const SizedBox(height: 8),
        _buildWagonCard('TÜMÜ', isFullWidth: true),
      ],
    );
  }

  Widget _buildWagonCard(String type, {bool isFullWidth = false}) {
    bool isSelected = _selectedWagonType == type;
    return GestureDetector(
      onTap: _isWatching ? null : () => setState(() => _selectedWagonType = type),
      child: Container(
        width: isFullWidth ? double.infinity : null,
        alignment: isFullWidth ? Alignment.center : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? backgroundLight : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? tcddRed : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            Text(type, style: TextStyle(
              color: isSelected ? tcddRed : textGray,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isWatching ? _stopWatching : _startWatching,
          style: ElevatedButton.styleFrom(
            backgroundColor: tcddRed,
            foregroundColor: Colors.white,
            elevation: 4,
            shadowColor: tcddRed.withOpacity(0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_isWatching ? Icons.stop : Icons.play_arrow, size: 24),
              const SizedBox(width: 12),
              Text(
                _isWatching ? 'TAKİBİ DURDUR' : 'TAKİBİ BAŞLAT',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogSection() {
    return Container(
      color: backgroundDark,
      child: Column(
        children: [
          // Log Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.terminal, color: textGray, size: 14), 
                    SizedBox(width: 8),
                    Text('AKTİVİTE GÜNLÜĞÜ', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ],
                ),
                InkWell(
                  onTap: () => setState(() => _logs.clear()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: tcddRed.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('TEMİZLE', style: TextStyle(color: tcddRed, fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
          // Log Content
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              reverse: true, 
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                // Reverse log order logic
                final reversedLogs = List.from(_logs.reversed);
                final log = reversedLogs[index]; 
                return _buildLogItem(log);
              },
            ),
          ),
          // Footer (Restored)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.black, border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified, color: Colors.green, size: 16),
                    SizedBox(width: 8),
                    Text('SİSTEM ÇALIŞIYOR', style: TextStyle(color: textGray, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
                Row(
                  children: [
                     const Text('UPTIME', style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                     const SizedBox(width: 8),
                     Text(DateTime.now().toString().substring(11, 16), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(String log) {
    Color logColor = Colors.white;
    if (log.contains('WARNING') || log.contains('WARN')) logColor = Colors.yellow;
    else if (log.contains('ERROR') || log.contains('CRIT')) logColor = tcddRed;
    else if (log.contains('SUCCESS') || log.contains('BİLET') || log.contains('MÜSAİT')) logColor = Colors.green;
    else if (log.contains('INFO') || log.contains('INIT')) logColor = Colors.blue[200]!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4), 
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50, 
            child: Text(
               DateTime.now().toString().substring(11, 19), // SS:dd ile daha detaylı
               style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              log,
              style: TextStyle(color: logColor.withOpacity(0.9), fontSize: 11, fontFamily: 'monospace'), // Font restored
              maxLines: 1, 
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// BİLET BULUNDU DIALOG WIDGET (Stateless -> Stateful for Timer)
class TicketFoundDialog extends StatefulWidget {
  final String from;
  final String to;
  final String date;
  final String wagonType;

  const TicketFoundDialog({
    Key? key,
    required this.from,
    required this.to,
    required this.date,
    required this.wagonType,
  }) : super(key: key);

  @override
  _TicketFoundDialogState createState() => _TicketFoundDialogState();
}

class _TicketFoundDialogState extends State<TicketFoundDialog> {
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    // 30 saniye sonra otomatik kapat
    _closeTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _launchURL() async {
    final Uri url = Uri.parse('https://ebilet.tcddtasimacilik.gov.tr/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
       // Fallback logic could go here
       print('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Stack(
          alignment: Alignment.center,
          children: [
             // Main Card
             Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40), // 2.5rem
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 25,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon Header
                  Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(
                          color: Color(0xFFECFDF5), // Green-50ish
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 48), // Green-600
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFACC15), // Yellow-400
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Title & Subtitle
                  const Text(
                    'BİLET BULUNDU!',
                    style: TextStyle(
                      color: Color(0xFF121617),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'İSTEDİĞİNİZ KRİTERLERE UYGUN YER VAR',
                    style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Info Cards
                  // Parkur Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF3F4F6)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
                          ),
                          child: const Icon(Icons.train, color: Color(0xFFE30613), size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('GÜZERGAH', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text('${widget.from} — ${widget.to}', style: const TextStyle(color: Color(0xFF121617), fontSize: 13, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // Date Card (Full Width)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF3F4F6)),
                    ),
                    child: Row(
                      children: [
                        Container(
                           padding: const EdgeInsets.all(8),
                           decoration: BoxDecoration(
                             color: Colors.white,
                             borderRadius: BorderRadius.circular(8),
                           ),
                           child: const Icon(Icons.calendar_month, color: Color(0xFFE30613), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('TARİH', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(widget.date, style: const TextStyle(color: Color(0xFF121617), fontSize: 14, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Found Wagons List Section
                  Container(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         const Padding(
                           padding: EdgeInsets.only(left: 4, bottom: 8),
                           child: Text('BULUNAN BİLETLER', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                         ),
                         ...widget.wagonType.split(', ').map((wagonInfo) {
                            // wagonInfo format: "EKONOMİ - 150 TL" or "LOCA"
                            String name = wagonInfo;
                            String price = '';
                            if (wagonInfo.contains(' - ')) {
                               final parts = wagonInfo.split(' - ');
                               name = parts[0];
                               price = parts.length > 1 ? parts[1] : '';
                            } else if (wagonInfo == 'ALL' || wagonInfo == 'TÜMÜ') {
                               name = 'Tümü';
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5), // Green-50
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFD1FAE5)), // Green-100
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check, color: Color(0xFF059669), size: 14), // Green-600
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(color: Color(0xFF064E3B), fontSize: 13, fontWeight: FontWeight.w800), // Green-900
                                    ),
                                  ),
                                  if (price.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white, 
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: const Color(0xFF059669).withOpacity(0.2)),
                                      ),
                                      child: Text(
                                        price,
                                        style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                            );
                         }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Actions
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _launchURL,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE30613),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: const Color(0xFFE30613).withOpacity(0.3),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_cart, size: 20),
                          SizedBox(width: 12),
                          Text('SATIN ALMAYA GİT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  const Text(
                    'Bu bildirim 30 saniye sonra kendiliğinden kapanacaktır.',
                    style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 10, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            // Close Button Positioned
            Positioned(
              top: 16,
              right: 16,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.grey, size: 20),
                ),
              ),
            ),
          ],
        )
      );
  }
}



// Custom Wagon Not Found Dialog
class WagonNotFoundDialog extends StatelessWidget {
  final String from;
  final String to;
  final String date;
  final String wagonType;
  final VoidCallback onEditCriteria;

  const WagonNotFoundDialog({
    Key? key,
    required this.from,
    required this.to,
    required this.date,
    required this.wagonType,
    required this.onEditCriteria,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40), // 2.5rem
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon Header
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFBEB), // Amber-50
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.train, color: Color(0xFFF59E0B), size: 48), // Amber-500
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B), // Amber-500
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.warning, color: Colors.white, size: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Title
            const Text(
              'VAGON TİPİ BULUNAMADI',
              style: TextStyle(
                color: Color(0xFF121617),
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            
            // Description (RichText)
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFF6B7280), // Gray-500
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  fontFamily: 'Roboto', // Default flutter font usually
                ),
                children: [
                  const TextSpan(text: 'Aradığınız güzergahta seçilen vagon tipi\n'),
                  TextSpan(
                    text: '($wagonType)',
                    style: const TextStyle(color: Color(0xFFE30613), fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' hizmet vermemektedir.'),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Info Cards
            // Route Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB), // Gray-50
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF3F4F6)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
                    ),
                    child: const Icon(Icons.route, color: Color(0xFFE30613), size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('GÜZERGAH', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('$from — $to', style: const TextStyle(color: Color(0xFF121617), fontSize: 13, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            
            // Grid: Date & Selection
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF3F4F6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TARİH', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.calendar_month, color: Color(0xFFE30613), size: 18),
                            const SizedBox(width: 6),
                            Expanded(child: Text(date, style: const TextStyle(color: Color(0xFF121617), fontSize: 13, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2), // Red-50
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFEE2E2)), // Red-100
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TERCİH (HATALI)', style: TextStyle(color: const Color(0xFFE30613).withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.event_seat, color: Color(0xFFE30613), size: 18), // Filled icon usually
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                wagonType == 'ALL' ? 'Tümü' : (wagonType == 'TÜMÜ' ? 'Tümü' : wagonType),
                                style: const TextStyle(color: Color(0xFFE30613), fontSize: 13, fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Actions
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onEditCriteria,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE30613),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                  shadowColor: const Color(0xFFE30613).withOpacity(0.3),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.tune, size: 20),
                    SizedBox(width: 12),
                    Text('KRİTERLERİ DÜZENLE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              'Lütfen farklı bir vagon tipi seçerek tekrar deneyiniz.',
              style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 10, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Title Case Formatter Helper
class TitleCaseTxt extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
     if (newValue.text.length <= oldValue.text.length) {
       return newValue;
     }
     if (newValue.text.isNotEmpty && newValue.text.length == 1) {
       return TextEditingValue(
         text: newValue.text.toUpperCase(),
         selection: newValue.selection,
       );
     }
     return newValue;
  }
}
