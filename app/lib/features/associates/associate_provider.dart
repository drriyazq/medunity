import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

// ── My MedicalProfessional + clinic snapshot ──────────────────────────────────
// Used by associates screens to know where the searcher is. Cheap enough to
// have its own family — Riverpod auto-dedupes simultaneous reads.

final myProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/auth/me/');
  return Map<String, dynamic>.from(resp.data as Map);
});

// ── My associate profile ──────────────────────────────────────────────────────

final myAssociateProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/associates/me/');
  return Map<String, dynamic>.from(resp.data as Map);
});

class AssociateProfileNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final Ref _ref;
  AssociateProfileNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/associates/me/');
      state = AsyncValue.data(Map<String, dynamic>.from(resp.data as Map));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> save(Map<String, dynamic> patch) async {
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.patch('/associates/me/', data: patch);
      state = AsyncValue.data(Map<String, dynamic>.from(resp.data as Map));
      _ref.invalidate(myAssociateProfileProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggle({bool? newValue}) async {
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.post('/associates/me/toggle/', data: {
        if (newValue != null) 'is_available_for_hire': newValue,
      });
      state = AsyncValue.data(Map<String, dynamic>.from(resp.data as Map));
      _ref.invalidate(myAssociateProfileProvider);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final associateProfileNotifierProvider = StateNotifierProvider.autoDispose<
    AssociateProfileNotifier, AsyncValue<Map<String, dynamic>>>(
  (ref) => AssociateProfileNotifier(ref),
);

// ── Search ────────────────────────────────────────────────────────────────────

class AssociateSearchArgs {
  final double lat;
  final double lng;
  final String? slotKind;
  final String sort;
  final String? maxRate;

  const AssociateSearchArgs({
    required this.lat,
    required this.lng,
    this.slotKind,
    this.sort = 'distance',
    this.maxRate,
  });

  @override
  bool operator ==(Object other) =>
      other is AssociateSearchArgs &&
      other.lat == lat &&
      other.lng == lng &&
      other.slotKind == slotKind &&
      other.sort == sort &&
      other.maxRate == maxRate;

  @override
  int get hashCode => Object.hash(lat, lng, slotKind, sort, maxRate);
}

final associateSearchProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, AssociateSearchArgs>((ref, args) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/associates/search/', queryParameters: {
    'lat': args.lat,
    'lng': args.lng,
    'sort': args.sort,
    if (args.slotKind != null) 'slot_kind': args.slotKind,
    if (args.maxRate != null && args.maxRate!.isNotEmpty)
      'max_rate': args.maxRate,
  });
  final list = (resp.data['associates'] as List? ?? []);
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

// ── Public profile + reviews ──────────────────────────────────────────────────

final publicDoctorProfileProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, profId) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/associates/$profId/');
  return Map<String, dynamic>.from(resp.data as Map);
});

class ReviewsArgs {
  final int profId;
  final String? context;
  const ReviewsArgs(this.profId, this.context);
  @override
  bool operator ==(Object other) =>
      other is ReviewsArgs &&
      other.profId == profId &&
      other.context == context;
  @override
  int get hashCode => Object.hash(profId, context);
}

final reviewsForProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ReviewsArgs>((ref, args) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get(
    '/reviews/of/${args.profId}/',
    queryParameters: {if (args.context != null) 'context': args.context},
  );
  return Map<String, dynamic>.from(resp.data as Map);
});

final myReviewForProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, ReviewsArgs>((ref, args) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get(
    '/reviews/mine/of/${args.profId}/',
    queryParameters: {'context': args.context ?? 'general'},
  );
  final r = resp.data['review'];
  if (r == null) return null;
  return Map<String, dynamic>.from(r as Map);
});

// ── Bookings ──────────────────────────────────────────────────────────────────

final myAssociateBookingsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, asRole) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/associates/bookings/',
      queryParameters: {'as': asRole});
  final list = (resp.data['bookings'] as List? ?? []);
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

final associateBookingDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, bookingId) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/associates/bookings/$bookingId/');
  return Map<String, dynamic>.from(resp.data as Map);
});
