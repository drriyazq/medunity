import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'consultants_provider.dart';

class ConsultantProfileScreen extends ConsumerWidget {
  final int profId;
  const ConsultantProfileScreen({super.key, required this.profId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(consultantProfileProvider(profId));

    return Scaffold(
      appBar: AppBar(title: const Text('Consultant Profile')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load profile.')),
        data: (prof) => _ProfileBody(prof: prof, profId: profId, ref: ref),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final Map<String, dynamic> prof;
  final int profId;
  final WidgetRef ref;
  const _ProfileBody({required this.prof, required this.profId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final avgRating = prof['avg_rating'] as double?;
    final reviewCount = prof['review_count'] as int? ?? 0;
    final reviews = (prof['recent_reviews'] as List? ?? []).cast<Map<String, dynamic>>();
    final isAvailable = prof['is_available'] as bool? ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundImage: prof['profile_photo'] != null
                          ? NetworkImage(prof['profile_photo'] as String)
                          : null,
                      child: prof['profile_photo'] == null
                          ? const Icon(Icons.person, size: 36)
                          : null,
                    ),
                    if (isAvailable)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(prof['full_name'] as String,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(prof['specialization'] as String,
                          style: const TextStyle(
                              color: MedUnityColors.primary, fontSize: 14)),
                      if (prof['clinic_name'] != null)
                        Text(
                          '${prof['clinic_name']}, ${prof['clinic_city'] ?? ''}',
                          style: const TextStyle(
                              fontSize: 12, color: MedUnityColors.textSecondary),
                        ),
                      if (avgRating != null)
                        Row(
                          children: [
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text('$avgRating ($reviewCount reviews)',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // About
          if ((prof['about'] as String? ?? '').isNotEmpty) ...[
            const Text('About',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            Text(prof['about'] as String),
            const SizedBox(height: 16),
          ],

          // Availability + Book button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isAvailable
                  ? Colors.green.withOpacity(0.07)
                  : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isAvailable
                      ? Colors.green.withOpacity(0.3)
                      : Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(
                  isAvailable ? Icons.circle : Icons.circle_outlined,
                  size: 14,
                  color: isAvailable ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  isAvailable ? 'Available for consultation' : 'Currently unavailable',
                  style: TextStyle(
                      color: isAvailable ? Colors.green[700] : Colors.grey[600],
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isAvailable
                  ? () => _showBookingSheet(context, ref, prof)
                  : null,
              icon: const Icon(Icons.send),
              label: const Text('Request Consultation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: MedUnityColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[200],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // Reviews
          if (reviews.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Recent Reviews',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            ...reviews.map((r) => _ReviewCard(review: r)),
          ],
        ],
      ),
    );
  }

  void _showBookingSheet(BuildContext context, WidgetRef ref, Map<String, dynamic> prof) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookingSheet(profId: profId, profName: prof['full_name'] as String, ref: ref),
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
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(review['reviewer_name'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
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

// ── Booking request sheet ─────────────────────────────────────────────────────

class _BookingSheet extends StatefulWidget {
  final int profId;
  final String profName;
  final WidgetRef ref;
  const _BookingSheet({required this.profId, required this.profName, required this.ref});

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  final _procedureCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _procedureCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final procedure = _procedureCtrl.text.trim();
    if (procedure.isEmpty) {
      setState(() => _error = 'Procedure is required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/consultants/bookings/', data: {
        'consultant_id': widget.profId,
        'procedure': procedure,
        'notes': _notesCtrl.text.trim(),
      });
      widget.ref.invalidate(myBookingsProvider('requester'));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Booking request sent to ${widget.profName}!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Could not send booking. Try again.';
      });
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
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Request Consultation — ${widget.profName}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _procedureCtrl,
              decoration: const InputDecoration(
                labelText: 'Procedure required *',
                border: OutlineInputBorder(),
                hintText: 'e.g. Root canal treatment, Surgical extraction',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Additional notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MedUnityColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Send Request',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
