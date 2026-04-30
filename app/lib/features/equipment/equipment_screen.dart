import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import 'equipment_provider.dart';
import 'marketplace_tab.dart';
import 'pools_tab.dart';

class EquipmentScreen extends ConsumerWidget {
  const EquipmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Equipment Hub'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.group_work_outlined), text: 'Co-Purchase'),
              Tab(icon: Icon(Icons.storefront_outlined), text: 'Marketplace'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [PoolsTab(), MarketplaceTab()],
        ),
      ),
    );
  }
}
