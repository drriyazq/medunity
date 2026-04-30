import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'vendors_provider.dart';

class VendorDetailScreen extends ConsumerWidget {
  final int vendorId;
  const VendorDetailScreen({super.key, required this.vendorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(vendorDetailProvider(vendorId));
    return Scaffold(
      appBar: AppBar(title: const Text('Vendor')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load vendor.')),
        data: (v) => _VendorBody(vendor: v, vendorId: vendorId, ref: ref),
      ),
    );
  }
}

class _VendorBody extends StatelessWidget {
  final Map<String, dynamic> vendor;
  final int vendorId;
  final WidgetRef ref;
  const _VendorBody({required this.vendor, required this.vendorId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final reviews = (vendor['reviews'] as List? ?? []).cast<Map<String, dynamic>>();
    final verified = vendor['is_verified'] as bool? ?? false;
    final myReview = vendor['my_review'];
    final iFlagged = vendor['i_flagged'] as bool? ?? false;
    final avgRating = vendor['avg_rating'] as double?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: MedUnityColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.store_outlined, color: MedUnityColors.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(vendor['name'] as String,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ),
                        if (verified)
                          const Tooltip(
                            message: 'Verified vendor',
                            child: Icon(Icons.verified, color: Colors.blue, size: 18),
                          ),
                      ],
                    ),
                    Text(vendor['category_display'] as String? ?? '',
                        style: const TextStyle(color: MedUnityColors.primary, fontSize: 13)),
                    if ((vendor['city'] as String? ?? '').isNotEmpty)
                      Text(
                        '${vendor['city']}${(vendor['state'] as String? ?? '').isNotEmpty ? ', ${vendor['state']}' : ''}',
                        style: const TextStyle(fontSize: 13, color: MedUnityColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Ratings row
          if (avgRating != null)
            Row(
              children: [
                _RatingChip(label: 'Overall', value: avgRating),
                if (vendor['avg_quality'] != null) ...[
                  const SizedBox(width: 8),
                  _RatingChip(label: 'Quality', value: vendor['avg_quality'] as double,
                      color: Colors.teal),
                ],
                if (vendor['avg_delivery'] != null) ...[
                  const SizedBox(width: 8),
                  _RatingChip(label: 'Delivery', value: vendor['avg_delivery'] as double,
                      color: Colors.orange),
                ],
              ],
            ),

          if ((vendor['description'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(vendor['description'] as String),
          ],

          // Contact info
          if ((vendor['phone'] as String? ?? '').isNotEmpty ||
              (vendor['address'] as String? ?? '').isNotEmpty ||
              (vendor['website'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if ((vendor['address'] as String? ?? '').isNotEmpty)
                    _InfoRow(icon: Icons.location_on_outlined, text: vendor['address'] as String),
                  if ((vendor['phone'] as String? ?? '').isNotEmpty)
                    _InfoRow(
                      icon: Icons.phone_outlined,
                      text: vendor['phone'] as String,
                      onTap: () => launchUrl(Uri.parse('tel:${vendor['phone']}')),
                    ),
                  if ((vendor['website'] as String? ?? '').isNotEmpty)
                    _InfoRow(
                      icon: Icons.language,
                      text: vendor['website'] as String,
                      onTap: () => launchUrl(Uri.parse(vendor['website'] as String)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: myReview == null ? () => _showReview(context) : null,
                  icon: const Icon(Icons.star_outline),
                  label: Text(myReview == null ? 'Write Review' : 'Reviewed'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MedUnityColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[200],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: iFlagged ? null : () => _showFlag(context),
                icon: Icon(Icons.flag_outlined,
                    color: iFlagged ? Colors.grey : Colors.red),
                label: Text(iFlagged ? 'Reported' : 'Report',
                    style: TextStyle(color: iFlagged ? Colors.grey : Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: iFlagged ? Colors.grey : Colors.red),
                ),
              ),
            ],
          ),

          // Reviews
          const SizedBox(height: 24),
          Text('Reviews (${vendor['review_count'] ?? 0})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          if (reviews.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
              child: const Center(
                child: Text('No reviews yet. Be the first!',
                    style: TextStyle(color: MedUnityColors.textSecondary)),
              ),
            )
          else
            ...reviews.map((r) => _ReviewCard(review: r)),
        ],
      ),
    );
  }

  void _showReview(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(vendorId: vendorId, ref: ref),
    );
  }

  void _showFlag(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FlagSheet(vendorId: vendorId, ref: ref),
    );
  }
}

class _RatingChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _RatingChip({required this.label, required this.value, this.color = Colors.amber});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, color: color, size: 14),
          const SizedBox(width: 4),
          Text('${value.toStringAsFixed(1)} $label',
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  const _InfoRow({required this.icon, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 16, color: MedUnityColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13,
                      color: onTap != null ? MedUnityColors.primary : Colors.black87,
                      decoration: onTap != null ? TextDecoration.underline : null)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final rating = review['rating'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(children: List.generate(5, (i) =>
                  Icon(i < rating ? Icons.star : Icons.star_border,
                      size: 14, color: Colors.amber))),
              const SizedBox(width: 8),
              Expanded(child: Text(review['reviewer_name'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
              if (review['quality_rating'] != null)
                Text('Q:${review['quality_rating']}★',
                    style: const TextStyle(fontSize: 11, color: Colors.teal)),
              if (review['delivery_rating'] != null) ...[
                const SizedBox(width: 6),
                Text('D:${review['delivery_rating']}★',
                    style: const TextStyle(fontSize: 11, color: Colors.orange)),
              ],
            ],
          ),
          if ((review['comment'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(review['comment'] as String),
          ],
        ],
      ),
    );
  }
}

// ── Review sheet ──────────────────────────────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  final int vendorId;
  final WidgetRef ref;
  const _ReviewSheet({required this.vendorId, required this.ref});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 0, _quality = 0, _delivery = 0;
  final _commentCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  Widget _starRow(String label, int value, void Function(int) onSet) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13))),
          ...List.generate(5, (i) => GestureDetector(
            onTap: () => onSet(i + 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(i < value ? Icons.star : Icons.star_border,
                  size: 28, color: Colors.amber),
            ),
          )),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select an overall rating.')));
      return;
    }
    setState(() => _loading = true);
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/vendors/${widget.vendorId}/review/', data: {
        'rating': _rating,
        if (_quality > 0) 'quality_rating': _quality,
        if (_delivery > 0) 'delivery_rating': _delivery,
        'comment': _commentCtrl.text.trim(),
      });
      widget.ref.invalidate(vendorDetailProvider(widget.vendorId));
      widget.ref.invalidate(vendorsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review submitted!'), backgroundColor: Colors.green),
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
            const Text('Write a Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _starRow('Overall *', _rating, (v) => setState(() => _rating = v)),
            _starRow('Quality', _quality, (v) => setState(() => _quality = v)),
            _starRow('Delivery', _delivery, (v) => setState(() => _delivery = v)),
            TextField(controller: _commentCtrl, maxLines: 3,
                decoration: const InputDecoration(labelText: 'Comment (optional)', border: OutlineInputBorder())),
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
                    : const Text('Submit Review', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Flag sheet ────────────────────────────────────────────────────────────────

class _FlagSheet extends StatefulWidget {
  final int vendorId;
  final WidgetRef ref;
  const _FlagSheet({required this.vendorId, required this.ref});

  @override
  State<_FlagSheet> createState() => _FlagSheetState();
}

class _FlagSheetState extends State<_FlagSheet> {
  String _reason = 'fraud';
  final _detailsCtrl = TextEditingController();
  bool _loading = false;

  static const _reasons = [
    ('fraud', 'Fraudulent or scam'),
    ('closed', 'Business no longer exists'),
    ('wrong_info', 'Incorrect information'),
    ('duplicate', 'Duplicate listing'),
    ('other', 'Other'),
  ];

  @override
  void dispose() { _detailsCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/vendors/${widget.vendorId}/flag/', data: {
        'reason': _reason,
        'details': _detailsCtrl.text.trim(),
      });
      widget.ref.invalidate(vendorDetailProvider(widget.vendorId));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Thank you.'), backgroundColor: Colors.green),
        );
      }
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
          const Text('Report This Vendor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ..._reasons.map((r) => RadioListTile<String>(
            value: r.$1,
            groupValue: _reason,
            title: Text(r.$2),
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _reason = v ?? 'other'),
          )),
          const SizedBox(height: 8),
          TextField(controller: _detailsCtrl, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Additional details (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
