import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'vendors_provider.dart';

const _vendorCategories = [
  ('', 'All'),
  ('dental_lab', 'Dental Labs'),
  ('material_dealer', 'Materials'),
  ('equipment_technician', 'Technicians'),
  ('pharmacy', 'Pharmacy'),
  ('imaging_centre', 'Imaging'),
  ('other', 'Other'),
];

const _sortOptions = [
  ('rating', 'Top Rated'),
  ('quality', 'Best Quality'),
  ('delivery', 'Fastest Delivery'),
  ('newest', 'Newest'),
];

class VendorsScreen extends ConsumerStatefulWidget {
  const VendorsScreen({super.key});

  @override
  ConsumerState<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends ConsumerState<VendorsScreen> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String _category = '';
  String _sort = 'rating';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(vendorSearchProvider);
    final vendorsAsync = ref.watch(vendorsProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search vendors…',
                  border: InputBorder.none,
                ),
                onChanged: (q) => ref
                    .read(vendorSearchProvider.notifier)
                    .search(q),
              )
            : const Text('Vendor Directory'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _searchCtrl.clear();
                ref.read(vendorSearchProvider.notifier).clear();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddVendor(context),
          ),
        ],
      ),
      body: _searching
          ? _SearchResults(async: searchResults)
          : Column(
              children: [
                // Category chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: _vendorCategories.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(c.$2, style: const TextStyle(fontSize: 12)),
                        selected: _category == c.$1,
                        onSelected: (_) {
                          setState(() => _category = c.$1);
                          ref.read(vendorsProvider.notifier)
                              .load(refresh: true, category: c.$1, sort: _sort);
                        },
                      ),
                    )).toList(),
                  ),
                ),

                // Sort row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.sort, size: 16, color: MedUnityColors.textSecondary),
                      const SizedBox(width: 8),
                      const Text('Sort:', style: TextStyle(fontSize: 13, color: MedUnityColors.textSecondary)),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _sort,
                        underline: const SizedBox.shrink(),
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                        items: _sortOptions.map((o) =>
                            DropdownMenuItem(value: o.$1, child: Text(o.$2))).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _sort = v);
                          ref.read(vendorsProvider.notifier)
                              .load(refresh: true, category: _category, sort: v);
                        },
                      ),
                    ],
                  ),
                ),

                // List
                Expanded(
                  child: vendorsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const Center(child: Text('Could not load vendors.')),
                    data: (vendors) {
                      if (vendors.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.store_mall_directory_outlined,
                                  size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              const Text('No vendors found.',
                                  style: TextStyle(color: MedUnityColors.textSecondary)),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showAddVendor(context),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add the first one'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: MedUnityColors.primary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: () => ref.read(vendorsProvider.notifier)
                            .load(refresh: true, category: _category, sort: _sort),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: vendors.length +
                              (ref.read(vendorsProvider.notifier).hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            if (i == vendors.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: () => ref
                                      .read(vendorsProvider.notifier)
                                      .loadMore(category: _category, sort: _sort),
                                  child: const Text('Load more'),
                                ),
                              );
                            }
                            return _VendorCard(vendor: vendors[i]);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _showAddVendor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddVendorSheet(ref: ref),
    );
  }
}

// ── Vendor card ───────────────────────────────────────────────────────────────

class _VendorCard extends StatelessWidget {
  final Map<String, dynamic> vendor;
  const _VendorCard({required this.vendor});

  @override
  Widget build(BuildContext context) {
    final avgRating = vendor['avg_rating'] as double?;
    final reviews = vendor['review_count'] as int? ?? 0;
    final verified = vendor['is_verified'] as bool? ?? false;

    return InkWell(
      onTap: () => context.push('/vendors/${vendor['id']}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: MedUnityColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.store_outlined,
                  color: MedUnityColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(vendor['name'] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      if (verified)
                        const Icon(Icons.verified, color: Colors.blue, size: 16),
                    ],
                  ),
                  Text(vendor['category_display'] as String? ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: MedUnityColors.primary)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: MedUnityColors.textSecondary),
                      const SizedBox(width: 2),
                      Text(vendor['city'] as String? ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: MedUnityColors.textSecondary)),
                      const Spacer(),
                      if (avgRating != null) ...[
                        const Icon(Icons.star, size: 13, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text('${avgRating.toStringAsFixed(1)} ($reviews)',
                            style: const TextStyle(fontSize: 12)),
                      ] else
                        const Text('No reviews yet',
                            style: TextStyle(
                                fontSize: 12, color: MedUnityColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

// ── Search results ────────────────────────────────────────────────────────────

class _SearchResults extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> async;
  const _SearchResults({required this.async});

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Search failed.')),
      data: (results) {
        if (results.isEmpty) {
          return const Center(
            child: Text('No vendors found.',
                style: TextStyle(color: MedUnityColors.textSecondary)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _VendorCard(vendor: results[i]),
        );
      },
    );
  }
}

// ── Add vendor sheet ──────────────────────────────────────────────────────────

class _AddVendorSheet extends StatefulWidget {
  final WidgetRef ref;
  const _AddVendorSheet({required this.ref});

  @override
  State<_AddVendorSheet> createState() => _AddVendorSheetState();
}

class _AddVendorSheetState extends State<_AddVendorSheet> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'dental_lab';
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _duplicate;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _addressCtrl, _cityCtrl, _phoneCtrl, _descCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    if (name.isEmpty || city.isEmpty) {
      setState(() => _error = 'Name and city are required.');
      return;
    }
    setState(() { _loading = true; _error = null; _duplicate = null; });
    final container = ProviderScope.containerOf(context, listen: false);
    final dio = container.read(dioProvider);
    try {
      final resp = await dio.post('/vendors/', data: {
        'name': name,
        'category': _category,
        'description': _descCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'city': city,
        'phone': _phoneCtrl.text.trim(),
      });
      widget.ref.read(vendorsProvider.notifier)
          .prependVendor(Map<String, dynamic>.from(resp.data as Map));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (e.toString().contains('409')) {
        // Duplicate found — show existing
        setState(() {
          _loading = false;
          _error = 'A similar vendor already exists:';
          // Duplicate data is in the error body but we can't easily extract it from Dio exception.
          // Show generic message.
          _error = 'A similar vendor already exists in this city. Please check the directory first.';
        });
      } else {
        setState(() { _loading = false; _error = 'Could not add vendor.'; });
      }
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
              const Text('Add a Vendor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Help your colleagues find trusted vendors.',
                  style: TextStyle(fontSize: 13, color: MedUnityColors.textSecondary)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: _vendorCategories.skip(1).map((c) =>
                    DropdownMenuItem(value: c.$1, child: Text(c.$2))).toList(),
                onChanged: (v) => setState(() => _category = v ?? 'dental_lab'),
              ),
              const SizedBox(height: 12),
              TextField(controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Vendor name *', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(controller: _cityCtrl,
                        decoration: const InputDecoration(labelText: 'City *', border: OutlineInputBorder())),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _descCtrl, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder())),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MedUnityColors.primary, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Submit Vendor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
