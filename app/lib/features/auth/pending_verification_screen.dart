import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_provider.dart';
import '../../theme.dart';

class PendingVerificationScreen extends ConsumerStatefulWidget {
  const PendingVerificationScreen({super.key});

  @override
  ConsumerState<PendingVerificationScreen> createState() => _PendingVerificationScreenState();
}

class _PendingVerificationScreenState extends ConsumerState<PendingVerificationScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Poll every 60 s while this screen is visible
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      ref.read(authProvider.notifier).refreshVerificationStatus();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 72, color: MedUnityColors.primary),
              const SizedBox(height: 24),
              Text(
                'Verification in Progress',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Your license and documents are under review by our team. '
                'This typically takes less than 24 hours.\n\n'
                'You\'ll receive a notification once your profile is approved.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: MedUnityColors.textSecondary,
                ),
              ),
              const SizedBox(height: 48),
              OutlinedButton.icon(
                onPressed: () => ref.read(authProvider.notifier).refreshVerificationStatus(),
                icon: const Icon(Icons.refresh),
                label: const Text('Check Status'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => ref.read(authProvider.notifier).logout(),
                child: const Text('Sign Out', style: TextStyle(color: MedUnityColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
