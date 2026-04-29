import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';

/// DPDP Act 2023 compliant consent screen — first screen on launch.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _dataProcessingAccepted = false;

  bool get _canProceed => _termsAccepted && _privacyAccepted && _dataProcessingAccepted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Text(
                'Welcome to MedUnity',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: MedUnityColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A private network for verified medical professionals.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: MedUnityColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              _ConsentTile(
                value: _termsAccepted,
                onChanged: (v) => setState(() => _termsAccepted = v ?? false),
                text: 'I agree to the Terms of Service',
              ),
              _ConsentTile(
                value: _privacyAccepted,
                onChanged: (v) => setState(() => _privacyAccepted = v ?? false),
                text: 'I have read and accept the Privacy Policy',
              ),
              _ConsentTile(
                value: _dataProcessingAccepted,
                onChanged: (v) => setState(() => _dataProcessingAccepted = v ?? false),
                text: 'I consent to processing of my professional and contact data '
                    'as described in the Privacy Policy (DPDP Act 2023)',
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canProceed ? () => context.go('/home') : null,
                  child: const Text('Continue'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String text;

  const _ConsentTile({required this.value, required this.onChanged, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: value, onChanged: onChanged),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
