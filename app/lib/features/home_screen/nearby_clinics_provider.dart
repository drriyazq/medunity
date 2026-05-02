import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

/// Nearby clinic_owner / hospital_owner profiles for the role-driven Home
/// previews on consultants + associate doctors. Distance is bucketed
/// server-side (no exact coords leaked).
///
/// Defaults to clinic GPS as the anchor; consumers can pass a different
/// lat/lng if they have one (rare on Home, but plumbed for future use).
final nearbyClinicsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final resp = await dio.get('/auth/nearby-clinics/', queryParameters: {
      'kind': 'both',
      'radius_km': 10,
    });
    return (resp.data as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
});
