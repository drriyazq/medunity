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
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.post('/auth/firebase/', data: {'id_token': firebaseIdToken});
      HiveSetup.sessionBox.put('access_token', resp.data['access']);
      HiveSetup.sessionBox.put('refresh_token', resp.data['refresh']);

      if (resp.data['profile_exists'] == true) {
        await refreshVerificationStatus();
      } else {
        state = const AuthState(status: AuthStatus.tokenIssued);
      }
    } catch (e) {
      debugPrint('[Auth] onFirebaseTokenReceived error: $e');
      state = const AuthState(status: AuthStatus.loggedOut);
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
    } catch (_) {
      // Token may be expired — treat as logged out
      await logout();
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
