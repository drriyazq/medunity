import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/client.dart';
import '../data/local/hive_setup.dart';

enum AuthStatus {
  loading,
  loggedOut,
  otpSent,
  tokenIssued,       // JWT received but no profile yet
  pendingVerification,
  rejected,
  verified,
}

class AuthState {
  final AuthStatus status;
  final String? rejectionReason;
  final bool clinicLocationSet;

  const AuthState({
    required this.status,
    this.rejectionReason,
    this.clinicLocationSet = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? rejectionReason,
    bool? clinicLocationSet,
  }) {
    return AuthState(
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      clinicLocationSet: clinicLocationSet ?? this.clinicLocationSet,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;

  AuthNotifier(this._ref) : super(const AuthState(status: AuthStatus.loading)) {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final token = HiveSetup.sessionBox.get('access_token') as String?;
    if (token == null) {
      state = const AuthState(status: AuthStatus.loggedOut);
      return;
    }
    // Token exists — check verification status
    await refreshVerificationStatus();
  }

  Future<void> onFirebaseTokenReceived(String firebaseIdToken) async {
    debugPrint('[Auth] onFirebaseTokenReceived START — token len: ${firebaseIdToken.length}');
    final dio = _ref.read(dioProvider);
    debugPrint('[Auth] Dio baseUrl: ${dio.options.baseUrl}');
    try {
      debugPrint('[Auth] POSTing to /auth/firebase/...');
      final resp = await dio.post('/auth/firebase/', data: {'id_token': firebaseIdToken});
      debugPrint('[Auth] Got response: status=${resp.statusCode} data=${resp.data}');
      await _onJwtIssued(resp.data);
    } catch (e, st) {
      debugPrint('[Auth] onFirebaseTokenReceived ERROR: $e');
      debugPrint('[Auth] Stacktrace: $st');
      state = const AuthState(status: AuthStatus.loggedOut);
    }
  }

  /// Send an OTP to an Indian phone via WhatsApp.
  /// Throws on network/server failure so the UI can show an error.
  Future<void> sendWhatsappOtp(String phone) async {
    final dio = _ref.read(dioProvider);
    debugPrint('[Auth] sendWhatsappOtp $phone');
    await dio.post('/auth/otp/send/', data: {'phone': phone});
  }

  /// Verify an OTP. Mirrors the JWT handoff used by the Firebase path.
  Future<void> verifyWhatsappOtp(String phone, String code) async {
    final dio = _ref.read(dioProvider);
    debugPrint('[Auth] verifyWhatsappOtp $phone');
    try {
      final resp = await dio.post('/auth/otp/verify/', data: {'phone': phone, 'code': code});
      await _onJwtIssued(resp.data);
    } catch (e, st) {
      debugPrint('[Auth] verifyWhatsappOtp ERROR: $e');
      debugPrint('[Auth] Stacktrace: $st');
      rethrow;
    }
  }

  Future<void> _onJwtIssued(dynamic data) async {
    HiveSetup.sessionBox.put('access_token', data['access']);
    HiveSetup.sessionBox.put('refresh_token', data['refresh']);
    if (data['uid'] != null) {
      HiveSetup.sessionBox.put('verified_phone', data['uid']);
    }
    if (data['profile_exists'] == true) {
      await refreshVerificationStatus();
    } else {
      state = const AuthState(status: AuthStatus.tokenIssued);
    }
  }

  Future<void> onProfileCreated() async {
    state = const AuthState(status: AuthStatus.pendingVerification);
  }

  Future<void> refreshVerificationStatus() async {
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/auth/verification-status/');
      final vstatus = resp.data['status'] as String?;
      final reason = resp.data['reason'] as String?;
      final locationSet = resp.data['clinic_location_set'] as bool? ?? false;

      switch (vstatus) {
        case 'verified':
          state = AuthState(status: AuthStatus.verified, clinicLocationSet: locationSet);
        case 'rejected':
          state = AuthState(status: AuthStatus.rejected, rejectionReason: reason);
        case 'no_profile':
          state = const AuthState(status: AuthStatus.tokenIssued);
        default:
          state = AuthState(status: AuthStatus.pendingVerification, clinicLocationSet: locationSet);
      }
    } on DioException catch (e) {
      // Only log out on a real auth failure. For network/server hiccups on
      // cold start, keep the token and surface a "pending" UI so the user
      // can retry without re-doing OTP.
      if (e.response?.statusCode == 401) {
        await logout();
      } else {
        debugPrint('[Auth] refreshVerificationStatus transient error: $e');
        state = const AuthState(status: AuthStatus.pendingVerification);
      }
    } catch (e) {
      debugPrint('[Auth] refreshVerificationStatus unexpected: $e');
      state = const AuthState(status: AuthStatus.pendingVerification);
    }
  }

  Future<void> logout() async {
    await HiveSetup.sessionBox.delete('access_token');
    await HiveSetup.sessionBox.delete('refresh_token');
    state = const AuthState(status: AuthStatus.loggedOut);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);
