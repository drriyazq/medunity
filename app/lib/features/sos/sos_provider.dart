import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

// ── State ─────────────────────────────────────────────────────────────────────

enum SosSendStatus { idle, sending, success, throttled, error }

class SosSendState {
  final SosSendStatus status;
  final int? alertId;
  final int? recipientCount;
  final double? radiusKm;
  final String? errorMessage;

  const SosSendState({
    this.status = SosSendStatus.idle,
    this.alertId,
    this.recipientCount,
    this.radiusKm,
    this.errorMessage,
  });

  SosSendState copyWith({
    SosSendStatus? status,
    int? alertId,
    int? recipientCount,
    double? radiusKm,
    String? errorMessage,
  }) =>
      SosSendState(
        status: status ?? this.status,
        alertId: alertId ?? this.alertId,
        recipientCount: recipientCount ?? this.recipientCount,
        radiusKm: radiusKm ?? this.radiusKm,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SosSendNotifier extends StateNotifier<SosSendState> {
  final Ref _ref;

  SosSendNotifier(this._ref) : super(const SosSendState());

  Future<void> sendSos({
    required String category,
    required double lat,
    required double lng,
    List<int>? recipientIds,
  }) async {
    state = const SosSendState(status: SosSendStatus.sending);
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.post('/sos/send/', data: {
        'category': category,
        'lat': lat,
        'lng': lng,
        if (recipientIds != null) 'recipient_ids': recipientIds,
      });
      state = SosSendState(
        status: SosSendStatus.success,
        alertId: resp.data['alert_id'] as int,
        recipientCount: resp.data['recipient_count'] as int,
        radiusKm: (resp.data['radius_km'] as num).toDouble(),
      );
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('429')) {
        state = const SosSendState(
          status: SosSendStatus.throttled,
          errorMessage: 'You can only send 3 SOS alerts per 24 hours.',
        );
      } else {
        state = SosSendState(
          status: SosSendStatus.error,
          errorMessage: 'Could not send SOS. Please try again.',
        );
      }
    }
  }

  void reset() => state = const SosSendState();
}

final sosSendProvider = StateNotifierProvider.autoDispose<SosSendNotifier, SosSendState>(
  (ref) => SosSendNotifier(ref),
);

// ── Status (polling) ──────────────────────────────────────────────────────────

class SosStatusNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final Ref _ref;
  final int alertId;

  SosStatusNotifier(this._ref, this.alertId) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/sos/$alertId/status/');
      state = AsyncValue.data(Map<String, dynamic>.from(resp.data as Map));
    } catch (e, st) {
      // Keep last good data on poll failures so the UI doesn't flicker.
      if (state is! AsyncData) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

final sosStatusProvider = StateNotifierProvider.autoDispose
    .family<SosStatusNotifier, AsyncValue<Map<String, dynamic>>, int>(
  (ref, alertId) => SosStatusNotifier(ref, alertId),
);

// ── Nearby doctors (for SOS recipient picker) ─────────────────────────────────

class NearbyDoctorsArgs {
  final double lat;
  final double lng;
  const NearbyDoctorsArgs(this.lat, this.lng);
  @override
  bool operator ==(Object other) =>
      other is NearbyDoctorsArgs && other.lat == lat && other.lng == lng;
  @override
  int get hashCode => Object.hash(lat, lng);
}

final nearbyDoctorsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, NearbyDoctorsArgs>((ref, args) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/sos/nearby-doctors/', queryParameters: {
    'lat': args.lat,
    'lng': args.lng,
  });
  return Map<String, dynamic>.from(resp.data as Map);
});

// ── My alerts (dashboard) ─────────────────────────────────────────────────────

final myAlertsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/sos/my-alerts/');
  final list = (resp.data['alerts'] as List? ?? []);
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

// ── Incoming SOS ──────────────────────────────────────────────────────────────

final incomingSosProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, alertId) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/sos/$alertId/incoming/');
  return Map<String, dynamic>.from(resp.data as Map);
});

// ── Respond ───────────────────────────────────────────────────────────────────

class SosRespondNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  SosRespondNotifier(this._ref) : super(const AsyncValue.data(null));

  Future<void> respond({
    required int alertId,
    required String status,
    double? lat,
    double? lng,
  }) async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      await dio.post('/sos/$alertId/respond/', data: {
        'status': status,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final sosRespondProvider =
    StateNotifierProvider.autoDispose<SosRespondNotifier, AsyncValue<void>>(
  (ref) => SosRespondNotifier(ref),
);
