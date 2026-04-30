import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import 'sos_provider.dart';

class SelectRecipientsScreen extends ConsumerStatefulWidget {
  final String category;
  final String categoryDisplay;
  final Position position;

  const SelectRecipientsScreen({
    super.key,
    required this.category,
    required this.categoryDisplay,
    required this.position,
  });

  @override
  ConsumerState<SelectRecipientsScreen> createState() => _SelectRecipientsScreenState();
}

class _SelectRecipientsScreenState extends ConsumerState<SelectRecipientsScreen> {
  final Set<int> _selected = {};
  bool _initialised = false;

  @override
  Widget build(BuildContext context) {
    final args = NearbyDoctorsArgs(
      widget.position.latitude,
      widget.position.longitude,
    );
    final async = ref.watch(nearbyDoctorsProvider(args));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Recipients'),
        backgroundColor: MedUnityColors.sos,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(error: e.toString()),
        data: (data) {
          final doctors = (data['doctors'] as List).cast<Map<String, dynamic>>();
          final radiusKm = data['radius_km'];

          if (!_initialised) {
            _selected.addAll(doctors.map((d) => d['professional_id'] as int));
            _initialised = true;
          }

          if (doctors.isEmpty) {
            return const _EmptyState();
          }

          return Column(
            children: [
              _Header(
                category: widget.categoryDisplay,
                radiusKm: radiusKm is num ? radiusKm.toDouble() : 0,
                total: doctors.length,
                selected: _selected.length,
                onSelectAll: () => setState(() {
                  _selected
                    ..clear()
                    ..addAll(doctors.map((d) => d['professional_id'] as int));
                }),
                onClearAll: () => setState(_selected.clear),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: doctors.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final doc = doctors[i];
                    final id = doc['professional_id'] as int;
                    final checked = _selected.contains(id);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(id);
                        } else {
                          _selected.remove(id);
                        }
                      }),
                      title: Text(
                        doc['full_name'] as String? ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${doc['specialization_display'] ?? ''}'
                        ' · ${doc['clinic_name'] ?? ''}'
                        ' · ${doc['distance_km']} km',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: MedUnityColors.sos,
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selected.isEmpty ? null : _proceed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MedUnityColors.sos,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        'Send to ${_selected.length} doctor${_selected.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _proceed() {
    context.pushReplacement(
      '/sos/countdown',
      extra: {
        'category': widget.category,
        'categoryDisplay': widget.categoryDisplay,
        'position': widget.position,
        'recipientIds': _selected.toList(),
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String category;
  final double radiusKm;
  final int total;
  final int selected;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;

  const _Header({
    required this.category,
    required this.radiusKm,
    required this.total,
    required this.selected,
    required this.onSelectAll,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: MedUnityColors.sos.withOpacity(0.06),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: MedUnityColors.sos,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$total doctor${total == 1 ? '' : 's'} found within ${radiusKm.toStringAsFixed(1)} km. '
            'Untick anyone you do not want to alert.',
            style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('$selected selected',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              TextButton(onPressed: onSelectAll, child: const Text('Select all')),
              TextButton(onPressed: onClearAll, child: const Text('Clear')),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 56, color: MedUnityColors.textSecondary),
              const SizedBox(height: 12),
              const Text(
                'No nearby doctors found within 5 km.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                'SOS cannot be sent if no one is in range.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: MedUnityColors.sos),
              const SizedBox(height: 12),
              const Text('Could not load nearby doctors.',
                  style: TextStyle(fontSize: 15)),
              const SizedBox(height: 6),
              Text(error,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
}
