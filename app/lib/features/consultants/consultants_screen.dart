import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import 'availability_toggle.dart';
import 'bookings_tab.dart';
import 'consultants_provider.dart';
import 'find_consultants_tab.dart';

class ConsultantsScreen extends ConsumerWidget {
  const ConsultantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Consultants'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _AvailabilityChip(ref: ref),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.search), text: 'Find'),
              Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Bookings'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [FindConsultantsTab(), BookingsTab()],
        ),
      ),
    );
  }
}

class _AvailabilityChip extends ConsumerWidget {
  final WidgetRef ref;
  const _AvailabilityChip({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(availabilityProvider);
    final isAvailable = async.valueOrNull?['is_available'] as bool? ?? false;

    return GestureDetector(
      onTap: () => showAvailabilityToggle(context, ref),
      child: Chip(
        avatar: Icon(
          isAvailable ? Icons.circle : Icons.circle_outlined,
          size: 12,
          color: isAvailable ? Colors.green : Colors.grey,
        ),
        label: Text(
          isAvailable ? 'Available' : 'Unavailable',
          style: TextStyle(
            fontSize: 12,
            color: isAvailable ? Colors.green[700] : Colors.grey[600],
          ),
        ),
        backgroundColor: isAvailable
            ? Colors.green.withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
