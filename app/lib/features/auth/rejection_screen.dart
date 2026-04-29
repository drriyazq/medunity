import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_provider.dart';
import '../../theme.dart';

class RejectionScreen extends ConsumerWidget {
  final String? reason;
  const RejectionScreen({super.key, this.reason});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cancel_outlined, size: 72, color: MedUnityColors.sos),
              const SizedBox(height: 24),
              Text(
                'Profile Not Approved',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MedUnityColors.sosLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MedUnityColors.sos.withOpacity(0.3)),
                  ),
                  child: Text(reason!, style: const TextStyle(color: MedUnityColors.sos)),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/onboarding/profile'),
                  child: const Text('Resubmit Documents'),
                ),
              ),
              const SizedBox(height: 12),
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
