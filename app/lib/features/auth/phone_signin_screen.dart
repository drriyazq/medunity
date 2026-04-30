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

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (!phone.startsWith('+') || phone.length < 10) {
      setState(() => _error = 'Enter a valid phone number with country code (e.g. +919876543210)');
      return;
    }
    setState(() { _loading = true; _error = null; });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        // Auto-verification (Android only)
        await _signInWithCredential(credential);
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

  Future<void> _verifyOtp() async {
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
    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    debugPrint('[SignIn] _signInWithCredential called');
    try {
      debugPrint('[SignIn] calling signInWithCredential...');
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      debugPrint('[SignIn] got user: ${result.user?.uid}');
      final idToken = await result.user?.getIdToken();
      debugPrint('[SignIn] got idToken: ${idToken?.length} chars');
      if (idToken == null) throw Exception('No ID token');
      await ref.read(authProvider.notifier).onFirebaseTokenReceived(idToken);
      debugPrint('[SignIn] onFirebaseTokenReceived returned');
    } catch (e, st) {
      debugPrint('[SignIn] ERROR: $e');
      debugPrint('[SignIn] Stack: $st');
      setState(() { _loading = false; _error = 'Sign-in failed: $e'; });
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
                _otpSent ? 'Enter the OTP sent to ${_phoneCtrl.text}' : 'Enter your phone number to receive an OTP.',
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
