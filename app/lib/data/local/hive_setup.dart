import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Single entry point for MedUnity local storage.
/// Sensitive boxes are AES-256 encrypted with a key held in Android Keystore.
class HiveSetup {
  static const _session = 'medunity_session';
  // Phase 1+: professional, circles, equipment boxes added here
  static const _encKeyName = 'medunity_hive_key_v1';

  static Future<void> init() async {
    await Hive.initFlutter();
    // Phase 1+: register TypeAdapters here

    final encKey = await _readOrCreateEncryptionKey();
    final cipher = HiveAesCipher(encKey);

    await Future.wait([
      Hive.openBox(_session, encryptionCipher: cipher),
    ]);
  }

  static Future<List<int>> _readOrCreateEncryptionKey() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final existing = await storage.read(key: _encKeyName);
    if (existing != null) return base64Decode(existing);
    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await storage.write(key: _encKeyName, value: base64Encode(key));
    return key;
  }

  static Box get sessionBox => Hive.box(_session);
}
