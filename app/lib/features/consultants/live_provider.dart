import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

// ── Live settings (mobility, schedule, radius, visibility) ───────────────────

class LiveSettingsNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final Ref _ref;
  LiveSettingsNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/consultants/me/settings/');
      state = AsyncValue.data(Map<String, dynamic>.from(resp.data as Map));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> save(Map<String, dynamic> patch) async {
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.patch('/consultants/me/settings/', data: patch);
      state = AsyncValue.data(Map<String, dynamic>.from(resp.data as Map));
      return true;
    } catch (_) {
      return false;
    }
  }
}

final liveSettingsProvider = StateNotifierProvider.autoDispose<
    LiveSettingsNotifier, AsyncValue<Map<String, dynamic>>>(
  (ref) => LiveSettingsNotifier(ref),
);

// ── Blocklist + Allowlist ─────────────────────────────────────────────────────

enum ConsultantListKind { blocklist, allowlist }

extension on ConsultantListKind {
  String get path =>
      this == ConsultantListKind.blocklist ? 'blocklist' : 'allowlist';
}

class ConsultantListNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  final ConsultantListKind kind;
  ConsultantListNotifier(this._ref, this.kind)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/consultants/me/${kind.path}/');
      state = AsyncValue.data((resp.data as List).cast<Map<String, dynamic>>());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Add by phone OR doctor_id. Returns the doctor card on success, null on failure.
  Future<Map<String, dynamic>?> add({String? phone, int? doctorId}) async {
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.post('/consultants/me/${kind.path}/', data: {
        if (phone != null) 'phone': phone,
        if (doctorId != null) 'doctor_id': doctorId,
      });
      await load();
      return Map<String, dynamic>.from(resp.data['doctor'] as Map);
    } catch (_) {
      return null;
    }
  }

  Future<bool> remove(int doctorId) async {
    final dio = _ref.read(dioProvider);
    try {
      await dio.delete('/consultants/me/${kind.path}/',
          data: {'doctor_id': doctorId});
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final blocklistProvider = StateNotifierProvider.autoDispose<
    ConsultantListNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => ConsultantListNotifier(ref, ConsultantListKind.blocklist),
);

final allowlistProvider = StateNotifierProvider.autoDispose<
    ConsultantListNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => ConsultantListNotifier(ref, ConsultantListKind.allowlist),
);

// ── Phone lookup ──────────────────────────────────────────────────────────────

Future<Map<String, dynamic>?> lookupDoctorByPhone(Ref ref, String phone) async {
  final dio = ref.read(dioProvider);
  try {
    final resp = await dio.get('/consultants/lookup-by-phone/',
        queryParameters: {'phone': phone});
    return Map<String, dynamic>.from(resp.data as Map);
  } catch (_) {
    return null;
  }
}
