import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import 'requests_tab.dart';
import 'leaderboard_screen.dart';

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Practice Support'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.handshake_outlined), text: 'Requests'),
              Tab(icon: Icon(Icons.leaderboard), text: 'Leaderboard'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [RequestsTab(), LeaderboardScreen()],
        ),
      ),
    );
  }
}
