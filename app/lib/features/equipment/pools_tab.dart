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
  ('consumables', 'Consumables'),
  ('other', 'Other'),
];

const _purposeFilters = [
  ('', 'All Pools'),
  ('bulk_buy', 'Bulk Buy'),
  ('shared_use', 'Shared Use'),
];

const _purposeColor = {
  'bulk_buy': Color(0xFF1E88E5),    // blue — each clinic buys their own
  'shared_use': Color(0xFF8E24AA),  // purple — one unit, shared
};

const _purposeIcon = {
  'bulk_buy': Icons.local_shipping_outlined,
  'shared_use': Icons.handshake_outlined,
};

class PoolsTab extends ConsumerStatefulWidget {
  const PoolsTab({super.key});

  @override
  ConsumerState<PoolsTab> createState() => _PoolsTabState();
}

class _PoolsTabState extends ConsumerState<PoolsTab> {
  String _category = '';
  String _purpose = '';

  void _reload() {
    ref.read(poolsProvider.notifier).load(category: _category, purpose: _purpose);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(poolsProvider);

    return Column(
      children: [
        // Purpose segmented filter (primary)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: _purposeFilters.map((p) {
              final selected = _purpose == p.$1;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _purpose = p.$1);
                    _reload();
                  },
                  child: Container(
                    margin: EdgeInsets.only(
                      right: p.$1 == 'shared_use' ? 0 : 6,
                      left: p.$1 == '' ? 0 : 0,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? MedUnityColors.primary
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? MedUnityColors.primary : Colors.grey[300]!,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        p.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : MedUnityColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Category filter (secondary)
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
                  _reload();
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.group_work_outlined, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          _purpose == 'bulk_buy'
                              ? 'No bulk-buy pools running yet.'
                              : _purpose == 'shared_use'
                                  ? 'No shared-use pools running yet.'
                                  : 'No co-purchase pools yet.',
                          style: const TextStyle(color: MedUnityColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Start one to either bulk-buy with a discount or share a single unit with nearby colleagues.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: MedUnityColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
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
    final purpose = pool['purpose'] as String? ?? 'bulk_buy';
    final purposeColor = _purposeColor[purpose] ?? Colors.grey;
    final purposeIcon = _purposeIcon[purpose] ?? Icons.group_work_outlined;
    final purposeLabel = pool['purpose_display'] as String?
        ?? (purpose == 'shared_use' ? 'Shared Use' : 'Bulk Buy');

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
            const SizedBox(height: 6),
            Row(
              children: [
                // Purpose pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: purposeColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(purposeIcon, size: 12, color: purposeColor),
                      const SizedBox(width: 4),
                      Text(purposeLabel,
                          style: TextStyle(
                              color: purposeColor, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(pool['category_display'] as String? ?? '',
                      style: const TextStyle(color: MedUnityColors.textSecondary, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
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
                Flexible(
                  child: Text('₹${pool['committed_amount']} of ₹${pool['target_amount']}',
                      style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Icon(
                  purpose == 'shared_use' ? Icons.handshake_outlined : Icons.people,
                  size: 14,
                  color: Colors.grey[400],
                ),
                const SizedBox(width: 4),
                Text(
                  purpose == 'shared_use'
                      ? '${pool['member_count']}/${pool['max_members']} sharing'
                      : '${pool['member_count']}/${pool['max_members']} joined',
                  style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary),
                ),
                if (isMember) ...[
                  const SizedBox(width: 6),
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
  String _purpose = 'bulk_buy';
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
        'purpose': _purpose,
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

              // Purpose selector — what kind of pool
              const Text('What kind of pool?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _PurposeOptionTile(
                value: 'bulk_buy',
                groupValue: _purpose,
                icon: _purposeIcon['bulk_buy']!,
                color: _purposeColor['bulk_buy']!,
                title: 'Bulk Discount Buy',
                subtitle: 'Each member buys their own unit. Pool together for a better price.',
                onTap: () => setState(() => _purpose = 'bulk_buy'),
              ),
              const SizedBox(height: 8),
              _PurposeOptionTile(
                value: 'shared_use',
                groupValue: _purpose,
                icon: _purposeIcon['shared_use']!,
                color: _purposeColor['shared_use']!,
                title: 'Shared Use',
                subtitle: 'Buy ONE unit and share it. Best for kits used a few times a month '
                    '(PFM repair, surgical kits, apex locator, etc).',
                onTap: () => setState(() => _purpose = 'shared_use'),
              ),
              const SizedBox(height: 16),

              TextField(controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Equipment name *', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _descCtrl, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: _categories.skip(1).map((c) =>
                    DropdownMenuItem(value: c.$1, child: Text(c.$2))).toList(),
                onChanged: (v) => setState(() => _category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: _targetCtrl, keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: _purpose == 'shared_use' ? 'Unit cost ₹ *' : 'Target ₹ *',
                          border: const OutlineInputBorder()))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _contribCtrl, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'My share ₹ *', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 12),
              Text(_purpose == 'shared_use'
                  ? 'Co-owners: $_maxMembers'
                  : 'Max members: $_maxMembers'),
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

class _PurposeOptionTile extends StatelessWidget {
  final String value;
  final String groupValue;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PurposeOptionTile({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey[300]!,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: selected ? color : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: MedUnityColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? color : Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
