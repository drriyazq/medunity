import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'associate_provider.dart';

/// Bottom sheet — rate any verified doctor 1–5 stars + optional comment.
/// Reviews are anonymous to the reviewee but stored against [reviewerId]
/// for admin audit. If the user already has a review for this doctor in
/// this context, that prior rating/comment is pre-filled and the submit
/// will replace it (one row per (reviewer, reviewee, context)).
Future<bool?> showRateDoctorSheet({
  required BuildContext context,
  required int profId,
  required String profName,
  String reviewContext = 'general',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RateDoctorSheet(
      profId: profId,
      profName: profName,
      reviewContext: reviewContext,
    ),
  );
}

class _RateDoctorSheet extends ConsumerStatefulWidget {
  final int profId;
  final String profName;
  final String reviewContext;

  const _RateDoctorSheet({
    required this.profId,
    required this.profName,
    required this.reviewContext,
  });

  @override
  ConsumerState<_RateDoctorSheet> createState() => _RateDoctorSheetState();
}

class _RateDoctorSheetState extends ConsumerState<_RateDoctorSheet> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _busy = false;
  bool _initialised = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    if (_initialised) return;
    _initialised = true;
    final args = ReviewsArgs(widget.profId, widget.reviewContext);
    final mine = await ref.read(myReviewForProvider(args).future);
    if (!mounted || mine == null) return;
    setState(() {
      _rating = (mine['rating'] as int?) ?? 0;
      _commentCtrl.text = (mine['comment'] as String?) ?? '';
    });
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a star rating first.')),
      );
      return;
    }
    setState(() => _busy = true);
    final dio = ref.read(dioProvider);
    try {
      await dio.post('/reviews/', data: {
        'reviewee': widget.profId,
        'rating': _rating,
        'comment': _commentCtrl.text.trim(),
        'context': widget.reviewContext,
      });
      if (!mounted) return;
      ref.invalidate(reviewsForProvider(
          ReviewsArgs(widget.profId, widget.reviewContext)));
      ref.invalidate(reviewsForProvider(ReviewsArgs(widget.profId, null)));
      ref.invalidate(publicDoctorProfileProvider(widget.profId));
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks — your review was submitted anonymously.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not submit review. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _hydrate();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Rate ${widget.profName}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Reviews are anonymous. Only an aggregate rating + your comment are shown to others.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setState(() => _rating = i),
                    iconSize: 36,
                    icon: Icon(
                      _rating >= i ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: Colors.amber,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MedUnityColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Submit Review',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
