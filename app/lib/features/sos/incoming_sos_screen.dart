import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
      // Refresh both providers so dashboard + the alert's own data update
      ref.invalidate(receivedAlertsProvider);
      ref.invalidate(incomingSosProvider(widget.alertId));
      setState(() => _responding = false);
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

  Future<void> _openInMaps(double lat, double lng) async {
    try {
      await launchUrl(
        Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Maps')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertAsync = ref.watch(incomingSosProvider(widget.alertId));

    return Scaffold(
      backgroundColor: const Color(0xFF1A0000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Incoming SOS'),
      ),
      body: alertAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: MedUnityColors.sos)),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.grey[600], size: 48),
                const SizedBox(height: 16),
                const Text('Could not load SOS details.',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(incomingSosProvider(widget.alertId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (alert) => _buildContent(alert),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> alert) {
    final isActive = alert['is_active'] as bool? ?? false;
    final myResponse = alert['my_response'] as String?;
    final categoryDisplay = alert['category_display'] as String? ?? 'SOS';
    final senderName = (alert['sender_name'] as String?) ?? 'A doctor';
    final senderPhone = (alert['sender_phone'] as String?) ?? '';
    final senderSpec =
        (alert['sender_specialization_display'] as String?) ?? '';
    final senderClinic = (alert['sender_clinic_name'] as String?) ?? '';
    final senderAddress = (alert['sender_clinic_address'] as String?) ?? '';
    final senderCity = (alert['sender_clinic_city'] as String?) ?? '';
    final senderLat = (alert['sender_lat'] as num?)?.toDouble();
    final senderLng = (alert['sender_lng'] as num?)?.toDouble();
    final createdAt =
        DateTime.tryParse(alert['created_at'] as String? ?? '')?.toLocal();
    final timeStr = createdAt != null
        ? DateFormat('d MMM yyyy, h:mm a').format(createdAt)
        : '';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Pulsing SOS badge + status pill
          Center(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (_, child) => Transform.scale(
                scale: 1.0 +
                    (isActive && myResponse == null
                        ? _pulseController.value * 0.08
                        : 0),
                child: child,
              ),
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MedUnityColors.sos.withOpacity(0.18),
                  border:
                      Border.all(color: MedUnityColors.sos, width: 2),
                ),
                child: const Icon(Icons.sos,
                    color: MedUnityColors.sos, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              categoryDisplay,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 6),
          Center(child: _StatusPill(isActive: isActive, myResponse: myResponse)),
          if (timeStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(timeStr,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ),
          ],

          const SizedBox(height: 24),

          // Sender card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: MedUnityColors.sos.withOpacity(0.18),
                      child: const Icon(Icons.person,
                          color: MedUnityColors.sos),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(senderName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          if (senderSpec.isNotEmpty)
                            Text(senderSpec,
                                style: TextStyle(
                                    color: Colors.grey[400], fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (senderClinic.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.local_hospital_outlined,
                          color: Colors.grey[500], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          senderClinic,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
                if (senderAddress.isNotEmpty || senderCity.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place_outlined,
                          color: Colors.grey[500], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          [senderAddress, senderCity]
                              .where((s) => s.isNotEmpty)
                              .join(', '),
                          style: TextStyle(
                              color: Colors.grey[300], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (senderPhone.isNotEmpty)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _call(senderPhone),
                          icon: const Icon(Icons.call, size: 18),
                          label: const Text('Call'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    if (senderPhone.isNotEmpty &&
                        senderLat != null &&
                        senderLng != null)
                      const SizedBox(width: 8),
                    if (senderLat != null && senderLng != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _openInMaps(senderLat, senderLng),
                          icon: const Icon(Icons.directions, size: 18),
                          label: const Text('Directions'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.lightBlueAccent,
                            side: BorderSide(
                                color: Colors.lightBlueAccent
                                    .withOpacity(0.5)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action area — Accept / Decline (only if active + not yet responded)
          if (isActive && myResponse == null) ...[
            if (_responding)
              const Center(
                  child:
                      CircularProgressIndicator(color: MedUnityColors.sos))
            else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _respond('accepted'),
                  icon: const Icon(Icons.directions_run),
                  label: const Text("Accept — I'm On My Way",
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
              const SizedBox(height: 10),
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
          ] else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  isActive
                      ? (myResponse == 'accepted'
                          ? "You're already on your way."
                          : 'You declined this SOS.')
                      : (myResponse == 'accepted'
                          ? 'You accepted this SOS (now expired).'
                          : myResponse == 'declined'
                              ? 'You declined this SOS (now expired).'
                              : 'This SOS has expired.'),
                  style:
                      TextStyle(color: Colors.grey[400], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool isActive;
  final String? myResponse;
  const _StatusPill({required this.isActive, required this.myResponse});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (myResponse == 'accepted') {
      color = Colors.green;
      label = 'YOU ACCEPTED';
    } else if (myResponse == 'declined') {
      color = Colors.grey;
      label = 'YOU DECLINED';
    } else if (isActive) {
      color = MedUnityColors.sos;
      label = 'ACTIVE — RESPOND';
    } else {
      color = Colors.grey;
      label = 'EXPIRED';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
