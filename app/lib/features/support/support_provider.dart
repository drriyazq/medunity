import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

// ── Coverage requests ─────────────────────────────────────────────────────────

class RequestsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  RequestsNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load({String type = '', String city = ''}) async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/support/requests/', queryParameters: {
        if (type.isNotEmpty) 'type': type,
        if (city.isNotEmpty) 'city': city,
      });
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void prependRequest(Map<String, dynamic> req) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([req, ...current]);
  }

  void updateRequest(Map<String, dynamic> updated) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([
      for (final r in current)
        if (r['id'] == updated['id']) updated else r
    ]);
  }

  void removeRequest(int id) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((r) => r['id'] != id).toList());
  }
}

final requestsProvider =
    StateNotifierProvider.autoDispose<RequestsNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => RequestsNotifier(ref),
);

final myRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/support/requests/mine/');
  return (resp.data as List).cast<Map<String, dynamic>>();
});

// ── Points + leaderboard ──────────────────────────────────────────────────────

final myPointsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/support/my-points/');
  return Map<String, dynamic>.from(resp.data as Map);
});

final leaderboardProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/support/leaderboard/');
  return (resp.data as List).cast<Map<String, dynamic>>();
});
