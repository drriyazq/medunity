import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import 'associate_provider.dart';

class FindAssociatesScreen extends ConsumerStatefulWidget {
  const FindAssociatesScreen({super.key});

  @override
  ConsumerState<FindAssociatesScreen> createState() =>
      _FindAssociatesScreenState();
}

class _FindAssociatesScreenState extends ConsumerState<FindAssociatesScreen> {
  String _sort = 'distance';
  String? _slotKind;
  final _maxRateCtrl = TextEditingController();

  @override
  void dispose() {
    _maxRateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) =>
          const Center(child: Text('Could not load your profile.')),
      data: (profile) => _buildBody(profile),
    );
  }

  Widget _buildBody(Map<String, dynamic> profile) {
    final clinic = profile['clinic'] as Map?;
    final lat = clinic?['lat'];
    final lng = clinic?['lng'];

    if (lat == null || lng == null) {
      return _NeedLocationView();
    }

    final args = AssociateSearchArgs(
      lat: double.parse(lat.toString()),
      lng: double.parse(lng.toString()),
      slotKind: _slotKind,
      sort: _sort,
      maxRate:
          _maxRateCtrl.text.trim().isEmpty ? null : _maxRateCtrl.text.trim(),
    );
    final async = ref.watch(associateSearchProvider(args));

    return Column(
      children: [
        // Filter bar
        Container(
          color: Colors.grey[100],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('Sort:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'distance', label: Text('Nearest')),
                        ButtonSegment(value: 'rate', label: Text('Cheapest')),
                        ButtonSegment(value: 'rating', label: Text('Top Rated')),
                      ],
                      selected: {_sort},
                      onSelectionChanged: (s) =>
                          setState(() => _sort = s.first),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Per slot'),
                      selected: _slotKind == 'per_slot',
                      onSelected: (s) => setState(
                          () => _slotKind = s ? 'per_slot' : null),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Per day'),
                      selected: _slotKind == 'per_day',
                      onSelected: (s) => setState(
                          () => _slotKind = s ? 'per_day' : null),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _maxRateCtrl,
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixText: '≤ ₹',
                        hintText: 'Max',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load nearby associates.'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () =>
                          ref.invalidate(associateSearchProvider(args)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return _EmptyView(onRefresh: () =>
                    ref.invalidate(associateSearchProvider(args)));
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(associateSearchProvider(args)),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _AssociateCard(item: items[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AssociateCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AssociateCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final id = item['professional_id'] as int;
    final name = (item['full_name'] as String?) ?? 'Doctor';
    final spec = (item['specialization_display'] as String?) ?? '';
    final dist = (item['distance_km'] as num?)?.toDouble();
    final ratePerSlot = item['rate_per_slot'];
    final ratePerDay = item['rate_per_day'];
    final slotHours = item['slot_hours'] as int?;
    final avgRating = (item['avg_rating'] as num?)?.toDouble();
    final reviewCount = item['review_count'] as int? ?? 0;
    final bio = (item['bio'] as String?) ?? '';
    final city = (item['base_city'] as String?) ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/associates/$id'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: MedUnityColors.primary.withOpacity(0.12),
                  child: const Icon(Icons.person, color: MedUnityColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('$spec${city.isNotEmpty ? " · $city" : ""}',
                          style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                    ],
                  ),
                ),
                if (dist != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: MedUnityColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${dist.toStringAsFixed(2)} km',
                      style: const TextStyle(
                          color: MedUnityColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(bio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[800], fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (ratePerSlot != null)
                  _PillChip(
                    icon: Icons.access_time,
                    label:
                        '₹$ratePerSlot / ${slotHours ?? 4}h slot',
                  ),
                if (ratePerDay != null)
                  _PillChip(
                    icon: Icons.calendar_today,
                    label: '₹$ratePerDay / day',
                  ),
                if (avgRating != null)
                  _PillChip(
                    icon: Icons.star_rounded,
                    label: '${avgRating.toStringAsFixed(1)} ($reviewCount)',
                    color: Colors.amber[700]!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _PillChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey[700]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyView({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medical_services_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text(
              'No associates available nearby.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Try clearing filters or pull to refresh.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRefresh, child: const Text('Refresh')),
          ],
        ),
      ),
    );
  }
}

class _NeedLocationView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text(
              'Set your clinic location first.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'We use it to find associates close to you.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.push('/profile'),
              child: const Text('Open Profile'),
            ),
          ],
        ),
      ),
    );
  }
}
