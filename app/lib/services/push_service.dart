import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/api/client.dart';
import '../data/local/hive_setup.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

// Router navigate callback — set by main.dart after router is created
typedef NavigateFn = void Function(String path);
NavigateFn? _navigate;

void setPushNavigate(NavigateFn fn) => _navigate = fn;

// Called when a 'sos_response' FCM arrives — host wires this up to invalidate
// the sosStatusProvider for the given alertId so an open status screen refreshes.
typedef SosResponseFn = void Function(int alertId);
SosResponseFn? _onSosResponse;

void setPushOnSosResponse(SosResponseFn fn) => _onSosResponse = fn;

class PushService {
  static final _fcm = FirebaseMessaging.instance;

  static Future<void> init() async {
    await _initLocalNotifications();
    await _requestPermission();
    _listenForeground();
    _listenTap();
    _fcm.onTokenRefresh.listen(_onTokenRefresh);

    // Handle tap when app was terminated
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _routeMessage(initial.data);
  }

  static Future<void> registerCurrentDevice(dio) async {
    final token = await _fcm.getToken();
    if (token == null) return;
    HiveSetup.sessionBox.put('fcm_token', token);
    try {
      // Endpoint is mounted under /auth/ (accounts/urls.py is included at
      // /api/v1/auth/, see medunity/urls.py).
      await dio.post('/auth/devices/register/', data: {
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
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload != null) _navigate?.call(payload);
      },
    );

    // SOS high-priority channel
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
      if (type == 'sos_response') {
        _showSosResponseNotification(message);
        final alertIdStr = message.data['alert_id'] as String?;
        final alertId = int.tryParse(alertIdStr ?? '');
        if (alertId != null) _onSosResponse?.call(alertId);
        return;
      }
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
      _routeMessage(message.data);
    });
  }

  static void _routeMessage(Map<String, dynamic> data) {
    final deepLink = data['deep_link'] as String?;
    if (deepLink != null) _navigate?.call(deepLink);
  }

  static void _onTokenRefresh(String token) {
    HiveSetup.sessionBox.put('fcm_token', token);
  }

  static Future<void> _showSosResponseNotification(RemoteMessage message) async {
    final alertId = message.data['alert_id'] ?? '';
    final deepLink = message.data['deep_link'] ?? '/sos/status/$alertId';
    final title = message.notification?.title ?? 'Someone is on their way';
    final body = message.notification?.body ?? 'A doctor accepted your SOS.';

    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'sos_critical',
          'SOS Alerts',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          color: const Color(0xFF2E7D32),
        ),
      ),
      payload: deepLink,
    );
  }

  static Future<void> _showSosNotification(RemoteMessage message) async {
    final alertId = message.data['alert_id'] ?? '';
    final categoryDisplay = message.data['category_display'] ?? 'SOS Alert';
    final deepLink = message.data['deep_link'] ?? '/sos/incoming/$alertId';

    await _localNotifications.show(
      message.hashCode,
      '🆘 $categoryDisplay',
      'A nearby doctor needs help — tap to respond',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'sos_critical',
          'SOS Alerts',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          color: const Color(0xFFD32F2F),
          ledColor: const Color(0xFFD32F2F),
          ledOnMs: 300,
          ledOffMs: 300,
        ),
      ),
      payload: deepLink,
    );
  }
}
