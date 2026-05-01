import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/local/hive_setup.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // appVerificationDisabledForTesting removed — Indian +91 phones now use the
  // WhatsApp OTP path (backend), not Firebase Phone Auth. Firebase is retained
  // only for non-India phones. Non-India debug testing still needs the SHA-1
  // debug fingerprint or a test number added in Firebase Console.
  await HiveSetup.init();
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  runApp(const ProviderScope(child: MedUnityApp()));
}
