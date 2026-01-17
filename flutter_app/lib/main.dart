import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase başlat (isteğe bağlı - yapılandırma yoksa devam et)
  try {
    await Firebase.initializeApp();
    print('[INFO] Firebase başlatıldı');
    
    // Bildirim servisini başlat
    NotificationService notificationService = NotificationService();
    await notificationService.initialize();
  } catch (e) {
    print('[WARNING] Firebase yapılandırması bulunamadı: $e');
    print('[INFO] Uygulama Firebase olmadan başlatılıyor...');
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TCDD Bilet İzleyicisi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}
