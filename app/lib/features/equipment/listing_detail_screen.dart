import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'equipment_provider.dart';

class ListingDetailScreen extends ConsumerWidget {
  final int listingId;
  const ListingDetailScreen({super.key, required this.listingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(listingDetailProvider(listingId));
    return Scaffold(
      appBar: AppBar(title: const Text('Listing')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load listing.')),
        data: (listing) => _ListingBody(listing: listing, listingId: listingId, ref: ref),
      ),
    );
  }
}

class _ListingBody extends StatelessWidget {
  final Map<String, dynamic> listing;
  final int listingId;
  final WidgetRef ref;
  const _ListingBody({required this.listing, required this.listingId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isMine = listing['is_mine'] as bool? ?? false;
    final status = listing['status'] as String? ?? 'active';
    final inquiries = (listing['inquiries'] as List? ?? []).cast<Map<String, dynamic>>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          if (listing['image'] != null)
            Image.network(listing['image'] as String,
                width: double.infinity, height: 220, fit: BoxFit.cover)
          else
            Container(
              width: double.infinity, height: 180,
              color: Colors.grey[100],
              child: const Center(
                child: Icon(Icons.medical_services_outlined, size: 64, color: MedUnityColors.textSecondary),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(listing['title'] as String,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    Text('₹${listing['price']}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold, color: MedUnityColors.primary)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(listing['category_display'] as String? ?? '',
                        style: const TextStyle(color: MedUnityColors.textSecondary, fontSize: 13)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(listing['condition_display'] as String? ?? '',
                          style: const TextStyle(fontSize: 12, color: Colors.orange)),
                    ),
                    if (status == 'sold') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('SOLD', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: MedUnityColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('${listing['seller_name']} — ${listing['seller_specialization']}',
                        style: const TextStyle(fontSize: 13, color: MedUnityColors.textSecondary)),
                  ],
                ),

                if ((listing['description'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(listing['description'] as String),
                ],

                const SizedBox(height: 20),

                // Buyer: inquire button
                if (!isMine && status == 'active')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showInquiry(context, ref),
                      icon: const Icon(Icons.message_outlined),
                      label: const Text('Contact Seller',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MedUnityColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                // Seller: mark sold / remove
                if (isMine) ...[
                  if (status == 'active') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _patchStatus(context, ref, 'sold'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: const Text('Mark as Sold'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _delete(context, ref),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Remove Listing'),
                    ),
                  ),

                  // Inquiries
                  if (inquiries.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Inquiries (${inquiries.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    ...inquiries.map((inq) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${inq['inquirer_name']} — ${inq['inquirer_specialization']}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(inq['message'] as String? ?? ''),
                        ],
                      ),
                    )),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInquiry(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InquirySheet(listingId: listingId, ref: ref),
    );
  }

  Future<void> _patchStatus(BuildContext context, WidgetRef ref, String status) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.patch('/equipment/listings/$listingId/', data: {'status': status});
      ref.invalidate(listingDetailProvider(listingId));
      ref.invalidate(myListingsProvider);
    } catch (_) {}
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/equipment/listings/$listingId/');
      ref.invalidate(myListingsProvider);
      if (context.mounted) Navigator.pop(context);
    } catch (_) {}
  }
}

// ── Inquiry sheet ─────────────────────────────────────────────────────────────

class _InquirySheet extends StatefulWidget {
  final int listingId;
  final WidgetRef ref;
  const _InquirySheet({required this.listingId, required this.ref});

  @override
  State<_InquirySheet> createState() => _InquirySheetState();
}

class _InquirySheetState extends State<_InquirySheet> {
  final _msgCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _msgCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() => _loading = true);
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/equipment/listings/${widget.listingId}/inquire/', data: {'message': msg});
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inquiry sent to the seller!'), backgroundColor: Colors.green),
        );
      }
    } catch (_) {
      setState(() => _loading = false);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Contact Seller', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _msgCtrl,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Write your inquiry message…',
                border: OutlineInputBorder(),
              ),
            ),
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
                    : const Text('Send Inquiry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
