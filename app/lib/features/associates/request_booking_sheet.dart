import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'associate_provider.dart';

Future<void> showRequestBookingSheet({
  required BuildContext context,
  required WidgetRef ref,
  required int profId,
  required String profName,
  dynamic ratePerSlot,
  dynamic ratePerDay,
  int? slotHours,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RequestBookingSheet(
      profId: profId,
      profName: profName,
      ratePerSlot: ratePerSlot,
      ratePerDay: ratePerDay,
      slotHours: slotHours ?? 4,
    ),
  );
}

class _RequestBookingSheet extends ConsumerStatefulWidget {
  final int profId;
  final String profName;
  final dynamic ratePerSlot;
  final dynamic ratePerDay;
  final int slotHours;

  const _RequestBookingSheet({
    required this.profId,
    required this.profName,
    required this.ratePerSlot,
    required this.ratePerDay,
    required this.slotHours,
  });

  @override
  ConsumerState<_RequestBookingSheet> createState() =>
      _RequestBookingSheetState();
}

class _RequestBookingSheetState extends ConsumerState<_RequestBookingSheet> {
  String _slotKind = 'per_slot';
  DateTime? _date;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  final _notesCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.ratePerSlot == null && widget.ratePerDay != null) {
      _slotKind = 'per_day';
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
        context: context, initialTime: _start);
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _submit() async {
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a date.')),
      );
      return;
    }
    setState(() => _busy = true);
    final dio = ref.read(dioProvider);

    final start = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _start.hour,
      _start.minute,
    );
    final end = _slotKind == 'per_day'
        ? start.add(const Duration(hours: 8))
        : start.add(Duration(hours: widget.slotHours));

    try {
      await dio.post('/associates/bookings/', data: {
        'associate': widget.profId,
        'proposed_start': start.toUtc().toIso8601String(),
        'proposed_end': end.toUtc().toIso8601String(),
        'slot_kind': _slotKind,
        'notes': _notesCtrl.text.trim(),
      });
      if (!mounted) return;
      ref.invalidate(myAssociateBookingsProvider('clinic'));
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Booking request sent to ${widget.profName}. They will receive a notification.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send booking request.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSlot = widget.ratePerSlot != null;
    final hasDay = widget.ratePerDay != null;
    final selectedRate = _slotKind == 'per_slot'
        ? widget.ratePerSlot
        : widget.ratePerDay;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Request booking — ${widget.profName}',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'No payment is collected by MedUnity. Settle directly after the doctor accepts.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),

            if (hasSlot && hasDay)
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'per_slot', label: Text('Per slot')),
                  ButtonSegment(value: 'per_day', label: Text('Per day')),
                ],
                selected: {_slotKind},
                onSelectionChanged: (s) => setState(() => _slotKind = s.first),
              ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_date == null
                        ? 'Pick date'
                        : DateFormat('EEE, d MMM').format(_date!)),
                  ),
                ),
                if (_slotKind == 'per_slot') ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStart,
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(_start.format(context)),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. patients are mostly fillings + extractions',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.currency_rupee, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      selectedRate == null
                          ? 'Rate not set'
                          : 'Rate: ₹$selectedRate ${_slotKind == "per_slot" ? "(${widget.slotHours}h)" : "(per day)"}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: MedUnityColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Send Request',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
