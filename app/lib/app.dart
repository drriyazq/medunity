import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'data/local/hive_setup.dart';
import 'features/auth/pending_verification_screen.dart';
import 'features/auth/phone_signin_screen.dart';
import 'features/auth/rejection_screen.dart';
import 'features/circles/circle_detail_screen.dart';
import 'features/circles/circles_screen.dart';
import 'features/circles/post_detail_screen.dart';
import 'features/consultants/consultant_profile_screen.dart';
import 'features/consultants/consultants_screen.dart';
import 'features/equipment/equipment_screen.dart';
import 'features/equipment/listing_detail_screen.dart';
import 'features/equipment/my_listings_screen.dart';
import 'features/equipment/pool_detail_screen.dart';
import 'features/home_screen/home_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/support/leaderboard_screen.dart';
import 'features/support/support_screen.dart';
import 'features/vendors/vendor_detail_screen.dart';
import 'features/vendors/vendors_screen.dart';
import 'features/consent/consent_screen.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/profile_setup_screen.dart';
import 'features/sos/incoming_sos_screen.dart';
import 'features/sos/select_recipients_screen.dart';
import 'features/sos/sos_countdown_screen.dart';
import 'features/sos/sos_dashboard_screen.dart';
import 'features/sos/sos_provider.dart';
import 'features/sos/sos_status_screen.dart';
import 'services/push_service.dart';
import 'state/auth_provider.dart';
import 'theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authListenable = ref.watch(_authListenableProvider);

  final consentAccepted = HiveSetup.sessionBox.get('consent_accepted') == true;

  return GoRouter(
    initialLocation: consentAccepted ? '/signin' : '/consent',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.uri.path;
      final accepted = HiveSetup.sessionBox.get('consent_accepted') == true;

      if (loc == '/consent') {
        if (!accepted) return null;
        // Already accepted — fall through to auth-based redirect below
      }

      // SOS screens require verified — redirect to home which will redirect if needed
      if (loc.startsWith('/sos/')) {
        if (auth.status != AuthStatus.verified) return '/signin';
        return null;
      }

      switch (auth.status) {
        case AuthStatus.loading:
          return null;

        case AuthStatus.loggedOut:
          if (loc == '/signin') return null;
          return '/signin';

        case AuthStatus.tokenIssued:
          if (loc == '/onboarding/profile') return null;
          return '/onboarding/profile';

        case AuthStatus.pendingVerification:
          if (loc == '/pending-verification') return null;
          return '/pending-verification';

        case AuthStatus.rejected:
          if (loc == '/rejected' || loc == '/onboarding/profile') return null;
          return '/rejected';

        case AuthStatus.verified:
          if (['/signin', '/onboarding/profile', '/pending-verification', '/rejected']
              .contains(loc)) {
            return '/home';
          }
          return null;

        default:
          return null;
      }
    },
    routes: [
      GoRoute(path: '/consent', builder: (_, __) => const ConsentScreen()),
      GoRoute(path: '/signin', builder: (_, __) => const PhoneSignInScreen()),
      GoRoute(path: '/onboarding/profile', builder: (_, __) => const ProfileSetupScreen()),
      GoRoute(path: '/pending-verification', builder: (_, __) => const PendingVerificationScreen()),
      GoRoute(
        path: '/rejected',
        builder: (context, state) {
          final reason = ref.read(authProvider).rejectionReason;
          return RejectionScreen(reason: reason);
        },
      ),

      // ── Vendor routes (outside shell) ───────────────────────────────────────
      GoRoute(path: '/vendors', builder: (_, __) => const VendorsScreen()),
      GoRoute(
        path: '/vendors/:id',
        builder: (_, state) =>
            VendorDetailScreen(vendorId: int.parse(state.pathParameters['id']!)),
      ),

      // ── Support routes (outside shell) ──────────────────────────────────────
      GoRoute(path: '/support', builder: (_, __) => const SupportScreen()),
      GoRoute(path: '/support/leaderboard', builder: (_, __) => const LeaderboardScreen()),
      GoRoute(path: '/support/requests/:id', builder: (_, __) => const SupportScreen()),

      // ── Equipment routes (outside shell) ────────────────────────────────────
      GoRoute(
        path: '/equipment/pools/:id',
        builder: (_, state) =>
            PoolDetailScreen(poolId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/equipment/listings/mine',
        builder: (_, __) => const MyListingsScreen(),
      ),
      GoRoute(
        path: '/equipment/listings/:id',
        builder: (_, state) =>
            ListingDetailScreen(listingId: int.parse(state.pathParameters['id']!)),
      ),

      // ── Consultant routes (outside shell) ───────────────────────────────────
      GoRoute(
        path: '/consultants/profile/:id',
        builder: (_, state) =>
            ConsultantProfileScreen(profId: int.parse(state.pathParameters['id']!)),
      ),

      // ── Circles routes (outside shell) ─────────────────────────────────────
      GoRoute(
        path: '/circles/:id',
        builder: (_, state) =>
            CircleDetailScreen(circleId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/circles/:id/posts/:postId',
        builder: (_, state) => PostDetailScreen(
          circleId: int.parse(state.pathParameters['id']!),
          postId: int.parse(state.pathParameters['postId']!),
        ),
      ),

      // ── SOS routes (outside shell — full-screen) ────────────────────────────
      GoRoute(
        path: '/sos/select-recipients',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return SelectRecipientsScreen(
            category: extra['category'] as String,
            categoryDisplay: extra['categoryDisplay'] as String,
            position: extra['position'] as Position,
          );
        },
      ),
      GoRoute(
        path: '/sos/countdown',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return SosCountdownScreen(
            category: extra['category'] as String,
            categoryDisplay: extra['categoryDisplay'] as String,
            position: extra['position'] as Position,
            recipientIds: (extra['recipientIds'] as List?)?.cast<int>(),
          );
        },
      ),
      GoRoute(
        path: '/sos/status/:alertId',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final alertId = int.parse(state.pathParameters['alertId']!);
          return SosStatusScreen(
            alertId: alertId,
            recipientCount: extra['recipientCount'] as int? ?? 0,
            radiusKm: (extra['radiusKm'] as num?)?.toDouble() ?? 1.0,
            category: extra['category'] as String? ?? '',
            categoryDisplay: extra['categoryDisplay'] as String? ?? 'SOS',
          );
        },
      ),
      GoRoute(
        path: '/sos/incoming/:alertId',
        builder: (context, state) {
          final alertId = int.parse(state.pathParameters['alertId']!);
          return IncomingSosScreen(alertId: alertId);
        },
      ),
      GoRoute(
        path: '/sos/dashboard',
        builder: (_, __) => const SosDashboardScreen(),
      ),

      // ── Home shell ──────────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/circles', builder: (_, __) => const CirclesScreen()),
          GoRoute(path: '/consultants', builder: (_, __) => const ConsultantsScreen()),
          GoRoute(path: '/marketplace', builder: (_, __) => const EquipmentScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
});

final _authListenableProvider = Provider((ref) {
  return _AuthListenable(ref);
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}

class MedUnityApp extends ConsumerWidget {
  const MedUnityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    setPushNavigate((path) => router.push(path));
    setPushOnSosResponse((alertId) {
      // Force refresh of an open status screen + dashboard.
      ref.invalidate(sosStatusProvider(alertId));
      ref.invalidate(myAlertsProvider);
    });
    setPushOnSosAlert((alertId) {
      // New incoming SOS — refresh the recipient's received list.
      ref.invalidate(receivedAlertsProvider);
    });
    return MaterialApp.router(
      title: 'MedUnity',
      theme: MedUnityTheme.light(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  final String name;
  const _PlaceholderScreen(this.name);
  @override
  Widget build(BuildContext context) => Center(
    child: Text('$name — Coming soon', style: const TextStyle(color: MedUnityColors.textSecondary)),
  );
}
