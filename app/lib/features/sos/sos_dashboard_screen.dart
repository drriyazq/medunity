import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import 'sos_provider.dart';

class SosDashboardScreen extends ConsumerWidget {
  const SosDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(myAlertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My SOS Alerts'),
      ),
      body: alertsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your alerts.'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.invalidate(myAlertsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (alerts) {
          if (alerts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined,
                        color: Colors.grey[400], size: 64),
                    const SizedBox(height: 12),
                    const Text(
                      'No SOS alerts yet.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Last 30 days of alerts you sent will appear here.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myAlertsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _AlertCard(alert: alerts[i]),
            ),
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isActive = alert['is_active'] as bool? ?? false;
    final accepted = alert['accepted_count'] as int? ?? 0;
    final recipients = alert['recipient_count'] as int? ?? 0;
    final categoryDisplay = alert['category_display'] as String? ?? 'SOS';
    final createdAt =
        DateTime.tryParse(alert['created_at'] as String? ?? '')?.toLocal();
    final radiusKm = (alert['radius_km'] as num?)?.toDouble() ?? 1.0;
    final alertId = alert['alert_id'] as int;

    final color = isActive ? MedUnityColors.sos : Colors.grey;
    final timeStr = createdAt != null
        ? DateFormat('d MMM, h:mm a').format(createdAt)
        : '';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push(
        '/sos/status/$alertId',
        extra: {
          'recipientCount': recipients,
          'radiusKm': radiusKm,
          'category': alert['category'] as String? ?? '',
          'categoryDisplay': categoryDisplay,
        },
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.sos, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          categoryDisplay,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isActive ? 'ACTIVE' : 'EXPIRED',
                          style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$accepted of $recipients accepted • ${radiusKm.toStringAsFixed(0)} km radius',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                  if (timeStr.isNotEmpty)
                    Text(timeStr,
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 11)),
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
