import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/client.dart';
import '../../state/auth_provider.dart';
import '../../theme.dart';
import '../profile/set_clinic_location.dart';
import '../support/support_provider.dart';

/// Pulls the user's primary role for role-driven Home rendering. Cached for
/// the session so the Home doesn't churn between rebuilds.
final _primaryRoleProvider = FutureProvider<String>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final resp = await dio.get('/auth/me/');
    final data = resp.data as Map;
    final primary = (data['primary_role'] as String?) ?? '';
    if (primary.isNotEmpty) return primary;
    // Fallback: first of `roles[]`, then legacy `role`. Server already
    // backfills, but this keeps the UI safe against stale clients.
    final roles = (data['roles'] as List?)?.cast<String>() ?? const [];
    if (roles.isNotEmpty) return roles.first;
    return (data['role'] as String?) ?? '';
  } catch (_) {
    return '';
  }
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _locationPromptTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskForLocation());
  }

  Future<void> _maybeAskForLocation() async {
    if (_locationPromptTriggered) return;
    final auth = ref.read(authProvider);
    if (auth.status != AuthStatus.verified) return;
    if (auth.clinicLocationSet) return;
    _locationPromptTriggered = true;
    if (!mounted) return;
    // setClinicLocationFromGps handles permissions, GPS read, POST, and the
    // success snackbar ("Clinic location saved.").
    await setClinicLocationFromGps(context, ref);
  }

  @override
  Widget build(BuildContext context) {
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

class _QuickNavRow extends ConsumerWidget {
  const _QuickNavRow();

  // Default order — Circles sits below the row of 4 (in row 2), after
  // Support + Rankings, since it's the lowest-traffic entry point. Some
  // roles override the row-1 mix below.
  static const _defaultRow1 = [
    (icon: Icons.medical_services_outlined, label: 'Associates', path: '/associates'),
    (icon: Icons.store_outlined, label: 'Vendors', path: '/vendors'),
    (icon: Icons.handshake_outlined, label: 'Support', path: '/support'),
    (icon: Icons.leaderboard, label: 'Rankings', path: '/support/leaderboard'),
  ];
  // Associate doctor's row-1 leads with Find Associates (their inbound feed)
  // and drops Vendors (lower priority for them than Support / Rankings).
  static const _associateRow1 = [
    (icon: Icons.medical_services_outlined, label: 'Find Gigs', path: '/associates'),
    (icon: Icons.handshake_outlined, label: 'Support', path: '/support'),
    (icon: Icons.store_outlined, label: 'Vendors', path: '/vendors'),
    (icon: Icons.leaderboard, label: 'Rankings', path: '/support/leaderboard'),
  ];
  static const _row2 = [
    (icon: Icons.people_outline, label: 'Circles', path: '/circles'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = ref.watch(_primaryRoleProvider).valueOrNull ?? '';
    final row1 = primary == 'associate_doctor' ? _associateRow1 : _defaultRow1;
    // 4 tiles in row 1 + Circles in row 2 (left-aligned, same width as a
    // row-1 tile). All five always visible — no horizontal scroll. Tiles
    // stretch to fill their column, so labels never clip at large font
    // scales because the tile height is content-driven (IntrinsicHeight via
    // the Column's natural sizing).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < row1.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _NavTile(item: row1[i])),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Row 2 — Circles. Use 4 expandeds with 3 invisible spacers so the
        // visible tile keeps the same width as a row-1 tile.
        Row(
          children: [
            Expanded(child: _NavTile(item: _row2[0])),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  final ({IconData icon, String label, String path}) item;
  const _NavTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(item.path),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        // No fixed height — Column sizes to its content so labels can grow
        // with the system font scale without clipping.
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: MedUnityColors.primary, size: 24),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
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
      // Slimmer than the original 20px-padded / 36px-pts version — frees
      // ~30 vertical pixels for the role-driven sections below.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MedUnityColors.primary, Color(0xFF1A4FA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: async.when(
        loading: () => const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator(color: Colors.white))),
        error: (_, __) => const Text('—',
            style: TextStyle(color: Colors.white, fontSize: 22)),
        data: (data) {
          final pts = data['total_points'] as int? ?? 0;
          final rank = data['rank'] as int? ?? 0;
          return Row(
            children: [
              const Icon(Icons.stars_rounded, color: Colors.amber, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$pts',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            height: 1)),
                    const SizedBox(width: 6),
                    const Text('Brownie Points',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('#$rank',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1)),
                  const SizedBox(width: 4),
                  const Text('Rank',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
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
