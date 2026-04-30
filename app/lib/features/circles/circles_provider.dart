import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

// ── My circles ────────────────────────────────────────────────────────────────

class MyCirclesNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  MyCirclesNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/circles/');
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final myCirclesProvider =
    StateNotifierProvider.autoDispose<MyCirclesNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => MyCirclesNotifier(ref),
);

// ── Nearby circles ────────────────────────────────────────────────────────────

final nearbyCirclesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/circles/nearby/');
  return (resp.data as List).cast<Map<String, dynamic>>();
});

// ── Circle detail ─────────────────────────────────────────────────────────────

final circleDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/circles/$id/');
  return Map<String, dynamic>.from(resp.data as Map);
});

// ── Posts ─────────────────────────────────────────────────────────────────────

class PostsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  final int circleId;
  int _page = 1;
  bool _hasMore = true;

  PostsNotifier(this._ref, this.circleId) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      state = const AsyncValue.loading();
    }
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/circles/$circleId/posts/', queryParameters: {'page': _page});
      final results = (resp.data['results'] as List).cast<Map<String, dynamic>>();
      _hasMore = resp.data['has_more'] as bool? ?? false;
      final existing = refresh ? <Map<String, dynamic>>[] : (state.valueOrNull ?? []);
      state = AsyncValue.data([...existing, ...results]);
    } catch (e, st) {
      if (state.valueOrNull == null) state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    _page++;
    await load();
  }

  bool get hasMore => _hasMore;

  void prependPost(Map<String, dynamic> post) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([post, ...current]);
  }

  void removePost(int postId) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((p) => p['id'] != postId).toList());
  }
}

final postsProvider =
    StateNotifierProvider.autoDispose.family<PostsNotifier, AsyncValue<List<Map<String, dynamic>>>, int>(
  (ref, circleId) => PostsNotifier(ref, circleId),
);

// ── Comments ──────────────────────────────────────────────────────────────────

class CommentsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  final int circleId;
  final int postId;

  CommentsNotifier(this._ref, this.circleId, this.postId)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/circles/$circleId/posts/$postId/comments/');
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void appendComment(Map<String, dynamic> comment) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([...current, comment]);
  }

  void removeComment(int commentId) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((c) => c['id'] != commentId).toList());
  }
}

final commentsProvider = StateNotifierProvider.autoDispose
    .family<CommentsNotifier, AsyncValue<List<Map<String, dynamic>>>, ({int circleId, int postId})>(
  (ref, ids) => CommentsNotifier(ref, ids.circleId, ids.postId),
);
