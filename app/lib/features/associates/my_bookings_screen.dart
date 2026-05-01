import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import 'associate_provider.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'I Hired'),
              Tab(text: 'I Was Hired'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _BookingList(asRole: 'clinic'),
                _BookingList(asRole: 'associate'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingList extends ConsumerWidget {
  final String asRole;
  const _BookingList({required this.asRole});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myAssociateBookingsProvider(asRole));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load bookings.')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_busy_outlined,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    asRole == 'clinic'
                        ? 'No bookings made yet.'
                        : 'No bookings received yet.',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(myAssociateBookingsProvider(asRole)),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) =>
                _BookingCard(booking: items[i], asRole: asRole),
          ),
        );
      },
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String asRole;
  const _BookingCard({required this.booking, required this.asRole});

  @override
  Widget build(BuildContext context) {
    final id = booking['id'] as int;
    final status = (booking['status'] as String?) ?? 'pending';
    final slotKindDisplay = booking['slot_kind_display'] as String? ?? '';
    final start = DateTime.tryParse(booking['proposed_start'] as String? ?? '')
        ?.toLocal();
    final end =
        DateTime.tryParse(booking['proposed_end'] as String? ?? '')?.toLocal();
    final rate = booking['rate_quoted'];
    final otherName = asRole == 'clinic'
        ? (booking['associate_name'] as String? ?? 'Doctor')
        : (booking['hiring_clinic_label'] as String? ?? 'Clinic');

    final color = switch (status) {
      'connected' => Colors.green,
      'declined' => Colors.red,
      'cancelled' => Colors.grey,
      _ => Colors.amber[700]!,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/associates/bookings/$id'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                asRole == 'clinic' ? Icons.person_search : Icons.event_available,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(otherName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$slotKindDisplay · ₹$rate',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                  if (start != null && end != null)
                    Text(
                      '${DateFormat('d MMM, h:mm a').format(start)} → '
                      '${DateFormat('h:mm a').format(end)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
