import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../support/support_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MedUnity'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myPointsProvider);
          ref.invalidate(requestsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            _BrowniePointsCard(),
            SizedBox(height: 20),
            _QuickNavRow(),
            SizedBox(height: 20),
            _CoverageSection(),
            SizedBox(height: 20),
            _LeaderboardPreview(),
          ],
        ),
      ),
    );
  }
}

// ── Quick nav row ─────────────────────────────────────────────────────────────

class _QuickNavRow extends StatelessWidget {
  const _QuickNavRow();

  static const _items = [
    (icon: Icons.store_outlined, label: 'Vendors', path: '/vendors'),
    (icon: Icons.handshake_outlined, label: 'Support', path: '/support'),
    (icon: Icons.leaderboard, label: 'Rankings', path: '/support/leaderboard'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _items.map((item) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InkWell(
            onTap: () => context.push(item.path),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  Icon(item.icon, color: MedUnityColors.primary, size: 24),
                  const SizedBox(height: 4),
                  Text(item.label,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      )).toList(),
    );
  }
}

// ── Brownie Points card ───────────────────────────────────────────────────────

class _BrowniePointsCard extends ConsumerWidget {
  const _BrowniePointsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myPointsProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MedUnityColors.primary, Color(0xFF1A4FA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white)),
        error: (_, __) => const Text('—',
            style: TextStyle(color: Colors.white, fontSize: 32)),
        data: (data) {
          final pts = data['total_points'] as int? ?? 0;
          final rank = data['rank'] as int? ?? 0;
          return Row(
            children: [
              const Icon(Icons.stars_rounded, color: Colors.amber, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$pts',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold)),
                    const Text('Brownie Points',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('#$rank',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const Text('Your rank',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Coverage requests preview ─────────────────────────────────────────────────

class _CoverageSection extends ConsumerWidget {
  const _CoverageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(requestsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Practice Support',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => context.push('/support'),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load requests.',
              style: TextStyle(color: MedUnityColors.textSecondary)),
          data: (requests) {
            final preview = requests.take(3).toList();
            if (preview.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('No open requests nearby.',
                      style: TextStyle(color: MedUnityColors.textSecondary)),
                ),
              );
            }
            return Column(
              children: preview
                  .map((r) => _RequestMiniCard(request: r))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _RequestMiniCard extends StatelessWidget {
  final Map<String, dynamic> request;
  const _RequestMiniCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final type = request['request_type'] as String? ?? 'coverage';
    final icon = type == 'coverage' ? Icons.swap_horiz : Icons.business;
    final color = type == 'coverage' ? Colors.blue : Colors.teal;

    return InkWell(
      onTap: () => context.push('/support/requests/${request['id']}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request['title'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${request['requester_name']} · ${request['city'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 12, color: MedUnityColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Leaderboard preview ───────────────────────────────────────────────────────

class _LeaderboardPreview extends ConsumerWidget {
  const _LeaderboardPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leaderboardProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Top Contributors',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => context.push('/support/leaderboard'),
              child: const Text('Full board'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) => Column(
            children: rows
                .take(3)
                .map((r) => _LeaderRow(row: r))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _LeaderRow({required this.row});

  static const _rankEmoji = {1: '🥇', 2: '🥈', 3: '🥉'};

  @override
  Widget build(BuildContext context) {
    final rank = row['rank'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              _rankEmoji[rank] ?? '#$rank',
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row['full_name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(row['specialization'] as String? ?? '',
                    style: const TextStyle(
                        fontSize: 12, color: MedUnityColors.textSecondary)),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.stars_rounded, color: Colors.amber, size: 16),
              const SizedBox(width: 4),
              Text('${row['total_points']}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
