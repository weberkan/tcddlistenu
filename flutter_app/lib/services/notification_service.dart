import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    // Firebase başlat
    await Firebase.initializeApp();

    // Bildirim izni al (iOS 13+ için)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('Bildirim izin durumu: ${settings.authorizationStatus}');

    // FCM token al
    String? token = await _messaging.getToken();
    print('FCM Token: $token');

    // Token'ı topic'e abone ol
    if (token != null) {
      await subscribeToTopic();
    }

    // Foreground bildirimleri dinle
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground bildirim alındı: ${message.notification?.title}');
      print('Mesaj: ${message.notification?.body}');
    });

    // Arka planda bildirimlerle uygulama açıldığında
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Bildirimle uygulama açıldı: ${message.data}');
    });
  }

  Future<void> subscribeToTopic() async {
    await _messaging.subscribeToTopic('tcdd-bilet-alerts');
    print('Topic\'e abone olundu: tcdd-bilet-alerts');
  }

  Future<void> unsubscribeFromTopic() async {
    await _messaging.unsubscribeFromTopic('tcdd-bilet-alerts');
    print('Topic aboneliği iptal edildi: tcdd-bilet-alerts');
  }
}
