import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';

class HomeShell extends StatelessWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  static const _tabs = [
    (icon: Icons.home_outlined, label: 'Home', path: '/home'),
    (icon: Icons.people_outline, label: 'Circles', path: '/circles'),
    (icon: Icons.medical_services_outlined, label: 'Consult', path: '/consultants'),
    (icon: Icons.storefront_outlined, label: 'Market', path: '/marketplace'),
    (icon: Icons.person_outline, label: 'Profile', path: '/profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _tabs.indexWhere((t) => location.startsWith(t.path));

    return Scaffold(
      body: Stack(
        children: [
          child,
          // SOS FAB — persistent overlay (Phase 2: wired to SOS flow)
          Positioned(
            right: 16,
            bottom: 80,
            child: FloatingActionButton(
              backgroundColor: MedUnityColors.sos,
              foregroundColor: Colors.white,
              onPressed: () {
                // Phase 2: navigate to SOS countdown
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('SOS — coming in Phase 2')),
                );
              },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sos, size: 20),
                  Text('SOS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex < 0 ? 0 : currentIndex,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: _tabs
            .map((t) => NavigationDestination(icon: Icon(t.icon), label: t.label))
            .toList(),
      ),
    );
  }
}
