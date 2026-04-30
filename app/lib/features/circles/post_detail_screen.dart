import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'circles_provider.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  final int circleId;
  final int postId;
  const PostDetailScreen({super.key, required this.circleId, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;
    setState(() => _submitting = true);
    final dio = ref.read(dioProvider);
    try {
      final resp = await dio.post(
          '/circles/${widget.circleId}/posts/${widget.postId}/comments/',
          data: {'content': content});
      ref
          .read(commentsProvider((circleId: widget.circleId, postId: widget.postId)).notifier)
          .appendComment(Map<String, dynamic>.from(resp.data as Map));
      _commentCtrl.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not post comment.')),
        );
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _deleteComment(int commentId) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.delete(
          '/circles/${widget.circleId}/posts/${widget.postId}/comments/$commentId/');
      ref
          .read(commentsProvider((circleId: widget.circleId, postId: widget.postId)).notifier)
          .removeComment(commentId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(
        commentsProvider((circleId: widget.circleId, postId: widget.postId)));

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: Column(
        children: [
          Expanded(
            child: commentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  const Center(child: Text('Could not load comments.')),
              data: (comments) => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: comments.length + (comments.isEmpty ? 1 : 0),
                itemBuilder: (_, i) {
                  if (comments.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No comments yet. Be the first!',
                            style: TextStyle(color: MedUnityColors.textSecondary)),
                      ),
                    );
                  }
                  return _CommentTile(
                    comment: comments[i],
                    onDelete: () => _deleteComment(comments[i]['id'] as int),
                  );
                },
              ),
            ),
          ),

          // Comment input bar
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    decoration: InputDecoration(
                      hintText: 'Write a comment…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(width: 8),
                _submitting
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.send, color: MedUnityColors.primary),
                        onPressed: _submitComment,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  final VoidCallback onDelete;
  const _CommentTile({required this.comment, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isMine = comment['is_mine'] as bool? ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 16,
            child: Icon(Icons.person_outline, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment['author_name'] as String? ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(comment['content'] as String? ?? ''),
                ],
              ),
            ),
          ),
          if (isMine)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
