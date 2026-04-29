import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/pending_verification_screen.dart';
import 'features/auth/phone_signin_screen.dart';
import 'features/auth/rejection_screen.dart';
import 'features/consent/consent_screen.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/profile_setup_screen.dart';
import 'state/auth_provider.dart';
import 'theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authListenable = ref.watch(_authListenableProvider);

  return GoRouter(
    initialLocation: '/consent',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.uri.path;

      // Always allow consent
      if (loc == '/consent') return null;

      switch (auth.status) {
        case AuthStatus.loading:
          return null;

        case AuthStatus.loggedOut:
          if (loc == '/signin') return null;
          return '/signin';

        case AuthStatus.tokenIssued:
          // Has JWT but no profile submitted yet
          if (loc == '/onboarding/profile') return null;
          return '/onboarding/profile';

        case AuthStatus.pendingVerification:
          if (loc == '/pending-verification') return null;
          return '/pending-verification';

        case AuthStatus.rejected:
          if (loc == '/rejected' || loc == '/onboarding/profile') return null;
          return '/rejected';

        case AuthStatus.verified:
          // If on auth screens, redirect to home
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
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const _PlaceholderScreen('Home')),
          GoRoute(path: '/circles', builder: (_, __) => const _PlaceholderScreen('Circles')),
          GoRoute(path: '/consultants', builder: (_, __) => const _PlaceholderScreen('Consultants')),
          GoRoute(path: '/marketplace', builder: (_, __) => const _PlaceholderScreen('Marketplace')),
          GoRoute(path: '/profile', builder: (_, __) => const _PlaceholderScreen('Profile')),
        ],
      ),
    ],
  );
});

// Makes GoRouter listen to authProvider changes for redirect
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
