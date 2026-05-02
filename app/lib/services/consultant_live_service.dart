import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

const _kSessionBox = 'medunity_session';
const _kEncKeyName = 'medunity_hive_key_v1';
const _kNotificationChannelId = 'medunity_consultant_live';
const _kNotificationId = 9001;

const _kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://trusmiledentist.in/medunity-api',
);

/// Foreground service that pings the server with the consultant's GPS while
/// Go Live is ON. Runs in a separate Dart isolate — must re-init Hive itself.
class ConsultantLiveService {
  static final _service = FlutterBackgroundService();

  /// Guards against repeat bootstrap network calls during widget rebuilds.
  /// Reset by [stop] so the next Go Live → Bootstrap cycle works.
  static bool _bootstrapInFlight = false;
  static bool _bootstrapDone = false;

  static Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _kNotificationChannelId,
        initialNotificationTitle: "You're live on MedUnity",
        initialNotificationContent:
            'Matching you with nearby doctors. Your exact location stays private.',
        foregroundServiceNotificationId: _kNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Future<bool> ensurePermissions() async {
    // Foreground location must be granted before background. Android won't
    // even surface the background-location prompt without it.
    final fg = await Permission.locationWhenInUse.request();
    if (!fg.isGranted) return false;
    final bg = await Permission.locationAlways.request();
    if (!bg.isGranted) return false;
    final notif = await Permission.notification.request();
    if (!notif.isGranted) return false;
    return true;
  }

  static Future<void> start({required String mobilityMode}) async {
    final running = await _service.isRunning();
    if (running) {
      _service.invoke('updateMobility', {'mobility_mode': mobilityMode});
      return;
    }
    await _service.startService();
    // Pass mobility mode after start — startService doesn't accept payload
    _service.invoke('updateMobility', {'mobility_mode': mobilityMode});
  }

  /// Idempotent self-heal: if the service isn't running but Go Live is on,
  /// start it. Safe to call from any UI surface that knows the user is live —
  /// the Go Live screen, the Consult-tab availability chip, etc. — so the
  /// foreground notification is reattached even after the OS killed the
  /// service or a cold start raced past the bootstrap.
  static Future<void> ensureRunning({String mobilityMode = 'mobile'}) async {
    if (await _service.isRunning()) return;
    await start(mobilityMode: mobilityMode);
  }

  static Future<void> stop() async {
    final running = await _service.isRunning();
    if (running) _service.invoke('stopService');
    // Allow bootstrap to attempt again next time Go Live flips on.
    _bootstrapDone = false;
  }

  static Future<bool> isRunning() => _service.isRunning();

  /// Reattach the foreground service to the user's existing `is_available=True`
  /// state on app startup (e.g. after a fresh install, OS reboot, or the user
  /// killing the app from recents). Without this, the persistent notification
  /// silently disappears even though the server still thinks they're live.
  ///
  /// Silent on every failure — never blocks app boot.
  static Future<void> bootstrapIfLive(String authToken) async {
    if (_bootstrapInFlight || _bootstrapDone) return;
    _bootstrapInFlight = true;
    try {
      if (await _service.isRunning()) {
        _bootstrapDone = true;
        return;
      }

      final dio = Dio(BaseOptions(
        baseUrl: _kApiBaseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {'Authorization': 'Bearer $authToken'},
      ));
      final resp = await dio.get(
        '/consultants/me/settings/',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (resp.statusCode != 200) return;
      final data = resp.data as Map;
      if (data['is_available'] != true) return;

      // Note: deliberately NOT pre-checking Permission.locationAlways here.
      // If the toggle is green on the server, the user already granted perms
      // when they went live. Re-checking via permission_handler can return a
      // transient false negative (especially on Android 14+) and silently
      // drop the foreground notification, which is exactly the bug we hit.
      final mobility = (data['mobility_mode'] as String?) ?? 'mobile';
      await start(mobilityMode: mobility);
      _bootstrapDone = true;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ConsultantLiveService] bootstrap → started in $mobility mode');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ConsultantLiveService] bootstrap failed: $e');
      }
    } finally {
      _bootstrapInFlight = false;
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Service isolate entry point — annotated so AOT release builds keep the symbol.
// ──────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Default cadence — overridden by `updateMobility` event.
  Duration interval = const Duration(minutes: 10);
  Timer? tickTimer;

  service.on('updateMobility').listen((event) {
    final mode = (event?['mobility_mode'] as String?) ?? 'mobile';
    interval = mode == 'stationary'
        ? const Duration(minutes: 30)
        : const Duration(minutes: 10);
    tickTimer?.cancel();
    tickTimer = Timer.periodic(interval, (_) => _pingLocation(service));
    // Immediate first ping on start / mode change.
    _pingLocation(service);
  });

  service.on('stopService').listen((_) async {
    tickTimer?.cancel();
    await service.stopSelf();
  });

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "You're live on MedUnity",
      content: 'Matching you with nearby doctors. Tap to manage Go Live.',
    );
  }

  // Default ticker until `updateMobility` arrives (start() always sends it).
  tickTimer = Timer.periodic(interval, (_) => _pingLocation(service));
}

Future<void> _pingLocation(ServiceInstance service) async {
  try {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Don't burn battery waiting for a high-accuracy fix forever.
        timeLimit: Duration(seconds: 30),
      ),
    );
    final token = await _readToken();
    if (token == null) {
      // No session — bail and stop the service. User logged out.
      await service.stopSelf();
      return;
    }
    final dio = Dio(BaseOptions(
      baseUrl: _kApiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Authorization': 'Bearer $token'},
    ));
    final resp = await dio.post(
      '/consultants/me/location/',
      data: {'lat': pos.latitude, 'lng': pos.longitude},
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    // 409 means consultant toggled off elsewhere — stop the service.
    if (resp.statusCode == 409) {
      await service.stopSelf();
      return;
    }
  } catch (e) {
    // Swallow — next tick will retry. We don't want to crash the service.
    if (kDebugMode) {
      // ignore: avoid_print
      print('ConsultantLiveService ping failed: $e');
    }
  }
}

/// Open the encrypted Hive session box inside the service isolate and read
/// the access token. Re-opens fresh each call so token rotation is picked up.
Future<String?> _readToken() async {
  try {
    if (!Hive.isBoxOpen(_kSessionBox)) {
      await Hive.initFlutter();
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final encStr = await storage.read(key: _kEncKeyName);
      if (encStr == null) return null;
      final cipher = HiveAesCipher(base64Decode(encStr));
      await Hive.openBox(_kSessionBox, encryptionCipher: cipher);
    }
    return Hive.box(_kSessionBox).get('access_token') as String?;
  } catch (_) {
    return null;
  }
}

