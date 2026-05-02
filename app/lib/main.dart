import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/local/hive_setup.dart';
import 'services/consultant_live_service.dart';
import 'services/consultant_schedule_alarm.dart';
import 'services/push_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  if (kReleaseMode) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  await HiveSetup.init();
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  await PushService.init();

  // Pre-create the foreground-service notification channel — MIUI / Android 13+
  // reject startForeground() if the channel isn't registered with an explicit
  // importance level.
  final flnp = FlutterLocalNotificationsPlugin();
  await flnp
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'medunity_consultant_live',
          'MedUnity Live Location',
          description:
              'Sharing your location with nearby doctors and clinics while Go Live is on.',
          importance: Importance.low,
        ),
      );

  // Live-location consultants — configure (does not start the service).
  await ConsultantLiveService.initialize();
  await ConsultantScheduleAlarm.initialize();

  runApp(const ProviderScope(child: MedUnityApp()));
}
