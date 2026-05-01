import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_provider.dart';
import '../../theme.dart';

class PhoneSignInScreen extends ConsumerStatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  ConsumerState<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends ConsumerState<PhoneSignInScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _verificationId;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  bool get _isIndianPhone => _phoneCtrl.text.trim().startsWith('+91');

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (!phone.startsWith('+') || phone.length < 10) {
      setState(() => _error = 'Enter a valid phone number with country code (e.g. +919876543210)');
      return;
    }
    setState(() { _loading = true; _error = null; });

    if (_isIndianPhone) {
      await _sendWhatsappOtp(phone);
    } else {
      await _sendFirebaseOtp(phone);
    }
  }

  // ── WhatsApp OTP path (+91) ──────────────────────────────────────────────

  Future<void> _sendWhatsappOtp(String phone) async {
    try {
      await ref.read(authProvider.notifier).sendWhatsappOtp(phone);
      setState(() { _loading = false; _otpSent = true; });
    } catch (e) {
      debugPrint('[SignIn] sendWhatsappOtp error: $e');
      setState(() { _loading = false; _error = 'Could not send OTP. Please try again.'; });
    }
  }

  Future<void> _verifyWhatsappOtp() async {
    final phone = _phoneCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).verifyWhatsappOtp(phone, otp);
    } catch (e) {
      debugPrint('[SignIn] verifyWhatsappOtp error: $e');
      final msg = e.toString().contains('400') ? 'Incorrect or expired code.' : 'Verification failed. Try again.';
      setState(() { _loading = false; _error = msg; });
    }
  }

  // ── Firebase OTP path (non-India fallback) ───────────────────────────────

  Future<void> _sendFirebaseOtp(String phone) async {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        await _signInWithFirebaseCredential(credential);
      },
      verificationFailed: (e) {
        setState(() { _loading = false; _error = 'Verification failed: ${e.message}'; });
      },
      codeSent: (verificationId, _) {
        setState(() {
          _loading = false;
          _otpSent = true;
          _verificationId = verificationId;
        });
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _verifyFirebaseOtp() async {
    if (_verificationId == null) return;
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: otp,
    );
    await _signInWithFirebaseCredential(credential);
  }

  Future<void> _signInWithFirebaseCredential(PhoneAuthCredential credential) async {
    debugPrint('[SignIn] _signInWithFirebaseCredential called');
    try {
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await result.user?.getIdToken();
      if (idToken == null) throw Exception('No ID token');
      await ref.read(authProvider.notifier).onFirebaseTokenReceived(idToken);
    } catch (e, st) {
      debugPrint('[SignIn] Firebase ERROR: $e');
      debugPrint('[SignIn] Stack: $st');
      setState(() { _loading = false; _error = 'Sign-in failed: $e'; });
    }
  }

  // ── Dispatch ─────────────────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    if (_isIndianPhone) {
      await _verifyWhatsappOtp();
    } else {
      await _verifyFirebaseOtp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text('Sign In', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold, color: MedUnityColors.primary,
              )),
              const SizedBox(height: 8),
              Text(
                _otpSent
                    ? 'Enter the OTP sent to ${_phoneCtrl.text}${_isIndianPhone ? ' via WhatsApp' : ''}'
                    : 'Enter your phone number to receive an OTP.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: MedUnityColors.textSecondary),
              ),
              const SizedBox(height: 32),
              if (!_otpSent) ...[
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+919876543210',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'OTP',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() { _otpSent = false; _otpCtrl.clear(); }),
                  child: const Text('Change number'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: MedUnityColors.sos)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : (_otpSent ? _verifyOtp : _sendOtp),
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_otpSent ? 'Verify OTP' : 'Send OTP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
