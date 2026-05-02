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
  String _sort = 'distance';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(nearbyConsultantsProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.grey[50],
          child: Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 16, color: MedUnityColors.textSecondary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Showing live consultants in your specialty nearby. Updated every 15 min.',
                  style: TextStyle(
                      fontSize: 12, color: MedUnityColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        // Sort control
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              const Text('Sort:',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(width: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'distance',
                    label: Text('Distance', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.place_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: 'rating',
                    label: Text('Rating', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.star_outline, size: 16),
                  ),
                ],
                selected: {_sort},
                onSelectionChanged: (s) {
                  setState(() => _sort = s.first);
                  ref
                      .read(nearbyConsultantsProvider.notifier)
                      .load(sort: _sort);
                },
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
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
                      const Icon(Icons.location_off,
                          size: 48, color: MedUnityColors.textSecondary),
                      const SizedBox(height: 12),
                      Text(msg,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: MedUnityColors.textSecondary)),
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
                      const Text('No consultants in your area right now.',
                          style:
                              TextStyle(color: MedUnityColors.textSecondary)),
                      const SizedBox(height: 4),
                      const Text('Pull to refresh.',
                          style: TextStyle(
                              fontSize: 12,
                              color: MedUnityColors.textSecondary)),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref
                    .read(nearbyConsultantsProvider.notifier)
                    .load(sort: _sort),
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
    final avgRating = (consultant['avg_rating'] as num?)?.toDouble();
    final reviewCount = consultant['review_count'] as int? ?? 0;
    final distLabel =
        consultant['distance_label'] as String? ?? 'Available nearby';
    final availableLabel =
        consultant['available_label'] as String? ?? 'Available now';

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
                  radius: 24,
                  backgroundImage: consultant['profile_photo'] != null
                      ? NetworkImage(consultant['profile_photo'] as String)
                      : null,
                  child: consultant['profile_photo'] == null
                      ? const Icon(Icons.person, size: 24)
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
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(consultant['specialization'] as String,
                      style: const TextStyle(
                          fontSize: 12, color: MedUnityColors.primary)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(availableLabel,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.green[800])),
                      ),
                      const SizedBox(width: 6),
                      Text(distLabel,
                          style: const TextStyle(
                              fontSize: 12,
                              color: MedUnityColors.textSecondary)),
                    ],
                  ),
                  if (avgRating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text('$avgRating ($reviewCount)',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
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
