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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My SOS Alerts'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.send_outlined), text: 'Sent'),
              Tab(icon: Icon(Icons.inbox_outlined), text: 'Received'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SentTab(),
            _ReceivedTab(),
          ],
        ),
      ),
    );
  }
}

class _SentTab extends ConsumerWidget {
  const _SentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(myAlertsProvider);
    return alertsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _ErrorView(onRetry: () => ref.invalidate(myAlertsProvider)),
      data: (alerts) {
        if (alerts.isEmpty) {
          return const _EmptyView(
            icon: Icons.shield_outlined,
            title: 'No SOS alerts sent.',
            subtitle: 'Last 30 days of alerts you sent will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myAlertsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _SentAlertCard(alert: alerts[i]),
          ),
        );
      },
    );
  }
}

class _ReceivedTab extends ConsumerWidget {
  const _ReceivedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(receivedAlertsProvider);
    return alertsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) =>
          _ErrorView(onRetry: () => ref.invalidate(receivedAlertsProvider)),
      data: (alerts) {
        if (alerts.isEmpty) {
          return const _EmptyView(
            icon: Icons.inbox_outlined,
            title: 'No incoming SOS alerts.',
            subtitle:
                'Alerts sent to you in the last 30 days will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(receivedAlertsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ReceivedAlertCard(alert: alerts[i]),
          ),
        );
      },
    );
  }
}

class _SentAlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _SentAlertCard({required this.alert});

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
    final timeStr =
        createdAt != null ? DateFormat('d MMM, h:mm a').format(createdAt) : '';

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
                      _StatusChip(
                        label: isActive ? 'ACTIVE' : 'EXPIRED',
                        color: color,
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

class _ReceivedAlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _ReceivedAlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isActive = alert['is_active'] as bool? ?? false;
    final categoryDisplay = alert['category_display'] as String? ?? 'SOS';
    final senderName = alert['sender_name'] as String? ?? 'A doctor';
    final senderClinic = alert['sender_clinic_name'] as String? ?? '';
    final myResponse = alert['my_response'] as String?;
    final createdAt =
        DateTime.tryParse(alert['created_at'] as String? ?? '')?.toLocal();
    final alertId = alert['alert_id'] as int;
    final timeStr =
        createdAt != null ? DateFormat('d MMM, h:mm a').format(createdAt) : '';

    final Color leadColor;
    final String chipLabel;
    if (myResponse == 'accepted') {
      leadColor = Colors.green;
      chipLabel = 'YOU ACCEPTED';
    } else if (myResponse == 'declined') {
      leadColor = Colors.grey;
      chipLabel = 'YOU DECLINED';
    } else if (isActive) {
      leadColor = MedUnityColors.sos;
      chipLabel = 'ACTIVE — RESPOND';
    } else {
      leadColor = Colors.grey;
      chipLabel = 'EXPIRED';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/sos/incoming/$alertId'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive && myResponse == null
                ? MedUnityColors.sos.withOpacity(0.5)
                : Colors.grey[200]!,
            width: isActive && myResponse == null ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: leadColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                myResponse == 'accepted'
                    ? Icons.directions_run
                    : (myResponse == 'declined'
                        ? Icons.do_not_disturb_on
                        : Icons.sos),
                color: leadColor,
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
                        child: Text(
                          categoryDisplay,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _StatusChip(label: chipLabel, color: leadColor),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'From $senderName${senderClinic.isNotEmpty ? ' · $senderClinic' : ''}',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    overflow: TextOverflow.ellipsis,
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

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.grey[400], size: 64),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load alerts.'),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
