import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/client.dart';
import '../../state/auth_provider.dart';
import '../../theme.dart';
import '../../widgets/primary_role_pill.dart';
import '../circles/circles_provider.dart';
import '../consultants/consultants_provider.dart';
import '../equipment/equipment_provider.dart';
import '../profile/set_clinic_location.dart';
import '../support/support_provider.dart';
import 'nearby_clinics_provider.dart';

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
          ref.invalidate(leaderboardProvider);
          ref.invalidate(_primaryRoleProvider);
          ref.invalidate(nearbyClinicsProvider);
          ref.invalidate(nearbyCirclesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            _BrowniePointsCard(),
            SizedBox(height: 16),
            _QuickNavRow(),
            SizedBox(height: 20),
            _RoleDrivenHomeSections(),
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

// ── Role-driven home sections ────────────────────────────────────────────────
//
// Locked mapping per primary_role (revisit only if user explicitly asks):
//   clinic_owner       → Co-Purchase + Marketplace
//   hospital_owner     → Consultants Live + Available Associates
//   visiting_consultant→ Nearby Clinics & Hospitals + Circles
//   associate_doctor   → Find-Associate posts + Nearby Clinics & Hospitals
//   academic_teaching  → Circles + Top Contributors
//   (anything else)    → Practice Support + Top Contributors  (safe default)

class _RoleDrivenHomeSections extends ConsumerWidget {
  const _RoleDrivenHomeSections();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = ref.watch(_primaryRoleProvider).valueOrNull ?? '';

    final sections = switch (primary) {
      'clinic_owner' => const [_PoolsPreview(), _ListingsPreview()],
      'hospital_owner' => const [
          _ConsultantsLivePreview(),
          _AvailableAssociatesPreview(),
        ],
      'visiting_consultant' => const [
          _NearbyClinicsPreview(),
          _CirclesPreview(),
        ],
      'associate_doctor' => const [
          _FindAssociatePostsPreview(),
          _NearbyClinicsPreview(),
        ],
      'academic_teaching' => const [_CirclesPreview(), _LeaderboardPreview()],
      _ => const [_CoverageSection(), _LeaderboardPreview()],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          sections[i],
        ],
      ],
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  final String title;
  final String seeAllPath;
  final String seeAllLabel;
  const _PreviewHeader({
    required this.title,
    required this.seeAllPath,
    this.seeAllLabel = 'See all',
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        TextButton(
          onPressed: () => context.push(seeAllPath),
          child: Text(seeAllLabel),
        ),
      ],
    );
  }
}

Widget _emptyTile(String text) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(text,
            style: const TextStyle(color: MedUnityColors.textSecondary)),
      ),
    );

// ── Preview: Co-Purchase pools ────────────────────────────────────────────────

class _PoolsPreview extends ConsumerWidget {
  const _PoolsPreview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(poolsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PreviewHeader(title: 'Co-Purchase Pools', seeAllPath: '/marketplace'),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => _emptyTile('Could not load pools.'),
          data: (pools) {
            final preview = pools.take(3).toList();
            if (preview.isEmpty) return _emptyTile('No active pools right now.');
            return Column(children: preview.map(_PoolMiniCard.new).toList());
          },
        ),
      ],
    );
  }
}

class _PoolMiniCard extends StatelessWidget {
  final Map<String, dynamic> pool;
  const _PoolMiniCard(this.pool);
  @override
  Widget build(BuildContext context) {
    final purpose = pool['purpose'] as String? ?? 'bulk_buy';
    final purposeColor = purpose == 'shared_use'
        ? const Color(0xFF8E24AA)
        : const Color(0xFF1E88E5);
    final purposeIcon = purpose == 'shared_use'
        ? Icons.handshake_outlined
        : Icons.local_shipping_outlined;
    final fundingPct = (pool['funding_pct'] as num?)?.toDouble() ?? 0;
    return InkWell(
      onTap: () => context.push('/equipment/pools/${pool['id']}'),
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
                color: purposeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(purposeIcon, color: purposeColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pool['name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    '${fundingPct.toStringAsFixed(0)}% funded · ${pool['member_count']}/${pool['max_members']}',
                    style: const TextStyle(fontSize: 11, color: MedUnityColors.textSecondary),
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

// ── Preview: Marketplace listings ─────────────────────────────────────────────

class _ListingsPreview extends ConsumerWidget {
  const _ListingsPreview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(listingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PreviewHeader(title: 'Marketplace', seeAllPath: '/marketplace'),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => _emptyTile('Could not load listings.'),
          data: (listings) {
            final preview = listings.take(3).toList();
            if (preview.isEmpty) return _emptyTile('No equipment listed nearby right now.');
            return Column(children: preview.map(_ListingMiniCard.new).toList());
          },
        ),
      ],
    );
  }
}

class _ListingMiniCard extends StatelessWidget {
  final Map<String, dynamic> listing;
  const _ListingMiniCard(this.listing);
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/equipment/listings/${listing['id']}'),
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
            const Icon(Icons.medical_services_outlined,
                color: MedUnityColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(listing['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    '₹${listing['price']} · ${listing['condition_display'] ?? ''}',
                    style: const TextStyle(fontSize: 11, color: MedUnityColors.textSecondary),
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

// ── Preview: Live Consultants nearby ──────────────────────────────────────────

class _ConsultantsLivePreview extends ConsumerWidget {
  const _ConsultantsLivePreview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nearbyConsultantsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PreviewHeader(title: 'Live Consultants Nearby', seeAllPath: '/consultants'),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => _emptyTile('Set your clinic location to find consultants nearby.'),
          data: (list) {
            final preview = list.take(3).toList();
            if (preview.isEmpty) return _emptyTile('No live consultants in your area right now.');
            return Column(children: preview.map(_DoctorMiniCard.new).toList());
          },
        ),
      ],
    );
  }
}

// ── Preview: Available Associates near my clinic ──────────────────────────────

class _AvailableAssociatesPreview extends ConsumerWidget {
  const _AvailableAssociatesPreview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reuses the same /associates/search/ endpoint as the Find tab. The
    // searcher's clinic GPS comes from the server side so we don't need to
    // pass lat/lng from the home preview.
    final dio = ref.watch(dioProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PreviewHeader(title: 'Associates Available', seeAllPath: '/associates'),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: () async {
            try {
              final resp = await dio.get('/associates/search/');
              final items = (resp.data['associates'] as List? ?? []);
              return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            } catch (_) {
              return const <Map<String, dynamic>>[];
            }
          }(),
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            final list = snap.data ?? const <Map<String, dynamic>>[];
            final preview = list.take(3).toList();
            if (preview.isEmpty) return _emptyTile('No associates available nearby right now.');
            return Column(children: preview.map(_DoctorMiniCard.new).toList());
          },
        ),
      ],
    );
  }
}

// ── Preview: Nearby Clinics & Hospitals ───────────────────────────────────────

class _NearbyClinicsPreview extends ConsumerWidget {
  const _NearbyClinicsPreview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nearbyClinicsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PreviewHeader(
          title: 'Clinics & Hospitals Nearby',
          seeAllPath: '/consultants',
          seeAllLabel: '',
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => _emptyTile('Set your clinic location first.'),
          data: (list) {
            final preview = list.take(3).toList();
            if (preview.isEmpty) {
              return _emptyTile('No clinics or hospitals indexed near you yet.');
            }
            return Column(children: preview.map(_DoctorMiniCard.new).toList());
          },
        ),
      ],
    );
  }
}

// ── Preview: Nearby Circles ───────────────────────────────────────────────────

class _CirclesPreview extends ConsumerWidget {
  const _CirclesPreview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nearbyCirclesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PreviewHeader(title: 'Circles Near You', seeAllPath: '/circles'),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => _emptyTile('Could not load circles.'),
          data: (list) {
            final preview = list.take(3).toList();
            if (preview.isEmpty) {
              return _emptyTile('No circles in your area yet.');
            }
            return Column(
              children: preview.map((c) => InkWell(
                onTap: () => context.push('/circles/${c['id']}'),
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
                      const Icon(Icons.people_outline,
                          color: MedUnityColors.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c['name'] as String? ?? 'Circle',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              '${c['member_count'] ?? 0} members · ${c['city'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: MedUnityColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                    ],
                  ),
                ),
              )).toList(),
            );
          },
        ),
      ],
    );
  }
}

// ── Preview: Find-Associate posts (associate doctor's primary feed) ───────────

class _FindAssociatePostsPreview extends ConsumerWidget {
  const _FindAssociatePostsPreview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dio = ref.watch(dioProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PreviewHeader(
            title: 'Clinics Looking for Associates',
            seeAllPath: '/support'),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: () async {
            try {
              final resp = await dio.get(
                '/support/requests/',
                queryParameters: {'type': 'find_associate'},
              );
              return (resp.data as List).cast<Map<String, dynamic>>();
            } catch (_) {
              return const <Map<String, dynamic>>[];
            }
          }(),
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            final list = snap.data ?? const [];
            final preview = list.take(3).toList();
            if (preview.isEmpty) {
              return _emptyTile('No clinics hiring associates right now.');
            }
            return Column(
              children: preview.map((r) => InkWell(
                onTap: () => context.push('/support'),
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
                          color: const Color(0xFF8E24AA).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.medical_services_outlined,
                            color: Color(0xFF8E24AA), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['title'] as String? ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              '${r['requester_name']} · ${r['city'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: MedUnityColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                    ],
                  ),
                ),
              )).toList(),
            );
          },
        ),
      ],
    );
  }
}

// ── Shared mini-card for any "doctor" entity (consultant / associate / clinic) ─

class _DoctorMiniCard extends StatelessWidget {
  final Map<String, dynamic> doctor;
  const _DoctorMiniCard(this.doctor);
  @override
  Widget build(BuildContext context) {
    final id = doctor['id'] as int?;
    final name = (doctor['full_name'] as String?) ?? 'Doctor';
    final spec = (doctor['specialization_display'] as String?) ??
        (doctor['specialization'] as String?) ??
        '';
    final dist = (doctor['distance_label'] as String?) ?? '';
    final primary = (doctor['primary_role'] as String?) ?? '';
    final primaryLabel = (doctor['primary_role_display'] as String?) ?? '';
    return InkWell(
      onTap: () => id == null ? null : context.push('/associates/$id'),
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
            CircleAvatar(
              radius: 18,
              backgroundColor: MedUnityColors.primary.withOpacity(0.12),
              child: const Icon(Icons.person, color: MedUnityColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      if (primary.isNotEmpty)
                        PrimaryRolePill(role: primary, label: primaryLabel),
                    ],
                  ),
                  Text(
                    [if (spec.isNotEmpty) spec, if (dist.isNotEmpty) dist].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: MedUnityColors.textSecondary),
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

