import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import 'support_provider.dart';

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lbAsync = ref.watch(leaderboardProvider);
    final myAsync = ref.watch(myPointsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(leaderboardProvider);
        ref.invalidate(myPointsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // My points card
          myAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (data) => _MyPointsCard(data: data),
          ),
          const SizedBox(height: 20),
          const Text('Regional Leaderboard',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          lbAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('Could not load leaderboard.')),
            data: (rows) {
              if (rows.isEmpty) {
                return const Center(
                  child: Text('No points awarded yet.',
                      style: TextStyle(color: MedUnityColors.textSecondary)),
                );
              }
              return Column(
                children: rows.map((r) => _LeaderboardRow(row: r)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MyPointsCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MyPointsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final pts = data['total_points'] as int? ?? 0;
    final rank = data['rank'] as int? ?? 0;
    final history = (data['history'] as List? ?? []).cast<Map<String, dynamic>>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MedUnityColors.primary, Color(0xFF1A4FA8)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars_rounded, color: Colors.amber, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$pts Brownie Points',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                    Text('You are ranked #$rank',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            const Text('Recent activity',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 6),
            ...history.take(3).map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text('+${h['points']}',
                      style: const TextStyle(
                          color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(h['reason'] as String? ?? '',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _LeaderboardRow({required this.row});

  static const _rankEmoji = {1: '🥇', 2: '🥈', 3: '🥉'};

  @override
  Widget build(BuildContext context) {
    final rank = row['rank'] as int? ?? 0;
    final isTop3 = rank <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTop3 ? Colors.amber.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop3 ? Colors.amber.withOpacity(0.3) : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              _rankEmoji[rank] ?? '#$rank',
              style: TextStyle(
                fontSize: isTop3 ? 20 : 14,
                fontWeight: FontWeight.bold,
                color: isTop3 ? null : Colors.grey[600],
              ),
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
                Text(
                  '${row['specialization']}${(row['clinic_city'] as String? ?? '').isNotEmpty ? ' · ${row['clinic_city']}' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: MedUnityColors.textSecondary),
                ),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.stars_rounded, color: Colors.amber, size: 18),
              const SizedBox(width: 4),
              Text(
                '${row['total_points']}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isTop3 ? 16 : 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
