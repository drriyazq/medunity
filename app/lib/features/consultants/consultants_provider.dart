import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

// ── My availability ───────────────────────────────────────────────────────────

class AvailabilityNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final Ref _ref;
  AvailabilityNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/consultants/availability/');
      state = AsyncValue.data(Map<String, dynamic>.from(resp.data as Map));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> toggle({required bool available, double? lat, double? lng}) async {
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.post('/consultants/availability/', data: {
        'is_available': available,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });
      state = AsyncValue.data({
        ...(state.valueOrNull ?? {}),
        'is_available': resp.data['is_available'],
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

final availabilityProvider =
    StateNotifierProvider.autoDispose<AvailabilityNotifier, AsyncValue<Map<String, dynamic>>>(
  (ref) => AvailabilityNotifier(ref),
);

// ── Nearby consultants ────────────────────────────────────────────────────────

class NearbyConsultantsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  NearbyConsultantsNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load({String? specialization, double radiusKm = 10}) async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/consultants/nearby/', queryParameters: {
        'radius_km': radiusKm,
        if (specialization != null && specialization.isNotEmpty)
          'specialization': specialization,
      });
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final nearbyConsultantsProvider = StateNotifierProvider.autoDispose<
    NearbyConsultantsNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => NearbyConsultantsNotifier(ref),
);

// ── Consultant profile ────────────────────────────────────────────────────────

final consultantProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, profId) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/consultants/profile/$profId/');
  return Map<String, dynamic>.from(resp.data as Map);
});

// ── My bookings ───────────────────────────────────────────────────────────────

class BookingsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  final String role; // 'requester' | 'consultant' | 'all'

  BookingsNotifier(this._ref, this.role) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/consultants/bookings/', queryParameters: {'role': role});
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void updateBooking(Map<String, dynamic> updated) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([
      for (final b in current)
        if (b['id'] == updated['id']) updated else b
    ]);
  }
}

final myBookingsProvider =
    StateNotifierProvider.autoDispose.family<BookingsNotifier,
        AsyncValue<List<Map<String, dynamic>>>, String>(
  (ref, role) => BookingsNotifier(ref, role),
);
