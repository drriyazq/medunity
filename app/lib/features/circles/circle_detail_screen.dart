import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import 'circles_provider.dart';

class CircleDetailScreen extends ConsumerWidget {
  final int circleId;
  const CircleDetailScreen({super.key, required this.circleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(circleDetailProvider(circleId));

    return detailAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Could not load circle.')),
      ),
      data: (circle) {
        final isMember = circle['is_member'] as bool? ?? false;
        final isAdmin = circle['my_role'] == 'admin';
        return Scaffold(
          appBar: AppBar(
            title: Text(circle['name'] as String),
            actions: [
              if (isMember)
                PopupMenuButton<String>(
                  onSelected: (val) => _onMenu(context, ref, val, circle),
                  itemBuilder: (_) => [
                    if (isAdmin)
                      const PopupMenuItem(value: 'members', child: Text('Manage Members')),
                    const PopupMenuItem(value: 'leave', child: Text('Leave Circle')),
                  ],
                ),
            ],
          ),
          body: isMember
              ? _PostsFeed(circleId: circleId, circle: circle)
              : _JoinPrompt(circleId: circleId, ref: ref),
          floatingActionButton: isMember
              ? FloatingActionButton.extended(
                  onPressed: () => _showCreatePost(context, ref, circle),
                  backgroundColor: MedUnityColors.primary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.edit),
                  label: const Text('Post'),
                )
              : null,
        );
      },
    );
  }

  void _onMenu(BuildContext context, WidgetRef ref, String val, Map circle) async {
    if (val == 'leave') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Leave Circle'),
          content: const Text('Are you sure you want to leave this circle?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      final dio = ref.read(dioProvider);
      try {
        await dio.delete('/circles/$circleId/leave/');
        ref.invalidate(myCirclesProvider);
        if (context.mounted) context.pop();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not leave circle.')),
          );
        }
      }
    } else if (val == 'members') {
      _showMembersSheet(context, ref, circle);
    }
  }

  void _showMembersSheet(BuildContext context, WidgetRef ref, Map circle) {
    final members = (circle['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    showModalBottomSheet(
      context: context,
      builder: (_) => _MembersSheet(
        circleId: circleId,
        members: members,
        ref: ref,
      ),
    );
  }

  void _showCreatePost(BuildContext context, WidgetRef ref, Map circle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePostSheet(circleId: circleId, ref: ref),
    );
  }
}

// ── Posts feed ────────────────────────────────────────────────────────────────

class _PostsFeed extends ConsumerWidget {
  final int circleId;
  final Map<String, dynamic> circle;
  const _PostsFeed({required this.circleId, required this.circle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider(circleId));

    return postsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load posts.')),
      data: (posts) {
        if (posts.isEmpty) {
          return const Center(
            child: Text('No posts yet. Be the first to post!',
                style: TextStyle(color: MedUnityColors.textSecondary)),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(postsProvider(circleId).notifier).load(refresh: true),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: posts.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              if (i == posts.length) {
                return _LoadMoreButton(circleId: circleId, ref: ref);
              }
              return _PostCard(
                post: posts[i],
                circleId: circleId,
                ref: ref,
              );
            },
          ),
        );
      },
    );
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final int circleId;
  final WidgetRef ref;
  const _PostCard({required this.post, required this.circleId, required this.ref});

  static const _typeIcon = {
    'discussion': Icons.chat_bubble_outline,
    'event': Icons.event,
    'announcement': Icons.campaign_outlined,
  };
  static const _typeColor = {
    'discussion': MedUnityColors.primary,
    'event': Colors.orange,
    'announcement': Colors.purple,
  };

  @override
  Widget build(BuildContext context) {
    final postType = post['post_type'] as String? ?? 'discussion';
    final isMine = post['is_mine'] as bool? ?? false;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_typeIcon[postType] ?? Icons.chat_bubble_outline,
                  color: _typeColor[postType] ?? MedUnityColors.primary, size: 16),
              const SizedBox(width: 6),
              Text(
                post['author_name'] as String? ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              if (isMine)
                GestureDetector(
                  onTap: () => _deletePost(context),
                  child: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(post['content'] as String? ?? ''),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => context.push('/circles/$circleId/posts/${post['id']}'),
            child: Row(
              children: [
                const Icon(Icons.comment_outlined, size: 16, color: MedUnityColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${post['comment_count'] ?? 0} comments',
                  style: const TextStyle(
                      color: MedUnityColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Delete this post permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/circles/$circleId/posts/${post['id']}/');
      ref.read(postsProvider(circleId).notifier).removePost(post['id'] as int);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete post.')),
        );
      }
    }
  }
}

class _LoadMoreButton extends StatefulWidget {
  final int circleId;
  final WidgetRef ref;
  const _LoadMoreButton({required this.circleId, required this.ref});

  @override
  State<_LoadMoreButton> createState() => _LoadMoreButtonState();
}

class _LoadMoreButtonState extends State<_LoadMoreButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final hasMore = widget.ref.read(postsProvider(widget.circleId).notifier).hasMore;
    if (!hasMore) return const SizedBox.shrink();
    return Center(
      child: _loading
          ? const CircularProgressIndicator()
          : TextButton(
              onPressed: () async {
                setState(() => _loading = true);
                await widget.ref.read(postsProvider(widget.circleId).notifier).loadMore();
                if (mounted) setState(() => _loading = false);
              },
              child: const Text('Load more'),
            ),
    );
  }
}

// ── Join prompt ───────────────────────────────────────────────────────────────

class _JoinPrompt extends StatefulWidget {
  final int circleId;
  final WidgetRef ref;
  const _JoinPrompt({required this.circleId, required this.ref});

  @override
  State<_JoinPrompt> createState() => _JoinPromptState();
}

class _JoinPromptState extends State<_JoinPrompt> {
  bool _loading = false;

  Future<void> _join() async {
    setState(() => _loading = true);
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/circles/${widget.circleId}/join/');
      widget.ref.invalidate(circleDetailProvider(widget.circleId));
      widget.ref.invalidate(myCirclesProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not join.')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 64, color: MedUnityColors.textSecondary),
          const SizedBox(height: 16),
          const Text('Join this circle to see posts.',
              style: TextStyle(color: MedUnityColors.textSecondary)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _join,
            style: ElevatedButton.styleFrom(
                backgroundColor: MedUnityColors.primary, foregroundColor: Colors.white),
            child: _loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Join Circle'),
          ),
        ],
      ),
    );
  }
}

// ── Members sheet ─────────────────────────────────────────────────────────────

class _MembersSheet extends StatelessWidget {
  final int circleId;
  final List<Map<String, dynamic>> members;
  final WidgetRef ref;
  const _MembersSheet({required this.circleId, required this.members, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Members (${members.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...members.map((m) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(m['full_name'] as String? ?? ''),
                subtitle: Text(m['specialization'] as String? ?? ''),
                trailing: m['role'] == 'admin'
                    ? const Chip(label: Text('Admin'), padding: EdgeInsets.zero)
                    : TextButton(
                        onPressed: () => _kick(context, m['id'] as int),
                        child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
              )),
        ],
      ),
    );
  }

  Future<void> _kick(BuildContext context, int memberId) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/circles/$circleId/kick/$memberId/');
      ref.invalidate(circleDetailProvider(circleId));
      if (context.mounted) Navigator.pop(context);
    } catch (_) {}
  }
}

// ── Create post sheet ─────────────────────────────────────────────────────────

class _CreatePostSheet extends StatefulWidget {
  final int circleId;
  final WidgetRef ref;
  const _CreatePostSheet({required this.circleId, required this.ref});

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _contentCtrl = TextEditingController();
  String _postType = 'discussion';
  bool _loading = false;

  static const _types = [
    (value: 'discussion', label: 'Discussion', icon: Icons.chat_bubble_outline),
    (value: 'event', label: 'Event', icon: Icons.event),
    (value: 'announcement', label: 'Announcement', icon: Icons.campaign_outlined),
  ];

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) return;
    setState(() => _loading = true);
    final dio = widget.ref.read(dioProvider);
    try {
      final resp = await dio.post('/circles/${widget.circleId}/posts/', data: {
        'content': content,
        'post_type': _postType,
      });
      widget.ref
          .read(postsProvider(widget.circleId).notifier)
          .prependPost(Map<String, dynamic>.from(resp.data as Map));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create post.')),
        );
      }
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
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            // Post type selector
            Row(
              children: _types.map((t) {
                final selected = _postType == t.value;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(t.icon, size: 16),
                      label: Text(t.label, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      onSelected: (_) => setState(() => _postType = t.value),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentCtrl,
              maxLines: 5,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Share something with the circle…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
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
                    : const Text('Post', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
