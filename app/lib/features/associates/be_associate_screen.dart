import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../theme.dart';
import 'associate_provider.dart';

class BeAssociateScreen extends ConsumerStatefulWidget {
  const BeAssociateScreen({super.key});

  @override
  ConsumerState<BeAssociateScreen> createState() => _BeAssociateScreenState();
}

class _BeAssociateScreenState extends ConsumerState<BeAssociateScreen> {
  final _bioCtrl = TextEditingController();
  final _slotHoursCtrl = TextEditingController();
  final _ratePerSlotCtrl = TextEditingController();
  final _ratePerDayCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _initialised = false;
  bool _saving = false;
  double? _baseLat;
  double? _baseLng;

  @override
  void dispose() {
    _bioCtrl.dispose();
    _slotHoursCtrl.dispose();
    _ratePerSlotCtrl.dispose();
    _ratePerDayCtrl.dispose();
    _radiusCtrl.dispose();
    _cityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> data) {
    if (_initialised) return;
    _initialised = true;
    _bioCtrl.text = (data['bio'] as String?) ?? '';
    _slotHoursCtrl.text = (data['slot_hours']?.toString()) ?? '4';
    _ratePerSlotCtrl.text = data['rate_per_slot']?.toString() ?? '';
    _ratePerDayCtrl.text = data['rate_per_day']?.toString() ?? '';
    _radiusCtrl.text = (data['travel_radius_km']?.toString()) ?? '10';
    _cityCtrl.text = (data['base_city'] as String?) ?? '';
    _notesCtrl.text = (data['notes'] as String?) ?? '';
    _baseLat = (data['base_lat'] as num?)?.toDouble();
    _baseLng = (data['base_lng'] as num?)?.toDouble();
  }

  Future<void> _useMyLocation() async {
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() {
        _baseLat = pos.latitude;
        _baseLng = pos.longitude;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read GPS.')),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final patch = <String, dynamic>{
      'bio': _bioCtrl.text.trim(),
      'slot_hours': int.tryParse(_slotHoursCtrl.text.trim()) ?? 4,
      'rate_per_slot': _ratePerSlotCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_ratePerSlotCtrl.text.trim()),
      'rate_per_day': _ratePerDayCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_ratePerDayCtrl.text.trim()),
      'travel_radius_km': int.tryParse(_radiusCtrl.text.trim()) ?? 10,
      'base_city': _cityCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      if (_baseLat != null) 'base_lat': _baseLat,
      if (_baseLng != null) 'base_lng': _baseLng,
    };

    final ok =
        await ref.read(associateProfileNotifierProvider.notifier).save(patch);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Saved.' : 'Save failed.'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _toggle(bool v) async {
    final ok = await ref
        .read(associateProfileNotifierProvider.notifier)
        .toggle(newValue: v);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Could not toggle — make sure at least one rate is set.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(associateProfileNotifierProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
          child: Text('Could not load your associate profile.')),
      data: (data) {
        _hydrate(data);
        final isAvailable = data['is_available_for_hire'] as bool? ?? false;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Toggle banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isAvailable
                    ? Colors.green.withOpacity(0.08)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isAvailable
                        ? Colors.green.withOpacity(0.4)
                        : Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Icon(
                    isAvailable
                        ? Icons.check_circle
                        : Icons.toggle_off_outlined,
                    color: isAvailable
                        ? Colors.green
                        : MedUnityColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAvailable
                              ? 'Available for hire'
                              : 'Not currently listed',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          isAvailable
                              ? 'Clinics nearby can find and book you.'
                              : 'Set your rates below, then turn on to start receiving bookings.',
                          style: TextStyle(
                              color: Colors.grey[700], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(value: isAvailable, onChanged: _toggle),
                ],
              ),
            ),
            const SizedBox(height: 18),

            const _SectionTitle('Bio'),
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'A few sentences about your experience and comfort areas.',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),
            const _SectionTitle('Rates'),
            const Text(
              'Set at least one. Rates are display-only — the platform does not handle payment.',
              style: TextStyle(fontSize: 12, color: MedUnityColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _slotHoursCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Slot length (hrs)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ratePerSlotCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      prefixText: '₹ ',
                      labelText: 'Rate per slot',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ratePerDayCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: '₹ ',
                labelText: 'Rate per day',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),
            const _SectionTitle('Where you can travel'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Base city',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _radiusCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Radius (km)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _baseLat == null
                        ? 'No base location pinned yet.'
                        : 'Pinned at: ${_baseLat!.toStringAsFixed(4)}, ${_baseLng!.toStringAsFixed(4)}',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: _useMyLocation,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Use GPS'),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const _SectionTitle('Notes for clinics'),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g. "Available evenings only" or "Comfortable with paedo"',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: MedUnityColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Save',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}
