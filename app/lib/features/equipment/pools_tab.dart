import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'equipment_provider.dart';

const _categories = [
  ('', 'All'),
  ('dental_chairs', 'Dental Chairs'),
  ('imaging', 'Imaging'),
  ('surgical_instruments', 'Instruments'),
  ('diagnostic', 'Diagnostic'),
  ('sterilization', 'Sterilization'),
  ('lab_equipment', 'Lab'),
  ('other', 'Other'),
];

class PoolsTab extends ConsumerStatefulWidget {
  const PoolsTab({super.key});

  @override
  ConsumerState<PoolsTab> createState() => _PoolsTabState();
}

class _PoolsTabState extends ConsumerState<PoolsTab> {
  String _category = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(poolsProvider);

    return Column(
      children: [
        // Category filter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: _categories.map((c) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(c.$2, style: const TextStyle(fontSize: 12)),
                selected: _category == c.$1,
                onSelected: (_) {
                  setState(() => _category = c.$1);
                  ref.read(poolsProvider.notifier).load(category: c.$1);
                },
              ),
            )).toList(),
          ),
        ),

        // Create button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showCreatePool(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Start a Co-Purchase Pool'),
              style: ElevatedButton.styleFrom(
                backgroundColor: MedUnityColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // List
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('Could not load pools.')),
            data: (pools) {
              if (pools.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group_work_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text('No co-purchase pools yet.',
                          style: TextStyle(color: MedUnityColors.textSecondary)),
                      const SizedBox(height: 4),
                      const Text('Start one to pool funds with nearby colleagues.',
                          style: TextStyle(fontSize: 12, color: MedUnityColors.textSecondary)),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref.read(poolsProvider.notifier).load(category: _category),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: pools.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _PoolCard(pool: pools[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCreatePool(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePoolSheet(ref: ref),
    );
  }
}

class _PoolCard extends StatelessWidget {
  final Map<String, dynamic> pool;
  const _PoolCard({required this.pool});

  static const _statusColor = {
    'open': Colors.green,
    'funded': Colors.blue,
    'active': MedUnityColors.primary,
    'closed': Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final status = pool['status'] as String? ?? 'open';
    final fundingPct = pool['funding_pct'] as double? ?? 0;
    final isMember = pool['is_member'] as bool? ?? false;
    final color = _statusColor[status] ?? Colors.grey;

    return InkWell(
      onTap: () => context.push('/equipment/pools/${pool['id']}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(pool['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    pool['status_display'] as String? ?? status,
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(pool['category_display'] as String? ?? '',
                style: const TextStyle(color: MedUnityColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 10),

            // Funding progress
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fundingPct / 100,
                      backgroundColor: Colors.grey[200],
                      color: fundingPct >= 100 ? Colors.green : MedUnityColors.primary,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${fundingPct.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('₹${pool['committed_amount']} of ₹${pool['target_amount']}',
                    style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary)),
                const Spacer(),
                Icon(Icons.people, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('${pool['member_count']}/${pool['max_members']}',
                    style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary)),
                if (isMember) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, size: 14, color: Colors.green),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create Pool sheet ─────────────────────────────────────────────────────────

class _CreatePoolSheet extends StatefulWidget {
  final WidgetRef ref;
  const _CreatePoolSheet({required this.ref});

  @override
  State<_CreatePoolSheet> createState() => _CreatePoolSheetState();
}

class _CreatePoolSheetState extends State<_CreatePoolSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _contribCtrl = TextEditingController();
  String _category = 'other';
  int _maxMembers = 5;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _targetCtrl.dispose();
    _contribCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final target = _targetCtrl.text.trim();
    final contrib = _contribCtrl.text.trim();
    if (name.isEmpty || target.isEmpty || contrib.isEmpty) {
      setState(() => _error = 'Name, target amount and your contribution are required.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final container = ProviderScope.containerOf(context, listen: false);
    final dio = container.read(dioProvider);
    try {
      final resp = await dio.post('/equipment/pools/', data: {
        'name': name,
        'description': _descCtrl.text.trim(),
        'category': _category,
        'target_amount': target,
        'my_contribution': contrib,
        'max_members': _maxMembers,
      });
      widget.ref
          .read(poolsProvider.notifier)
          .prependPool(Map<String, dynamic>.from(resp.data as Map));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() { _loading = false; _error = 'Could not create pool.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Start a Co-Purchase Pool',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Equipment name *', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _descCtrl, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: _categories.skip(1).map((c) =>
                    DropdownMenuItem(value: c.$1, child: Text(c.$2))).toList(),
                onChanged: (v) => setState(() => _category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: _targetCtrl, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Target ₹ *', border: OutlineInputBorder()))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _contribCtrl, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'My share ₹ *', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 12),
              Text('Max members: $_maxMembers'),
              Slider(value: _maxMembers.toDouble(), min: 2, max: 20, divisions: 18,
                  activeColor: MedUnityColors.primary,
                  label: '$_maxMembers',
                  onChanged: (v) => setState(() => _maxMembers = v.toInt())),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: MedUnityColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Create Pool', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
