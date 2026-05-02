import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import '../messaging/messaging_provider.dart';
import 'associate_provider.dart';
import 'rate_doctor_sheet.dart';

class BookingDetailScreen extends ConsumerStatefulWidget {
  final int bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  bool _busy = false;

  Future<void> _patch(String status) async {
    setState(() => _busy = true);
    final dio = ref.read(dioProvider);
    try {
      await dio.patch('/associates/bookings/${widget.bookingId}/',
          data: {'status': status});
      if (!mounted) return;
      ref.invalidate(associateBookingDetailProvider(widget.bookingId));
      ref.invalidate(myAssociateBookingsProvider('clinic'));
      ref.invalidate(myAssociateBookingsProvider('associate'));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update booking.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    try {
      await launchUrl(Uri.parse('tel:$phone'),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dialer for $phone')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(associateBookingDetailProvider(widget.bookingId));
    final myProfileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Booking')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load booking.')),
        data: (b) {
          final me = myProfileAsync.asData?.value;
          final myProfId = me?['id'] as int?;
          final iAmAssociate = myProfId == (b['associate'] as int?);
          final iAmClinic = myProfId == (b['hiring_clinic'] as int?);
          final status = (b['status'] as String?) ?? 'pending';
          return _buildBody(b, iAmAssociate, iAmClinic, status);
        },
      ),
    );
  }

  Widget _buildBody(
      Map<String, dynamic> b, bool iAmAssociate, bool iAmClinic, String status) {
    final color = switch (status) {
      'connected' => Colors.green,
      'declined' => Colors.red,
      'cancelled' => Colors.grey,
      _ => Colors.amber[700]!,
    };
    final start =
        DateTime.tryParse(b['proposed_start'] as String? ?? '')?.toLocal();
    final end =
        DateTime.tryParse(b['proposed_end'] as String? ?? '')?.toLocal();
    final associatePhone = (b['associate_phone'] as String?) ?? '';
    final clinicPhone = (b['hiring_clinic_phone'] as String?) ?? '';
    final connected = status == 'connected';
    final showCallOther = connected && (iAmAssociate || iAmClinic);
    final otherPhone = iAmAssociate ? clinicPhone : associatePhone;
    final otherName = iAmAssociate
        ? (b['hiring_clinic_label'] as String? ?? 'Clinic')
        : (b['associate_name'] as String? ?? 'Associate');
    final otherProfId =
        iAmAssociate ? b['hiring_clinic'] as int : b['associate'] as int;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status pill
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Text(status.toUpperCase(),
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
        ),
        const SizedBox(height: 16),

        _Row(label: 'Associate', value: b['associate_name'] as String? ?? ''),
        _Row(
            label: 'Specialization',
            value: b['associate_specialization'] as String? ?? ''),
        _Row(
            label: 'Hiring clinic',
            value: b['hiring_clinic_label'] as String? ?? ''),
        _Row(
            label: 'Slot kind',
            value: b['slot_kind_display'] as String? ?? ''),
        _Row(label: 'Rate quoted', value: '₹${b['rate_quoted']}'),
        if (start != null && end != null)
          _Row(
            label: 'Time',
            value:
                '${DateFormat('EEE, d MMM, h:mm a').format(start)} → ${DateFormat('h:mm a').format(end)}',
          ),
        if ((b['notes'] as String? ?? '').isNotEmpty)
          _Row(label: 'Notes', value: b['notes'] as String),

        if (connected) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("You're connected!",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                const Text(
                  'Call directly to confirm details, location, and payment.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (showCallOther && otherPhone.isNotEmpty)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _call(otherPhone),
                          icon: const Icon(Icons.call),
                          label: Text('Call $otherName',
                              overflow: TextOverflow.ellipsis),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    if (showCallOther && otherPhone.isNotEmpty)
                      const SizedBox(width: 8),
                    Expanded(
                      child: _MessageOtherButton(profId: otherProfId),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showRateDoctorSheet(
              context: context,
              profId: otherProfId,
              profName: otherName,
              reviewContext: iAmAssociate ? 'clinic' : 'associate',
            ),
            icon: const Icon(Icons.star_outline_rounded),
            label: Text('Rate $otherName'),
          ),
        ] else ...[
          // Pre-connection: still allow messaging so the two parties can chat
          // about the booking before accept.
          const SizedBox(height: 12),
          _MessageOtherButton(profId: otherProfId),
        ],

        // Action buttons
        const SizedBox(height: 16),
        if (status == 'pending') ...[
          if (iAmAssociate) ...[
            ElevatedButton.icon(
              onPressed: _busy ? null : () => _patch('connected'),
              icon: const Icon(Icons.check),
              label: const Text('Accept — Connect with clinic'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _patch('declined'),
              child: const Text('Decline'),
            ),
          ],
          if (iAmClinic) ...[
            OutlinedButton(
              onPressed: _busy ? null : () => _patch('cancelled'),
              child: const Text('Cancel my request'),
            ),
          ],
        ],
        if (status == 'connected') ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _patch('cancelled'),
            child: const Text('Cancel booking'),
          ),
        ],

        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.push('/associates/$otherProfId'),
          child: Text('View ${iAmAssociate ? "clinic" : "associate"} profile'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    color: MedUnityColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _MessageOtherButton extends ConsumerStatefulWidget {
  final int profId;
  const _MessageOtherButton({required this.profId});

  @override
  ConsumerState<_MessageOtherButton> createState() =>
      _MessageOtherButtonState();
}

class _MessageOtherButtonState extends ConsumerState<_MessageOtherButton> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final id = await startThreadWith(ref, widget.profId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) {
      context.push('/messages/$id');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open conversation.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _open,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chat_bubble_outline, size: 16),
      label: const Text('Message'),
      style: OutlinedButton.styleFrom(
        foregroundColor: MedUnityColors.primary,
        side: const BorderSide(color: MedUnityColors.primary),
      ),
    );
  }
}
