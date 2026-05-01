import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';
import 'sos_provider.dart';

class IncomingSosScreen extends ConsumerStatefulWidget {
  final int alertId;

  const IncomingSosScreen({super.key, required this.alertId});

  @override
  ConsumerState<IncomingSosScreen> createState() => _IncomingSosScreenState();
}

class _IncomingSosScreenState extends ConsumerState<IncomingSosScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _respond(String status) async {
    setState(() => _responding = true);
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {}

    await ref.read(sosRespondProvider.notifier).respond(
          alertId: widget.alertId,
          status: status,
          lat: pos?.latitude,
          lng: pos?.longitude,
        );

    if (!mounted) return;
    final respState = ref.read(sosRespondProvider);
    if (respState is AsyncError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not submit response.'),
            backgroundColor: Colors.red),
      );
      setState(() => _responding = false);
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertAsync = ref.watch(incomingSosProvider(widget.alertId));

    return Scaffold(
      backgroundColor: const Color(0xFF1A0000),
      body: alertAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: MedUnityColors.sos)),
        error: (_, __) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.grey[600], size: 48),
              const SizedBox(height: 16),
              const Text('Could not load SOS details.',
                  style: TextStyle(color: Colors.white70)),
              TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Go Home',
                      style: TextStyle(color: Colors.white38))),
            ],
          ),
        ),
        data: (alert) {
          final isActive = alert['is_active'] as bool? ?? false;
          final alreadyResponded = alert['my_response'] as String?;

          if (!isActive) {
            return _ExpiredView(onHome: () => context.go('/home'));
          }

          if (alreadyResponded != null) {
            return _AlreadyRespondedView(
              status: alreadyResponded,
              onHome: () => context.go('/home'),
            );
          }

          final senderLat = alert['sender_lat'] as double?;
          final senderLng = alert['sender_lng'] as double?;
          final categoryDisplay = alert['category_display'] as String? ?? 'SOS';

          return SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                // Pulsing SOS badge
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, child) => Transform.scale(
                    scale: 1.0 + _pulseController.value * 0.06,
                    child: child,
                  ),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MedUnityColors.sos.withOpacity(0.2),
                      border: Border.all(color: MedUnityColors.sos, width: 2.5),
                    ),
                    child: const Icon(Icons.sos, color: MedUnityColors.sos, size: 48),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'SOS Alert Nearby',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  categoryDisplay,
                  style: TextStyle(color: Colors.red[200], fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'A verified doctor nearby needs immediate help.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Sender location card with "Open in Maps" button
                if (senderLat != null && senderLng != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: MedUnityColors.sos, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SOS Location',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${senderLat.toStringAsFixed(5)}, ${senderLng.toStringAsFixed(5)}',
                                  style: TextStyle(
                                      color: Colors.grey[400], fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=$senderLat,$senderLng');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.directions, size: 16),
                            label: const Text('Open in Maps'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.lightBlueAccent,
                              side: BorderSide(
                                  color: Colors.lightBlueAccent.withOpacity(0.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),

                const SizedBox(height: 24),

                if (_responding)
                  const CircularProgressIndicator(color: MedUnityColors.sos)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _respond('accepted'),
                            icon: const Icon(Icons.directions_run),
                            label: const Text('Accept — I\'m On My Way',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => _respond('declined'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white38),
                              foregroundColor: Colors.white54,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cannot Help Right Now'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ExpiredView extends StatelessWidget {
  final VoidCallback onHome;
  const _ExpiredView({required this.onHome});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_off_outlined, color: Colors.grey[600], size: 64),
            const SizedBox(height: 16),
            const Text('SOS Alert Expired',
                style: TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('This alert is no longer active.',
                style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onHome,
              style: ElevatedButton.styleFrom(
                  backgroundColor: MedUnityColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlreadyRespondedView extends StatelessWidget {
  final String status;
  final VoidCallback onHome;
  const _AlreadyRespondedView({required this.status, required this.onHome});

  @override
  Widget build(BuildContext context) {
    final accepted = status == 'accepted';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              accepted ? Icons.check_circle : Icons.cancel_outlined,
              color: accepted ? Colors.green : Colors.grey[600],
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              accepted ? 'You accepted this SOS' : 'You declined this SOS',
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onHome,
              style: ElevatedButton.styleFrom(
                  backgroundColor: MedUnityColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}
