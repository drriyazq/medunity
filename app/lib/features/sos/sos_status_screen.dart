import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';
import 'sos_provider.dart';

class SosStatusScreen extends ConsumerStatefulWidget {
  final int alertId;
  final int recipientCount;
  final double radiusKm;
  final String category;
  final String categoryDisplay;

  const SosStatusScreen({
    super.key,
    required this.alertId,
    required this.recipientCount,
    required this.radiusKm,
    required this.category,
    required this.categoryDisplay,
  });

  @override
  ConsumerState<SosStatusScreen> createState() => _SosStatusScreenState();
}

class _SosStatusScreenState extends ConsumerState<SosStatusScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Poll every 15 seconds to refresh accepted count + dots
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      ref.read(sosStatusProvider(widget.alertId).notifier).load();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(sosStatusProvider(widget.alertId));

    return Scaffold(
      backgroundColor: const Color(0xFF1A0000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('SOS Active', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Done', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: MedUnityColors.sos,
          onRefresh: () =>
              ref.read(sosStatusProvider(widget.alertId).notifier).load(),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Sent confirmation banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MedUnityColors.sos.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MedUnityColors.sos.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sos, color: MedUnityColors.sos, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.categoryDisplay,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          Text(
                            'Alert sent to ${widget.recipientCount} '
                            'doctor${widget.recipientCount == 1 ? '' : 's'} '
                            'within ${widget.radiusKm.toStringAsFixed(0)} km',
                            style: TextStyle(color: Colors.red[200], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Response count
              statusAsync.when(
                loading: () => const _ResponseCountCard(count: 0, loading: true),
                error: (_, __) => const _ResponseCountCard(count: 0, loading: false),
                data: (data) => _ResponseCountCard(
                  count: data['accepted_count'] as int? ?? 0,
                  loading: false,
                ),
              ),
              const SizedBox(height: 20),

              // Responder cards
              statusAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => Text(
                    'Could not load responders.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                data: (data) {
                  final responders =
                      (data['responders'] as List? ?? const []).cast<Map>();
                  if (responders.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_top,
                              color: Colors.grey[500], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No one has accepted yet. Auto-refreshes every 15 seconds — pull down to refresh now.',
                              style: TextStyle(
                                  color: Colors.grey[400], fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final r in responders)
                        _ResponderCard(
                            r: Map<String, dynamic>.from(r as Map)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Refreshes every 15 seconds • Alert expires in 2 hours',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponseCountCard extends StatelessWidget {
  final int count;
  final bool loading;
  const _ResponseCountCard({required this.count, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_run, color: Colors.greenAccent, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (loading)
                  const SizedBox(
                      width: 60,
                      height: 20,
                      child: LinearProgressIndicator(color: Colors.greenAccent))
                else
                  Text(
                    count == 0 ? 'Waiting for responses…' : '$count on their way',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                const Text('Doctor responses',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponderCard extends StatelessWidget {
  final Map<String, dynamic> r;
  const _ResponderCard({required this.r});

  Future<void> _call(BuildContext context, String phone) async {
    // Don't gate behind canLaunchUrl — on Android 11+ it returns false
    // unless AndroidManifest has a <queries> block for the tel scheme,
    // which we can't ship from this repo (android/ is generated on
    // Windows). The dialer always exists, so just launch.
    try {
      await launchUrl(Uri.parse('tel:$phone'),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open dialer for $phone')),
        );
      }
    }
  }

  Future<void> _openInMaps(BuildContext context, double lat, double lng) async {
    try {
      await launchUrl(
        Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Maps')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (r['full_name'] as String?) ?? 'Doctor';
    final spec = (r['specialization_display'] as String?) ?? '';
    final clinic = (r['clinic_name'] as String?) ?? '';
    final phone = (r['phone'] as String?) ?? '';
    final dist = (r['distance_km'] as num?)?.toDouble();
    final lat = (r['lat'] as num?)?.toDouble();
    final lng = (r['lng'] as num?)?.toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_run,
                  color: Colors.greenAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
              if (dist != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${dist.toStringAsFixed(2)} km',
                    style: const TextStyle(
                        color: Colors.greenAccent, fontSize: 12),
                  ),
                ),
            ],
          ),
          if (spec.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 32),
              child: Text(spec,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            ),
          if (clinic.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 32),
              child: Text(clinic,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (phone.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _call(context, phone),
                    icon: const Icon(Icons.call, size: 16),
                    label: const Text('Call'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.greenAccent,
                      side: BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              if (phone.isNotEmpty) const SizedBox(width: 8),
              if (phone.isNotEmpty)
                IconButton(
                  tooltip: 'Copy number',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: phone));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Copied $phone'),
                          duration: const Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
                ),
              if (lat != null && lng != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openInMaps(context, lat, lng),
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Directions'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.lightBlueAccent,
                      side: BorderSide(
                          color: Colors.lightBlueAccent.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
