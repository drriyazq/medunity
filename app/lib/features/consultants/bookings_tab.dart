import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'consultants_provider.dart';
import 'review_sheet.dart';

class BookingsTab extends ConsumerWidget {
  /// 0 = My Requests, 1 = Incoming. Push-notification deep links use this.
  final int initialIndex;
  const BookingsTab({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'My Requests'),
              Tab(text: 'Incoming'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _BookingsList(role: 'requester', ref: ref),
                _BookingsList(role: 'consultant', ref: ref),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingsList extends ConsumerWidget {
  final String role;
  final WidgetRef ref;
  const _BookingsList({required this.role, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final async = widgetRef.watch(myBookingsProvider(role));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load bookings.')),
      data: (bookings) {
        if (bookings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  role == 'requester'
                      ? 'No bookings made yet.'
                      : 'No incoming consultation requests.',
                  style: const TextStyle(color: MedUnityColors.textSecondary),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => widgetRef.read(myBookingsProvider(role).notifier).load(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _BookingCard(
              booking: bookings[i],
              role: role,
              ref: widgetRef,
            ),
          ),
        );
      },
    );
  }
}

class _BookingCard extends StatefulWidget {
  final Map<String, dynamic> booking;
  final String role;
  final WidgetRef ref;
  const _BookingCard({required this.booking, required this.role, required this.ref});

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  bool _acting = false;

  static const _statusColor = {
    'pending': Colors.orange,
    'accepted': Colors.blue,
    'declined': Colors.red,
    'completed': Colors.green,
    'cancelled': Colors.grey,
  };

  Future<void> _action(String action) async {
    setState(() => _acting = true);
    final dio = widget.ref.read(dioProvider);
    try {
      final resp =
          await dio.post('/consultants/bookings/${widget.booking['id']}/$action/');
      widget.ref.read(myBookingsProvider(widget.role).notifier)
          .updateBooking(Map<String, dynamic>.from(resp.data as Map));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action failed. Please retry.')),
        );
      }
    }
    if (mounted) setState(() => _acting = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final status = b['status'] as String? ?? '';
    final isMine = b['i_am_requester'] as bool? ?? false;
    final reviewDone = b['my_review_submitted'] as bool? ?? false;
    final other = isMine
        ? b['consultant'] as Map<String, dynamic>
        : b['requester'] as Map<String, dynamic>;
    final statusColor = _statusColor[status] ?? Colors.grey;

    return Container(
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
                child: Text(b['procedure'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status[0].toUpperCase() + status.substring(1),
                  style: TextStyle(
                      color: statusColor, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isMine
                ? 'Consultant: ${other['full_name']}'
                : 'From: ${other['full_name']}',
            style: const TextStyle(
                fontSize: 13, color: MedUnityColors.textSecondary),
          ),
          if ((other['phone'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone, size: 16, color: MedUnityColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(other['phone'] as String,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: MedUnityColors.primary)),
                ),
                TextButton.icon(
                  onPressed: () => _callPhone(other['phone'] as String),
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Call'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
          if ((b['notes'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(b['notes'] as String, style: const TextStyle(fontSize: 13)),
          ],

          // Action buttons
          if (_acting)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            )
          else ...[
            // Consultant actions on pending
            if (!isMine && status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _action('accept'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white),
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _action('decline'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red),
                      child: const Text('Decline'),
                    ),
                  ),
                ],
              ),
            ],

            // Mark complete (accepted booking — either side)
            if (status == 'accepted') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _action('complete'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: MedUnityColors.primary,
                      foregroundColor: Colors.white),
                  child: const Text('Mark as Completed'),
                ),
              ),
            ],

            // Requester cancel (pending only)
            if (isMine && status == 'pending') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _action('cancel'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Cancel Request'),
                ),
              ),
            ],

            // Review (completed, not yet reviewed)
            if (status == 'completed' && !reviewDone) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showReview(context),
                  icon: const Icon(Icons.star_outline, size: 18),
                  label: const Text('Leave a Review'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber[700]),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _callPhone(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    // Android 11+ doesn't reliably resolve tel: through canLaunchUrl; just launch.
    await launchUrl(uri);
  }

  void _showReview(BuildContext context) {
    showReviewSheet(
      context,
      bookingId: widget.booking['id'] as int,
      ref: widget.ref,
      onSubmitted: () {
        widget.ref.read(myBookingsProvider(widget.role).notifier).load();
      },
    );
  }
}
