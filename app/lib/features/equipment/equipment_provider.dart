import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

// ── Pools ─────────────────────────────────────────────────────────────────────

class PoolsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  PoolsNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load({String category = ''}) async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/equipment/pools/', queryParameters: {
        if (category.isNotEmpty) 'category': category,
      });
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void prependPool(Map<String, dynamic> pool) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([pool, ...current]);
  }

  void updatePool(Map<String, dynamic> updated) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([
      for (final p in current)
        if (p['id'] == updated['id']) updated else p
    ]);
  }
}

final poolsProvider =
    StateNotifierProvider.autoDispose<PoolsNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => PoolsNotifier(ref),
);

final poolDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/equipment/pools/$id/');
  return Map<String, dynamic>.from(resp.data as Map);
});

final poolSlotsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, int>((ref, poolId) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/equipment/pools/$poolId/slots/');
  return (resp.data as List).cast<Map<String, dynamic>>();
});

// ── Marketplace ───────────────────────────────────────────────────────────────

class ListingsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  int _page = 1;
  bool _hasMore = true;

  ListingsNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load({bool refresh = false, String category = ''}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      state = const AsyncValue.loading();
    }
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/equipment/listings/', queryParameters: {
        'page': _page,
        if (category.isNotEmpty) 'category': category,
      });
      final results = (resp.data['results'] as List).cast<Map<String, dynamic>>();
      _hasMore = resp.data['has_more'] as bool? ?? false;
      final existing = refresh ? <Map<String, dynamic>>[] : (state.valueOrNull ?? []);
      state = AsyncValue.data([...existing, ...results]);
    } catch (e, st) {
      if (state.valueOrNull == null) state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore(String category) async {
    if (!_hasMore) return;
    _page++;
    await load(category: category);
  }

  bool get hasMore => _hasMore;

  void prependListing(Map<String, dynamic> l) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([l, ...current]);
  }

  void removeListing(int id) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((l) => l['id'] != id).toList());
  }
}

final listingsProvider =
    StateNotifierProvider.autoDispose<ListingsNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => ListingsNotifier(ref),
);

final listingDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/equipment/listings/$id/');
  return Map<String, dynamic>.from(resp.data as Map);
});

final myListingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/equipment/listings/mine/');
  return (resp.data as List).cast<Map<String, dynamic>>();
});
