import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import 'live_provider.dart';

class VisibilitySettingsScreen extends ConsumerWidget {
  const VisibilitySettingsScreen({super.key});

  Future<void> _setMode(WidgetRef ref, BuildContext ctx, String mode) async {
    final ok = await ref
        .read(liveSettingsProvider.notifier)
        .save({'visibility_mode': mode});
    if (!ctx.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Could not update.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Who can find you')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load settings.')),
        data: (s) {
          final mode = (s['visibility_mode'] as String?) ?? 'open';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RadioListTile<String>(
                value: 'open',
                groupValue: mode,
                onChanged: (v) =>
                    v == null ? null : _setMode(ref, context, v),
                title: const Text('Open',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'All doctors matching your specialty in your radius can find you. '
                    'You can decline + block specific doctors when their requests come in.'),
              ),
              RadioListTile<String>(
                value: 'allowlist',
                groupValue: mode,
                onChanged: (v) =>
                    v == null ? null : _setMode(ref, context, v),
                title: const Text('Allowlist',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Only doctors you have explicitly added can find you. '
                    'Everyone else sees no consultants nearby.'),
              ),
              const Divider(height: 32),
              if (mode == 'allowlist')
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.checklist_rounded,
                        color: MedUnityColors.primary),
                    title: const Text('Manage allowlist'),
                    subtitle:
                        const Text('Doctors who are allowed to find you'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.push('/consultants/manage-list/allowlist'),
                  ),
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.block, color: Colors.red),
                  title: const Text('Manage blocklist'),
                  subtitle:
                      const Text('Doctors you have blocked from finding you'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push('/consultants/manage-list/blocklist'),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: const Text(
                  'Tip: Adding a doctor to your allowlist also removes them from your blocklist (and vice-versa).',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
