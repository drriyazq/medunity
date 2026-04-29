import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'features/consent/consent_screen.dart';
import 'features/home/home_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/consent',
    routes: [
      GoRoute(path: '/consent', builder: (_, __) => const ConsentScreen()),
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
  Widget build(BuildContext context) => Center(child: Text('$name — Coming soon'));
}
