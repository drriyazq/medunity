import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
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
              const SizedBox(height: 24),

              // Response count
              statusAsync.when(
                loading: () => const _ResponseCountCard(count: 0, loading: true),
                error: (_, __) => const _ResponseCountCard(count: 0, loading: false),
                data: (data) => _ResponseCountCard(
                  count: data['accepted_count'] as int? ?? 0,
                  loading: false,
                ),
              ),
              const SizedBox(height: 24),

              // Map with responder dots
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: statusAsync.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(color: MedUnityColors.sos)),
                    error: (_, __) => Center(
                        child: Text('Could not load map.',
                            style: TextStyle(color: Colors.grey[400]))),
                    data: (data) {
                      final dots = (data['responder_dots'] as List? ?? [])
                          .map((d) => LatLng(
                                (d['lat'] as num).toDouble(),
                                (d['lng'] as num).toDouble(),
                              ))
                          .toList();
                      return _ResponderMap(dots: dots);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Refreshing every 15 seconds • Alert expires in 2 hours',
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

class _ResponderMap extends StatelessWidget {
  final List<LatLng> dots;
  const _ResponderMap({required this.dots});

  @override
  Widget build(BuildContext context) {
    if (dots.isEmpty) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_outlined, color: Colors.grey[700], size: 48),
              const SizedBox(height: 8),
              Text('Responder locations will appear here',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final center = LatLng(
      dots.map((d) => d.latitude).reduce((a, b) => a + b) / dots.length,
      dots.map((d) => d.longitude).reduce((a, b) => a + b) / dots.length,
    );

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: center, zoom: 13),
      markers: dots
          .asMap()
          .entries
          .map((e) => Marker(
                markerId: MarkerId('dot_${e.key}'),
                position: e.value,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen),
                infoWindow: const InfoWindow(title: 'Responder'),
              ))
          .toSet(),
      myLocationEnabled: false,
      zoomControlsEnabled: false,
      mapType: MapType.normal,
    );
  }
}
