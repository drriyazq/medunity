import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../messaging/messaging_provider.dart';
import '../sos/category_sheet.dart';

class HomeShell extends ConsumerWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  static const _tabs = [
    (icon: Icons.home_outlined, label: 'Home', path: '/home'),
    (icon: Icons.chat_bubble_outline, label: 'Messages', path: '/messages'),
    (icon: Icons.medical_services_outlined, label: 'Consult', path: '/consultants'),
    (icon: Icons.storefront_outlined, label: 'Market', path: '/marketplace'),
    (icon: Icons.person_outline, label: 'Profile', path: '/profile'),
  ];

  Future<void> _onSosTap(BuildContext context) async {
    final result = await showSosCategorySheet(context);
    if (result == null || !context.mounted) return;

    final categoryLabels = {
      'medical_emergency': 'Medical Emergency',
      'legal_issue': 'Legal Issue',
      'clinic_threat': 'Clinic Under Threat',
      'urgent_clinical': 'Urgent Clinical Assistance',
    };

    context.push(
      '/sos/select-recipients',
      extra: {
        'category': result.category,
        'categoryDisplay': categoryLabels[result.category] ?? result.category,
        'position': result.position,
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _tabs.indexWhere((t) => location.startsWith(t.path));
    final unread = ref.watch(messagesUnreadCountProvider).valueOrNull ?? 0;

    return Scaffold(
      body: Stack(
        children: [
          child,
          Positioned(
            right: 16,
            bottom: 80,
            child: FloatingActionButton(
              backgroundColor: MedUnityColors.sos,
              foregroundColor: Colors.white,
              onPressed: () => _onSosTap(context),
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
        destinations: _tabs.map((t) {
          final isMessages = t.path == '/messages';
          final iconWidget = (isMessages && unread > 0)
              ? Badge.count(count: unread, child: Icon(t.icon))
              : Icon(t.icon);
          return NavigationDestination(icon: iconWidget, label: t.label);
        }).toList(),
      ),
    );
  }
}
