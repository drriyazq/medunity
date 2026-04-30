import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import 'consultants_provider.dart';

class FindConsultantsTab extends ConsumerStatefulWidget {
  const FindConsultantsTab({super.key});

  @override
  ConsumerState<FindConsultantsTab> createState() => _FindConsultantsTabState();
}

class _FindConsultantsTabState extends ConsumerState<FindConsultantsTab> {
  String _selectedSpec = '';
  double _radiusKm = 10;

  static const _specializations = [
    ('', 'All'),
    ('endodontist', 'Endodontist'),
    ('oral_surgeon', 'Oral Surgeon'),
    ('orthodontist', 'Orthodontist'),
    ('anaesthesiologist', 'Anaesthesiologist'),
    ('prosthodontist', 'Prosthodontist'),
    ('periodontist', 'Periodontist'),
    ('general_surgeon', 'General Surgeon'),
    ('paediatrician', 'Paediatrician'),
  ];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(nearbyConsultantsProvider);

    return Column(
      children: [
        // Filter row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ..._specializations.map((s) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(s.$2, style: const TextStyle(fontSize: 12)),
                      selected: _selectedSpec == s.$1,
                      onSelected: (_) {
                        setState(() => _selectedSpec = s.$1);
                        ref
                            .read(nearbyConsultantsProvider.notifier)
                            .load(specialization: s.$1, radiusKm: _radiusKm);
                      },
                    ),
                  )),
            ],
          ),
        ),

        // Radius row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.my_location, size: 16, color: MedUnityColors.textSecondary),
              const SizedBox(width: 8),
              Text('Within ${_radiusKm.toStringAsFixed(0)} km',
                  style: const TextStyle(fontSize: 13, color: MedUnityColors.textSecondary)),
              Expanded(
                child: Slider(
                  value: _radiusKm,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  activeColor: MedUnityColors.primary,
                  onChangeEnd: (v) {
                    setState(() => _radiusKm = v);
                    ref
                        .read(nearbyConsultantsProvider.notifier)
                        .load(specialization: _selectedSpec, radiusKm: v);
                  },
                  onChanged: (v) => setState(() => _radiusKm = v),
                ),
              ),
            ],
          ),
        ),

        // Results
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              final msg = e.toString().contains('400')
                  ? 'Set your clinic location to find nearby consultants.'
                  : 'Could not load consultants.';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_off, size: 48, color: MedUnityColors.textSecondary),
                      const SizedBox(height: 12),
                      Text(msg,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: MedUnityColors.textSecondary)),
                    ],
                  ),
                ),
              );
            },
            data: (consultants) {
              if (consultants.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medical_services_outlined,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text('No available consultants nearby.',
                          style: TextStyle(color: MedUnityColors.textSecondary)),
                      const SizedBox(height: 4),
                      const Text('Try increasing the radius.',
                          style: TextStyle(
                              fontSize: 12, color: MedUnityColors.textSecondary)),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref
                    .read(nearbyConsultantsProvider.notifier)
                    .load(specialization: _selectedSpec, radiusKm: _radiusKm),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: consultants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) =>
                      _ConsultantCard(consultant: consultants[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConsultantCard extends StatelessWidget {
  final Map<String, dynamic> consultant;
  const _ConsultantCard({required this.consultant});

  @override
  Widget build(BuildContext context) {
    final avgRating = consultant['avg_rating'] as double?;
    final reviewCount = consultant['review_count'] as int? ?? 0;
    final distKm = consultant['distance_km'] as double?;

    return InkWell(
      onTap: () => context.push('/consultants/profile/${consultant['id']}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: consultant['profile_photo'] != null
                      ? NetworkImage(consultant['profile_photo'] as String)
                      : null,
                  child: consultant['profile_photo'] == null
                      ? const Icon(Icons.person, size: 28)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(consultant['full_name'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(consultant['specialization'] as String,
                      style: const TextStyle(
                          fontSize: 13, color: MedUnityColors.primary)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (avgRating != null) ...[
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text('$avgRating ($reviewCount)',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 8),
                      ],
                      if (distKm != null)
                        Text('${distKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                fontSize: 12,
                                color: MedUnityColors.textSecondary)),
                    ],
                  ),
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
