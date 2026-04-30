import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/api/client.dart';
import '../../state/auth_provider.dart';

/// Captures the device's current GPS, POSTs it to /auth/me/clinic-location/,
/// and refreshes the auth state so consult/SOS screens unlock.
/// Returns true on success. Shows snackbars on the supplied [context].
Future<bool> setClinicLocationFromGps(BuildContext context, WidgetRef ref) async {
  void snack(String msg) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // Permission check
  final serviceOk = await Geolocator.isLocationServiceEnabled();
  if (!serviceOk) {
    snack('Location services are off. Enable GPS and try again.');
    return false;
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied) {
    snack('Location permission denied.');
    return false;
  }
  if (perm == LocationPermission.deniedForever) {
    snack('Location permission permanently denied. Enable it in Settings.');
    return false;
  }

  // Capture position
  Position pos;
  try {
    pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  } catch (_) {
    snack('Could not read GPS. Try again outdoors.');
    return false;
  }

  // POST
  final dio = ref.read(dioProvider);
  try {
    await dio.post('/auth/me/clinic-location/', data: {
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
  } on DioException catch (e) {
    snack(e.response?.data?['detail']?.toString() ?? 'Could not save location.');
    return false;
  } catch (_) {
    snack('Could not save location.');
    return false;
  }

  await ref.read(authProvider.notifier).refreshVerificationStatus();
  snack('Clinic location saved.');
  return true;
}
