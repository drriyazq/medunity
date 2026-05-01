import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import 'associate_provider.dart';
import 'rate_doctor_sheet.dart';
import 'request_booking_sheet.dart';

class AssociatePublicScreen extends ConsumerWidget {
  final int profId;
  const AssociatePublicScreen({super.key, required this.profId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(publicDoctorProfileProvider(profId));

    return Scaffold(
      appBar: AppBar(title: const Text('Doctor Profile')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load profile.'),
                const SizedBox(height: 12),
                ElevatedButton(
                    onPressed: () =>
                        ref.invalidate(publicDoctorProfileProvider(profId)),
                    child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (data) => _buildBody(context, ref, data),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) {
    final fullName = (data['full_name'] as String?) ?? 'Doctor';
    final spec = (data['specialization_display'] as String?) ?? '';
    final qualification = (data['qualification'] as String?) ?? '';
    final years = data['years_experience'] as int?;
    final about = (data['about'] as String?) ?? '';
    final clinic = data['clinic'] as Map?;
    final assocProfile = data['associate_profile'] as Map?;
    final isAvailable = (assocProfile?['is_available_for_hire'] as bool?) ?? false;

    final ratingAssoc = data['rating_associate'] as Map?;
    final ratingClinic = data['rating_clinic'] as Map?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: MedUnityColors.primary.withOpacity(0.12),
              child: const Icon(Icons.person,
                  color: MedUnityColors.primary, size: 36),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fullName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  if (spec.isNotEmpty)
                    Text(spec,
                        style: const TextStyle(
                            color: MedUnityColors.primary, fontSize: 13)),
                  if (qualification.isNotEmpty || years != null)
                    Text(
                      [
                        if (qualification.isNotEmpty) qualification,
                        if (years != null) '$years yrs exp',
                      ].join(' · '),
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),

        if (about.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(about,
              style: TextStyle(color: Colors.grey[800], fontSize: 13)),
        ],

        // Associate availability + rates card
        if (assocProfile != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isAvailable
                  ? Colors.green.withOpacity(0.06)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isAvailable
                      ? Colors.green.withOpacity(0.4)
                      : Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isAvailable
                          ? Icons.check_circle
                          : Icons.do_not_disturb_alt_outlined,
                      color: isAvailable
                          ? Colors.green
                          : MedUnityColors.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAvailable
                          ? 'Available for short-term hire'
                          : 'Not currently available',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (assocProfile['rate_per_slot'] != null)
                  _RateRow(
                    label:
                        'Per ${assocProfile['slot_hours'] ?? 4}h slot',
                    amount: assocProfile['rate_per_slot'].toString(),
                  ),
                if (assocProfile['rate_per_day'] != null)
                  _RateRow(
                    label: 'Per day',
                    amount: assocProfile['rate_per_day'].toString(),
                  ),
                if ((assocProfile['bio'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(assocProfile['bio'] as String,
                      style:
                          TextStyle(color: Colors.grey[800], fontSize: 13)),
                ],
                if ((assocProfile['notes'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(assocProfile['notes'] as String,
                      style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 12),
                if (isAvailable)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => showRequestBookingSheet(
                        context: context,
                        ref: ref,
                        profId: profId,
                        profName: fullName,
                        ratePerSlot: assocProfile['rate_per_slot'],
                        ratePerDay: assocProfile['rate_per_day'],
                        slotHours: assocProfile['slot_hours'] as int?,
                      ),
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Request Booking'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MedUnityColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Clinic
        if (clinic != null) ...[
          const SizedBox(height: 16),
          const _SectionTitle('Clinic'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clinic['name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if ((clinic['address'] as String? ?? '').isNotEmpty)
                  Text(
                    [clinic['address'], clinic['city']]
                        .where((s) => (s as String?)?.isNotEmpty == true)
                        .join(', '),
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
              ],
            ),
          ),
        ],

        // Ratings
        const SizedBox(height: 16),
        const _SectionTitle('Ratings'),
        Row(
          children: [
            Expanded(
              child: _RatingTile(
                label: 'As Associate',
                rating: (ratingAssoc?['avg_rating'] as num?)?.toDouble(),
                count: ratingAssoc?['review_count'] as int? ?? 0,
                onRate: () => showRateDoctorSheet(
                  context: context,
                  profId: profId,
                  profName: fullName,
                  reviewContext: 'associate',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RatingTile(
                label: 'As Clinic',
                rating: (ratingClinic?['avg_rating'] as num?)?.toDouble(),
                count: ratingClinic?['review_count'] as int? ?? 0,
                onRate: () => showRateDoctorSheet(
                  context: context,
                  profId: profId,
                  profName: fullName,
                  reviewContext: 'clinic',
                ),
              ),
            ),
          ],
        ),

        // Reviews list (anonymous)
        const SizedBox(height: 16),
        const _SectionTitle('Recent reviews'),
        _ReviewsList(profId: profId),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _RateRow extends StatelessWidget {
  final String label;
  final String amount;
  const _RateRow({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.currency_rupee, size: 14, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Expanded(
            child: Text('$label: ₹$amount',
                style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _RatingTile extends StatelessWidget {
  final String label;
  final double? rating;
  final int count;
  final VoidCallback onRate;
  const _RatingTile({
    required this.label,
    required this.rating,
    required this.count,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
              const SizedBox(width: 4),
              Text(
                rating != null ? rating!.toStringAsFixed(1) : '—',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(width: 4),
              Text('($count)',
                  style:
                      TextStyle(color: Colors.grey[600], fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: onRate,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 6),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Rate', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _ReviewsList extends ConsumerWidget {
  final int profId;
  const _ReviewsList({required this.profId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = ReviewsArgs(profId, null);
    final async = ref.watch(reviewsForProvider(args));
    return async.when(
      loading: () => const SizedBox(
          height: 4, child: LinearProgressIndicator()),
      error: (_, __) =>
          Text('Could not load reviews.', style: TextStyle(color: Colors.grey[600])),
      data: (data) {
        final reviews =
            (data['reviews'] as List? ?? []).cast<Map>();
        if (reviews.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No reviews yet.',
                style: TextStyle(color: Colors.grey[600])),
          );
        }
        return Column(
          children: reviews.take(20).map((r) {
            final rating = r['rating'] as int? ?? 0;
            final comment = (r['comment'] as String?) ?? '';
            final ctx = (r['context_display'] as String?) ?? '';
            final created =
                DateTime.tryParse(r['updated_at'] as String? ?? '')?.toLocal();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
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
                            i < rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 16,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(ctx,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600])),
                      const Spacer(),
                      if (created != null)
                        Text(DateFormat('d MMM').format(created),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  if (comment.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(comment,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
    );
  }
}
