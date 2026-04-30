import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'circles_provider.dart';
import 'create_circle_sheet.dart';

class CirclesScreen extends ConsumerWidget {
  const CirclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Circles'),
          bottom: const TabBar(
            tabs: [Tab(text: 'My Circles'), Tab(text: 'Nearby')],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final created = await showCreateCircleSheet(context);
                if (created == true) ref.invalidate(myCirclesProvider);
              },
            ),
          ],
        ),
        body: const TabBarView(
          children: [_MyCirclesTab(), _NearbyTab()],
        ),
      ),
    );
  }
}

// ── My Circles tab ────────────────────────────────────────────────────────────

class _MyCirclesTab extends ConsumerWidget {
  const _MyCirclesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myCirclesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Could not load circles.'),
            TextButton(
              onPressed: () => ref.read(myCirclesProvider.notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (circles) {
        if (circles.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text('You haven\'t joined any circles yet.',
                    style: TextStyle(color: MedUnityColors.textSecondary)),
                const SizedBox(height: 8),
                const Text('Explore nearby circles or create one.',
                    style: TextStyle(color: MedUnityColors.textSecondary, fontSize: 13)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(myCirclesProvider.notifier).load(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: circles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _CircleTile(circle: circles[i]),
          ),
        );
      },
    );
  }
}

// ── Nearby tab ────────────────────────────────────────────────────────────────

class _NearbyTab extends ConsumerWidget {
  const _NearbyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nearbyCirclesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        final msg = e.toString().contains('400')
            ? 'Set your clinic location in profile to see nearby circles.'
            : 'Could not load nearby circles.';
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: MedUnityColors.textSecondary)),
          ),
        );
      },
      data: (circles) {
        if (circles.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_searching, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text('No circles found within 10 km.',
                    style: TextStyle(color: MedUnityColors.textSecondary)),
                const SizedBox(height: 8),
                const Text('Create one to get started.',
                    style: TextStyle(color: MedUnityColors.textSecondary, fontSize: 13)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: circles.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _NearbyCircleTile(circle: circles[i], ref: ref),
        );
      },
    );
  }
}

// ── Tiles ─────────────────────────────────────────────────────────────────────

class _CircleTile extends StatelessWidget {
  final Map<String, dynamic> circle;
  const _CircleTile({required this.circle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/circles/${circle['id']}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: MedUnityColors.primary.withOpacity(0.12),
              child: const Icon(Icons.people, color: MedUnityColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(circle['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(
                    '${circle['member_count']} members • ${circle['my_role'] ?? 'member'}',
                    style: const TextStyle(
                        fontSize: 12, color: MedUnityColors.textSecondary),
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

class _NearbyCircleTile extends StatefulWidget {
  final Map<String, dynamic> circle;
  final WidgetRef ref;
  const _NearbyCircleTile({required this.circle, required this.ref});

  @override
  State<_NearbyCircleTile> createState() => _NearbyCircleTileState();
}

class _NearbyCircleTileState extends State<_NearbyCircleTile> {
  bool _joining = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/circles/${widget.circle['id']}/join/');
      widget.ref.invalidate(myCirclesProvider);
      widget.ref.invalidate(nearbyCirclesProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join circle.')),
        );
      }
    }
    if (mounted) setState(() => _joining = false);
  }

  @override
  Widget build(BuildContext context) {
    final distKm = widget.circle['distance_km'] as double?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.green.withOpacity(0.12),
            child: const Icon(Icons.people_outline, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.circle['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text(
                  '${widget.circle['member_count']} members'
                  '${distKm != null ? ' • ${distKm.toStringAsFixed(1)} km away' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: MedUnityColors.textSecondary),
                ),
              ],
            ),
          ),
          _joining
              ? const SizedBox(
                  width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(onPressed: _join, child: const Text('Join')),
        ],
      ),
    );
  }
}
