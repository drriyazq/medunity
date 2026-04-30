import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

// ── Vendors list (paginated) ──────────────────────────────────────────────────

class VendorsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  int _page = 1;
  bool _hasMore = true;

  VendorsNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load({
    bool refresh = false,
    String category = '',
    String city = '',
    String sort = 'rating',
  }) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      state = const AsyncValue.loading();
    }
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/vendors/', queryParameters: {
        'page': _page,
        if (category.isNotEmpty) 'category': category,
        if (city.isNotEmpty) 'city': city,
        'sort': sort,
      });
      final results = (resp.data['results'] as List).cast<Map<String, dynamic>>();
      _hasMore = resp.data['has_more'] as bool? ?? false;
      final existing = refresh ? <Map<String, dynamic>>[] : (state.valueOrNull ?? []);
      state = AsyncValue.data([...existing, ...results]);
    } catch (e, st) {
      if (state.valueOrNull == null) state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore({String category = '', String city = '', String sort = 'rating'}) async {
    if (!_hasMore) return;
    _page++;
    await load(category: category, city: city, sort: sort);
  }

  bool get hasMore => _hasMore;

  void prependVendor(Map<String, dynamic> v) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([v, ...current]);
  }
}

final vendorsProvider =
    StateNotifierProvider.autoDispose<VendorsNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => VendorsNotifier(ref),
);

// ── Search ────────────────────────────────────────────────────────────────────

class VendorSearchNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  VendorSearchNotifier(this._ref) : super(const AsyncValue.data([]));

  Future<void> search(String q, {String city = ''}) async {
    if (q.isEmpty) { state = const AsyncValue.data([]); return; }
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/vendors/search/', queryParameters: {
        'q': q,
        if (city.isNotEmpty) 'city': city,
      });
      final list = (resp.data['results'] as List).cast<Map<String, dynamic>>();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void clear() => state = const AsyncValue.data([]);
}

final vendorSearchProvider =
    StateNotifierProvider.autoDispose<VendorSearchNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => VendorSearchNotifier(ref),
);

// ── Vendor detail ─────────────────────────────────────────────────────────────

final vendorDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/vendors/$id/');
  return Map<String, dynamic>.from(resp.data as Map);
});
