import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import 'messaging_provider.dart';

class MessagesTab extends ConsumerWidget {
  const MessagesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(threadsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(threadsProvider.notifier).load(),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(
            child: Text('Could not load conversations.'),
          ),
          data: (threads) {
            if (threads.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  _EmptyState(),
                ],
              );
            }
            return ListView.separated(
              itemCount: threads.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
              itemBuilder: (_, i) => _ThreadRow(thread: threads[i]),
            );
          },
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  final Map<String, dynamic> thread;
  const _ThreadRow({required this.thread});

  @override
  Widget build(BuildContext context) {
    final other = (thread['other'] as Map?) ?? const {};
    final name = other['full_name'] as String? ?? 'Unknown';
    final spec = other['specialization_display'] as String? ?? '';
    final photo = other['profile_photo'] as String?;
    final last = thread['last_message'] as Map?;
    final unread = thread['unread_count'] as int? ?? 0;

    final lastBody = last?['body'] as String? ?? '';
    final lastIsMine = (last?['is_mine'] as bool?) ?? false;
    final lastPreview = last == null
        ? 'Start the conversation'
        : (lastIsMine ? 'You: $lastBody' : lastBody);

    final lastAt = thread['last_message_at'] as String?;
    final timeLabel = _shortRelativeTime(lastAt);

    return InkWell(
      onTap: () => context.push('/messages/${thread['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: MedUnityColors.primary.withOpacity(0.12),
              backgroundImage:
                  (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
              child: (photo == null || photo.isEmpty)
                  ? Text(
                      _initials(name),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: MedUnityColors.primary),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: unread > 0
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: unread > 0
                              ? MedUnityColors.primary
                              : Colors.grey[500],
                          fontWeight: unread > 0
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (spec.isNotEmpty)
                    Text(
                      spec,
                      style: const TextStyle(
                          fontSize: 11, color: MedUnityColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: unread > 0
                                ? Colors.black87
                                : Colors.grey[600],
                            fontWeight:
                                unread > 0 ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: const BoxDecoration(
                            color: MedUnityColors.primary,
                            shape: BoxShape.rectangle,
                            borderRadius:
                                BorderRadius.all(Radius.circular(10)),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No conversations yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: MedUnityColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a doctor’s profile, an associate listing, or a consultant card '
            'and choose Message to start a chat.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.replaceFirst(RegExp(r'^Dr\s+', caseSensitive: false), '').trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

String _shortRelativeTime(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final local = dt.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return DateFormat.E().format(local);
  return DateFormat('d MMM').format(local);
}
