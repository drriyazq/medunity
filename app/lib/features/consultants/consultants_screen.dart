import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/consultant_live_service.dart';
import '../../theme.dart';
import 'bookings_tab.dart';
import 'consultants_provider.dart';
import 'find_consultants_tab.dart';
import 'live_provider.dart';

class ConsultantsScreen extends ConsumerWidget {
  /// 0 = Find, 1 = Bookings. Used when deep-linking from a push notification.
  final int initialTab;

  /// When [initialTab] == 1 (Bookings), pick which inner tab to show:
  /// 0 = "My Requests", 1 = "Incoming". Default 0.
  final int initialBookingsSubTab;

  const ConsultantsScreen({
    super.key,
    this.initialTab = 0,
    this.initialBookingsSubTab = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
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
        body: TabBarView(
          children: [
            const FindConsultantsTab(),
            BookingsTab(initialIndex: initialBookingsSubTab),
          ],
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

    if (isAvailable) {
      // Self-heal: whenever the chip shows LIVE, ensure the foreground service
      // (and its persistent notification) is actually running. Catches OS-kills
      // and the cold-start race where bootstrap never fired.
      final mobility = (ref.read(liveSettingsProvider).valueOrNull?[
                  'mobility_mode'] as String?) ??
          'mobile';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ConsultantLiveService.ensureRunning(mobilityMode: mobility);
      });
    }

    return GestureDetector(
      onTap: () => context.push('/consultants/go-live'),
      child: Chip(
        avatar: Icon(
          isAvailable ? Icons.gps_fixed : Icons.gps_off,
          size: 14,
          color: isAvailable ? Colors.green : Colors.grey,
        ),
        label: Text(
          isAvailable ? 'LIVE' : 'Go Live',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isAvailable ? Colors.green[700] : Colors.grey[700],
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
