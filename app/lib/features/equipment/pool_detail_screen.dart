import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'equipment_provider.dart';

class PoolDetailScreen extends ConsumerWidget {
  final int poolId;
  const PoolDetailScreen({super.key, required this.poolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(poolDetailProvider(poolId));
    return Scaffold(
      appBar: AppBar(title: const Text('Pool Details')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load pool.')),
        data: (pool) => _PoolBody(pool: pool, poolId: poolId, ref: ref),
      ),
    );
  }
}

class _PoolBody extends StatelessWidget {
  final Map<String, dynamic> pool;
  final int poolId;
  final WidgetRef ref;
  const _PoolBody({required this.pool, required this.poolId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isMember = pool['is_member'] as bool? ?? false;
    final isMine = pool['is_mine'] as bool? ?? false;
    final status = pool['status'] as String? ?? 'open';
    final fundingPct = pool['funding_pct'] as double? ?? 0;
    final members = (pool['members'] as List? ?? []).cast<Map<String, dynamic>>();
    final purpose = pool['purpose'] as String? ?? 'bulk_buy';
    final isSharedUse = purpose == 'shared_use';
    final purposeColor = isSharedUse
        ? const Color(0xFF8E24AA)
        : const Color(0xFF1E88E5);
    final purposeIcon =
        isSharedUse ? Icons.handshake_outlined : Icons.local_shipping_outlined;
    final purposeLabel = pool['purpose_display'] as String?
        ?? (isSharedUse ? 'Shared Use' : 'Bulk Discount Buy');
    final purposeBlurb = isSharedUse
        ? 'One unit, shared between members. Book usage slots once funded and active.'
        : 'Each member buys their own unit at a group-discounted price.';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(pool['name'] as String,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(pool['category_display'] as String? ?? '',
              style: const TextStyle(color: MedUnityColors.primary)),
          const SizedBox(height: 12),
          // Purpose chip + blurb
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: purposeColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: purposeColor.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(purposeIcon, color: purposeColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(purposeLabel,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: purposeColor)),
                      const SizedBox(height: 2),
                      Text(purposeBlurb,
                          style: const TextStyle(
                              fontSize: 12,
                              color: MedUnityColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if ((pool['description'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(pool['description'] as String),
          ],
          const SizedBox(height: 20),

          // Funding progress card
          Container(
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('₹${pool['committed_amount']}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('of ₹${pool['target_amount']}',
                        style: const TextStyle(color: MedUnityColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fundingPct / 100,
                    backgroundColor: Colors.grey[200],
                    color: fundingPct >= 100 ? Colors.green : MedUnityColors.primary,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${fundingPct.toStringAsFixed(1)}% funded · '
                  '${pool['member_count']}/${pool['max_members']} members',
                  style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Join / leave / status actions
          if (status == 'open') ...[
            if (!isMember)
              _JoinButton(poolId: poolId, ref: ref)
            else if (!isMine)
              _LeaveButton(poolId: poolId, ref: ref),
          ],

          // Creator status controls
          if (isMine && status == 'open') ...[
            const SizedBox(height: 10),
            _StatusButton(poolId: poolId, newStatus: 'funded', label: 'Mark as Funded', ref: ref),
          ],
          if (isMine && status == 'funded') ...[
            const SizedBox(height: 10),
            _StatusButton(poolId: poolId, newStatus: 'active', label: 'Activate (In Use)', ref: ref),
          ],
          if (isMine && status != 'closed') ...[
            const SizedBox(height: 10),
            _StatusButton(poolId: poolId, newStatus: 'closed', label: 'Close Pool',
                ref: ref, isDestructive: true),
          ],

          // Usage calendar — shared-use pools only (bulk-buy doesn't share a unit)
          if (isSharedUse && status == 'active' && isMember) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Usage Schedule',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton.icon(
                  onPressed: () => _showBookSlot(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Book Slot'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SlotsList(poolId: poolId, ref: ref),
          ],

          // Members list
          const SizedBox(height: 24),
          Text('Members (${members.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          ...members.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const CircleAvatar(radius: 16, child: Icon(Icons.person_outline, size: 16)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(m['specialization'] as String? ?? '',
                          style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary)),
                    ],
                  ),
                ),
                Text('₹${m['contribution']}',
                    style: const TextStyle(fontWeight: FontWeight.w500, color: MedUnityColors.primary)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  void _showBookSlot(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookSlotSheet(poolId: poolId, ref: ref),
    );
  }
}

// ── Slots list ────────────────────────────────────────────────────────────────

class _SlotsList extends ConsumerWidget {
  final int poolId;
  final WidgetRef ref;
  const _SlotsList({required this.poolId, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final async = widgetRef.watch(poolSlotsProvider(poolId));
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const Text('Could not load slots.'),
      data: (slots) {
        if (slots.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('No upcoming bookings.',
                style: TextStyle(color: MedUnityColors.textSecondary)),
          );
        }
        return Column(
          children: slots.map((s) => _SlotTile(slot: s, poolId: poolId, ref: widgetRef)).toList(),
        );
      },
    );
  }
}

class _SlotTile extends StatelessWidget {
  final Map<String, dynamic> slot;
  final int poolId;
  final WidgetRef ref;
  const _SlotTile({required this.slot, required this.poolId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isMine = slot['is_mine'] as bool? ?? false;
    final fmt = DateFormat('d MMM, h:mm a');
    final start = DateTime.tryParse(slot['start_dt'] as String? ?? '');
    final end = DateTime.tryParse(slot['end_dt'] as String? ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMine ? MedUnityColors.primary.withOpacity(0.07) : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isMine ? MedUnityColors.primary.withOpacity(0.3) : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.event, size: 18, color: MedUnityColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot['member_name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                if (start != null && end != null)
                  Text('${fmt.format(start)} → ${fmt.format(end)}',
                      style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary)),
                if ((slot['notes'] as String? ?? '').isNotEmpty)
                  Text(slot['notes'] as String,
                      style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary)),
              ],
            ),
          ),
          if (isMine)
            IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
              onPressed: () => _cancel(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/equipment/pools/$poolId/slots/${slot['id']}/');
      ref.invalidate(poolSlotsProvider(poolId));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not cancel slot.')));
      }
    }
  }
}

// ── Book slot sheet ───────────────────────────────────────────────────────────

class _BookSlotSheet extends StatefulWidget {
  final int poolId;
  final WidgetRef ref;
  const _BookSlotSheet({required this.poolId, required this.ref});

  @override
  State<_BookSlotSheet> createState() => _BookSlotSheetState();
}

class _BookSlotSheetState extends State<_BookSlotSheet> {
  DateTime? _start;
  DateTime? _end;
  final _notesCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
        context: context, initialDate: DateTime.now(),
        firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() => _start = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickEnd() async {
    final base = _start ?? DateTime.now();
    final date = await showDatePicker(
        context: context, initialDate: base,
        firstDate: base, lastDate: base.add(const Duration(days: 1)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null) return;
    setState(() => _end = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (_start == null || _end == null) {
      setState(() => _error = 'Select start and end times.');
      return;
    }
    if (!_end!.isAfter(_start!)) {
      setState(() => _error = 'End must be after start.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/equipment/pools/${widget.poolId}/slots/', data: {
        'start_dt': _start!.toIso8601String(),
        'end_dt': _end!.toIso8601String(),
        'notes': _notesCtrl.text.trim(),
      });
      widget.ref.invalidate(poolSlotsProvider(widget.poolId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      final msg = e.toString().contains('409')
          ? 'Time slot conflicts with an existing booking.'
          : 'Could not book slot.';
      setState(() { _loading = false; _error = msg; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM, h:mm a');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Book Usage Slot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStart,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_start == null ? 'Start time' : fmt.format(_start!),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEnd,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_end == null ? 'End time' : fmt.format(_end!),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder())),
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
                    : const Text('Book Slot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action buttons ────────────────────────────────────────────────────────────

class _JoinButton extends StatefulWidget {
  final int poolId;
  final WidgetRef ref;
  const _JoinButton({required this.poolId, required this.ref});
  @override State<_JoinButton> createState() => _JoinButtonState();
}

class _JoinButtonState extends State<_JoinButton> {
  bool _loading = false;
  final _contribCtrl = TextEditingController();

  Future<void> _join() async {
    final contrib = _contribCtrl.text.trim();
    if (contrib.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter your contribution amount.')));
      return;
    }
    setState(() => _loading = true);
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/equipment/pools/${widget.poolId}/join/', data: {'contribution_amount': contrib});
      widget.ref.invalidate(poolDetailProvider(widget.poolId));
      widget.ref.invalidate(poolsProvider);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join pool.')));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _contribCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'My contribution ₹',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: _loading ? null : _join,
          style: ElevatedButton.styleFrom(
              backgroundColor: MedUnityColors.primary, foregroundColor: Colors.white),
          child: _loading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Join Pool'),
        ),
      ],
    );
  }
}

class _LeaveButton extends StatefulWidget {
  final int poolId;
  final WidgetRef ref;
  const _LeaveButton({required this.poolId, required this.ref});
  @override State<_LeaveButton> createState() => _LeaveButtonState();
}

class _LeaveButtonState extends State<_LeaveButton> {
  bool _loading = false;

  Future<void> _leave() async {
    setState(() => _loading = true);
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.delete('/equipment/pools/${widget.poolId}/leave/');
      widget.ref.invalidate(poolDetailProvider(widget.poolId));
      widget.ref.invalidate(poolsProvider);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: _loading ? null : _leave,
      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
      child: const Text('Leave Pool'),
    ),
  );
}

class _StatusButton extends StatefulWidget {
  final int poolId;
  final String newStatus;
  final String label;
  final WidgetRef ref;
  final bool isDestructive;
  const _StatusButton({required this.poolId, required this.newStatus,
      required this.label, required this.ref, this.isDestructive = false});
  @override State<_StatusButton> createState() => _StatusButtonState();
}

class _StatusButtonState extends State<_StatusButton> {
  bool _loading = false;

  Future<void> _update() async {
    setState(() => _loading = true);
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/equipment/pools/${widget.poolId}/status/', data: {'status': widget.newStatus});
      widget.ref.invalidate(poolDetailProvider(widget.poolId));
      widget.ref.invalidate(poolsProvider);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: _loading ? null : _update,
      style: OutlinedButton.styleFrom(
          foregroundColor: widget.isDestructive ? Colors.red : MedUnityColors.primary),
      child: Text(widget.label),
    ),
  );
}
