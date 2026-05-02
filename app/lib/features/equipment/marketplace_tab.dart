import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'equipment_provider.dart';

const _mktCategories = [
  ('', 'All'),
  ('dental_chairs', 'Chairs'),
  ('imaging', 'Imaging'),
  ('surgical_instruments', 'Instruments'),
  ('diagnostic', 'Diagnostic'),
  ('sterilization', 'Sterilization'),
  ('lab_equipment', 'Lab'),
  ('consumables', 'Consumables'),
  ('other', 'Other'),
];

const _conditionColors = {
  'new': Colors.green,
  'like_new': Colors.lightGreen,
  'good': Colors.orange,
  'fair': Colors.red,
};

class MarketplaceTab extends ConsumerStatefulWidget {
  const MarketplaceTab({super.key});

  @override
  ConsumerState<MarketplaceTab> createState() => _MarketplaceTabState();
}

class _MarketplaceTabState extends ConsumerState<MarketplaceTab> {
  String _category = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(listingsProvider);

    return Column(
      children: [
        // Category filter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: _mktCategories.map((c) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(c.$2, style: const TextStyle(fontSize: 12)),
                selected: _category == c.$1,
                onSelected: (_) {
                  setState(() => _category = c.$1);
                  ref.read(listingsProvider.notifier).load(refresh: true, category: c.$1);
                },
              ),
            )).toList(),
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateListing(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Sell Equipment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MedUnityColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => context.push('/equipment/listings/mine'),
                icon: const Icon(Icons.list, size: 16),
                label: const Text('My Listings'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Grid
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('Could not load listings.')),
            data: (listings) {
              if (listings.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.storefront_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text('No equipment listed yet.',
                          style: TextStyle(color: MedUnityColors.textSecondary)),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref.read(listingsProvider.notifier).load(refresh: true, category: _category),
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.66,
                  ),
                  itemCount: listings.length + (ref.read(listingsProvider.notifier).hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == listings.length) {
                      return Center(
                        child: TextButton(
                          onPressed: () => ref.read(listingsProvider.notifier).loadMore(_category),
                          child: const Text('Load more'),
                        ),
                      );
                    }
                    return _ListingCard(listing: listings[i]);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCreateListing(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateListingSheet(ref: ref, category: _category),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final Map<String, dynamic> listing;
  const _ListingCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    final condition = listing['condition'] as String? ?? 'good';
    final condColor = _conditionColors[condition] ?? Colors.grey;

    return InkWell(
      onTap: () => context.push('/equipment/listings/${listing['id']}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image or placeholder
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: listing['image'] != null
                    ? Image.network(listing['image'] as String, fit: BoxFit.cover,
                        width: double.infinity)
                    : Container(
                        color: Colors.grey[100],
                        child: const Center(
                          child: Icon(Icons.medical_services_outlined,
                              size: 40, color: MedUnityColors.textSecondary),
                        ),
                      ),
              ),
            ),
            // Info
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(listing['title'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text('₹${listing['price']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: MedUnityColors.primary,
                                  fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: condColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(listing['condition_display'] as String? ?? '',
                              style: TextStyle(fontSize: 10, color: condColor)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create listing sheet ──────────────────────────────────────────────────────

class _CreateListingSheet extends StatefulWidget {
  final WidgetRef ref;
  final String category;
  const _CreateListingSheet({required this.ref, required this.category});

  @override
  State<_CreateListingSheet> createState() => _CreateListingSheetState();
}

class _CreateListingSheetState extends State<_CreateListingSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String _category = 'other';
  String _condition = 'good';
  bool _loading = false;
  String? _error;

  static const _conditions = [
    ('new', 'Brand New'), ('like_new', 'Like New'), ('good', 'Good'), ('fair', 'Fair'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.category.isNotEmpty) _category = widget.category;
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose(); _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final price = _priceCtrl.text.trim();
    if (title.isEmpty || price.isEmpty) {
      setState(() => _error = 'Title and price are required.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final container = ProviderScope.containerOf(context, listen: false);
    final dio = container.read(dioProvider);
    try {
      final resp = await dio.post('/equipment/listings/',
          data: FormData.fromMap({
            'title': title,
            'description': _descCtrl.text.trim(),
            'category': _category,
            'price': price,
            'condition': _condition,
          }));
      widget.ref.read(listingsProvider.notifier).prependListing(
          Map<String, dynamic>.from(resp.data as Map));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() { _loading = false; _error = 'Could not create listing.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('List Equipment for Sale',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title *', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _descCtrl, maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: _mktCategories.skip(1).map((c) =>
                    DropdownMenuItem(value: c.$1, child: Text(c.$2))).toList(),
                onChanged: (v) => setState(() => _category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _condition,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Condition',
                  border: OutlineInputBorder(),
                ),
                items: _conditions.map((c) =>
                    DropdownMenuItem(value: c.$1, child: Text(c.$2))).toList(),
                onChanged: (v) => setState(() => _condition = v ?? 'good'),
              ),
              const SizedBox(height: 12),
              TextField(controller: _priceCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price ₹ *', border: OutlineInputBorder())),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: MedUnityColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('List for Sale', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
