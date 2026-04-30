import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../theme.dart';
import 'consultants_provider.dart';

Future<void> showAvailabilityToggle(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _AvailabilitySheet(ref: ref),
  );
}

class _AvailabilitySheet extends StatefulWidget {
  final WidgetRef ref;
  const _AvailabilitySheet({required this.ref});

  @override
  State<_AvailabilitySheet> createState() => _AvailabilitySheetState();
}

class _AvailabilitySheetState extends State<_AvailabilitySheet> {
  bool _loading = false;

  Future<void> _toggle(bool available) async {
    setState(() => _loading = true);
    double? lat, lng;

    if (available) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}
    }

    final ok = await widget.ref
        .read(availabilityProvider.notifier)
        .toggle(available: available, lat: lat, lng: lng);

    if (mounted) {
      Navigator.pop(context);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update availability.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = widget.ref.watch(availabilityProvider);
    final isAvailable = async.valueOrNull?['is_available'] as bool? ?? false;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          const Text('Consultation Availability',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Toggle your availability so nearby clinics can request your consultation.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 28),
          if (_loading)
            const CircularProgressIndicator()
          else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isAvailable ? null : () => _toggle(true),
                icon: const Icon(Icons.circle, size: 12, color: Colors.white),
                label: const Text('Set as Available'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.green[100],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isAvailable ? () => _toggle(false) : null,
                icon: const Icon(Icons.circle_outlined, size: 12),
                label: const Text('Set as Unavailable'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
