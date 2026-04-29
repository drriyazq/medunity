import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/api/client.dart';
import '../data/local/hive_setup.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

class PushService {
  static final _fcm = FirebaseMessaging.instance;

  /// Call once after app startup and user login.
  static Future<void> init() async {
    await _initLocalNotifications();
    await _requestPermission();
    _listenForeground();
    _listenTap();
    _fcm.onTokenRefresh.listen(_onTokenRefresh);
  }

  static Future<void> registerCurrentDevice(dio) async {
    final token = await _fcm.getToken();
    if (token == null) return;
    HiveSetup.sessionBox.put('fcm_token', token);
    try {
      await dio.post('/devices/register/', data: {
        'token': token,
        'platform': 'android',
      });
    } catch (_) {}
  }

  static Future<void> _requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
  }

  static Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    // SOS high-priority channel (Phase 2: custom sound + full-screen intent)
    const sosChannel = AndroidNotificationChannel(
      'sos_critical',
      'SOS Alerts',
      description: 'High-priority SOS emergency alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(sosChannel);
  }

  static void _listenForeground() {
    FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type'];
      if (type == 'sos_alert') {
        _showSosNotification(message);
        return;
      }
      // Default notification for other types
      _localNotifications.show(
        message.hashCode,
        message.notification?.title,
        message.notification?.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default',
            'General',
            importance: Importance.defaultImportance,
          ),
        ),
      );
    });
  }

  static void _listenTap() {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final deepLink = message.data['deep_link'] as String?;
      if (deepLink != null) {
        // Phase 2+: router.push(deepLink)
        debugPrint('[FCM] Deep link: $deepLink');
      }
    });
  }

  static void _onTokenRefresh(String token) {
    HiveSetup.sessionBox.put('fcm_token', token);
    // Phase 1: re-register token on backend
  }

  static Future<void> _showSosNotification(RemoteMessage message) async {
    // Full-screen intent + siren added in Phase 2 when siren asset is available
    await _localNotifications.show(
      message.hashCode,
      '🚨 ${message.data['requester_clinic_name'] ?? 'SOS Alert'}',
      message.data['message']?.isNotEmpty == true
          ? message.data['message']
          : 'Nearby doctor needs assistance — tap to respond',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'sos_critical',
          'SOS Alerts',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
      ),
      payload: message.data['deep_link'],
    );
  }
}
