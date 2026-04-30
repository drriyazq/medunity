import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import 'equipment_provider.dart';

class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myListingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Listings')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load your listings.')),
        data: (listings) {
          if (listings.isEmpty) {
            return const Center(
              child: Text('You have no active listings.',
                  style: TextStyle(color: MedUnityColors.textSecondary)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: listings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final l = listings[i];
              return InkWell(
                onTap: () => context.push('/equipment/listings/${l['id']}'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l['title'] as String,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('₹${l['price']} · ${l['condition_display']}',
                                style: const TextStyle(
                                    fontSize: 13, color: MedUnityColors.textSecondary)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: l['status'] == 'sold'
                              ? Colors.grey.withOpacity(0.1)
                              : Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          (l['status'] as String).toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              color: l['status'] == 'sold' ? Colors.grey : Colors.green),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
