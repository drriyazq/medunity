import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';

// ── Inbox / threads list ──────────────────────────────────────────────────────

class ThreadsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  ThreadsNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/messages/threads/');
      state = AsyncValue.data(
        (resp.data as List).cast<Map<String, dynamic>>(),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void upsertFromSummary(Map<String, dynamic> summary) {
    final current = state.valueOrNull ?? [];
    final id = summary['id'] as int;
    final filtered = current.where((t) => t['id'] != id).toList();
    state = AsyncValue.data([summary, ...filtered]);
  }

  void zeroUnread(int threadId) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([
      for (final t in current)
        if (t['id'] == threadId)
          {...t, 'unread_count': 0}
        else
          t,
    ]);
  }
}

final threadsProvider = StateNotifierProvider.autoDispose<ThreadsNotifier,
    AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => ThreadsNotifier(ref),
);

// ── Unread count for the bottom-nav badge ─────────────────────────────────────
//
// NOT autoDispose — kept alive by HomeShell so the badge stays accurate even
// when the user is deep inside another tab. Refresh from push handler when a
// new direct_message arrives.

final messagesUnreadCountProvider = FutureProvider<int>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final resp = await dio.get('/messages/unread-count/');
    return resp.data['unread_count'] as int? ?? 0;
  } catch (_) {
    return 0;
  }
});

// ── Single thread detail (messages + thread summary) ──────────────────────────

class ThreadDetail {
  final Map<String, dynamic> thread;
  final List<Map<String, dynamic>> messages;
  const ThreadDetail({required this.thread, required this.messages});

  ThreadDetail copyWith({
    Map<String, dynamic>? thread,
    List<Map<String, dynamic>>? messages,
  }) =>
      ThreadDetail(
        thread: thread ?? this.thread,
        messages: messages ?? this.messages,
      );
}

class ThreadDetailNotifier extends StateNotifier<AsyncValue<ThreadDetail>> {
  final Ref _ref;
  final int threadId;
  ThreadDetailNotifier(this._ref, this.threadId)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.get('/messages/threads/$threadId/');
      final data = resp.data as Map;
      state = AsyncValue.data(ThreadDetail(
        thread: Map<String, dynamic>.from(data['thread'] as Map),
        messages: (data['messages'] as List).cast<Map<String, dynamic>>(),
      ));
      // Server-side mark-read so unread count zeroes out.
      _markRead();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> send(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    final dio = _ref.read(dioProvider);
    try {
      final resp = await dio.post(
        '/messages/threads/$threadId/messages/',
        data: {'body': trimmed},
      );
      final newMsg = Map<String, dynamic>.from(resp.data as Map);
      final detail = state.valueOrNull;
      if (detail != null) {
        state = AsyncValue.data(detail.copyWith(
          messages: [...detail.messages, newMsg],
          thread: {
            ...detail.thread,
            'last_message': {
              'body': newMsg['body'],
              'sender_id': newMsg['sender_id'],
              'is_mine': true,
              'created_at': newMsg['created_at'],
            },
            'last_message_at': newMsg['created_at'],
          },
        ));
      }
      // Refresh inbox + badge so the sender's UI reflects the new last-message.
      _ref.read(threadsProvider.notifier).load();
      _ref.invalidate(messagesUnreadCountProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markRead() async {
    final dio = _ref.read(dioProvider);
    try {
      await dio.post('/messages/threads/$threadId/read/');
      _ref.read(threadsProvider.notifier).zeroUnread(threadId);
      _ref.invalidate(messagesUnreadCountProvider);
    } catch (_) {
      // Silent — read state is best-effort.
    }
  }

  /// Soft-delete a single message for me only. Other side still sees it.
  Future<bool> deleteMessage(int messageId) async {
    final dio = _ref.read(dioProvider);
    try {
      await dio.delete(
          '/messages/threads/$threadId/messages/$messageId/delete/');
      final detail = state.valueOrNull;
      if (detail != null) {
        state = AsyncValue.data(detail.copyWith(
          messages: detail.messages
              .where((m) => m['id'] != messageId)
              .toList(),
        ));
      }
      // Refresh inbox so the last-message preview updates if we just
      // deleted the most recent message.
      _ref.read(threadsProvider.notifier).load();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Soft-delete the whole thread for me only. Server keeps the row; the
/// thread reappears in my inbox if the other side messages again.
Future<bool> deleteThreadForMe(WidgetRef ref, int threadId) async {
  final dio = ref.read(dioProvider);
  try {
    await dio.delete('/messages/threads/$threadId/delete/');
    ref.read(threadsProvider.notifier).load();
    ref.invalidate(messagesUnreadCountProvider);
    return true;
  } catch (_) {
    return false;
  }
}

final threadDetailProvider = StateNotifierProvider.autoDispose
    .family<ThreadDetailNotifier, AsyncValue<ThreadDetail>, int>(
  (ref, id) => ThreadDetailNotifier(ref, id),
);

// ── Start / fetch thread by professional id ───────────────────────────────────

/// Starts (or resumes) a thread with the given professional. Returns the
/// thread id on success — caller pushes to /messages/<id>.
Future<int?> startThreadWith(WidgetRef ref, int profId) async {
  final dio = ref.read(dioProvider);
  try {
    final resp = await dio.post('/messages/threads/with/$profId/');
    final id = (resp.data as Map)['id'] as int;
    ref.read(threadsProvider.notifier).load();
    return id;
  } catch (_) {
    return null;
  }
}
