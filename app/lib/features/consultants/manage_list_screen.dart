import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import 'live_provider.dart';

class ManageListScreen extends ConsumerStatefulWidget {
  final ConsultantListKind kind;
  const ManageListScreen({super.key, required this.kind});

  @override
  ConsumerState<ManageListScreen> createState() => _ManageListScreenState();
}

class _ManageListScreenState extends ConsumerState<ManageListScreen> {
  final _phoneCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  AutoDisposeStateNotifierProvider<ConsultantListNotifier,
          AsyncValue<List<Map<String, dynamic>>>>
      get _provider => widget.kind == ConsultantListKind.blocklist
          ? blocklistProvider
          : allowlistProvider;

  String get _title => widget.kind == ConsultantListKind.blocklist
      ? 'Blocklist'
      : 'Allowlist';

  String get _emptyText => widget.kind == ConsultantListKind.blocklist
      ? 'You have not blocked any doctors yet.'
      : 'No doctors approved yet. Add a doctor below to let them find you.';

  Future<void> _add() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() => _adding = true);
    try {
      // Look up first to confirm doctor exists, then add
      final card = await lookupDoctorByPhone(ref, phone);
      if (card == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No verified doctor found with that phone number.'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(_title == 'Blocklist'
              ? 'Block this doctor?'
              : 'Allow this doctor?'),
          content: Text(
              '${card['full_name']} (${card['specialization']})\n${card['phone']}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('CONFIRM')),
          ],
        ),
      );
      if (confirm != true) return;
      final added = await ref
          .read(_provider.notifier)
          .add(doctorId: card['id'] as int);
      if (!mounted) return;
      if (added != null) {
        _phoneCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Added ${added['full_name']}.'),
          backgroundColor: Colors.green,
        ));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> doc) async {
    final ok = await ref
        .read(_provider.notifier)
        .remove(doc['id'] as int);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Removed ${doc['full_name']}.' : 'Could not remove.'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_provider);
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Column(
        children: [
          // Add row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Doctor phone number',
                      hintText: '+91 9876543210',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _adding ? null : _add,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MedUnityColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                  child: _adding
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('ADD'),
                ),
              ],
            ),
          ),

          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Could not load.')),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(_emptyText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: MedUnityColors.textSecondary)),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = list[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: d['profile_photo'] != null
                            ? NetworkImage(d['profile_photo'] as String)
                            : null,
                        child: d['profile_photo'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(d['full_name'] as String),
                      subtitle: Text(
                          '${d['specialization'] ?? ''} · ${d['phone'] ?? ''}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _remove(d),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
