import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import 'messaging_provider.dart';

class ThreadScreen extends ConsumerStatefulWidget {
  final int threadId;
  const ThreadScreen({super.key, required this.threadId});

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _composer = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteMessage(Map<String, dynamic> message) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete for me',
                    style: TextStyle(color: Colors.red)),
                subtitle: const Text(
                    'Removes this message from your view. The other person '
                    'still sees it on their side.'),
                onTap: () => Navigator.pop(sheetCtx, true),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(sheetCtx, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    final success = await ref
        .read(threadDetailProvider(widget.threadId).notifier)
        .deleteMessage(message['id'] as int);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete message.')),
      );
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await ref
        .read(threadDetailProvider(widget.threadId).notifier)
        .send(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _composer.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(threadDetailProvider(widget.threadId));

    return Scaffold(
      appBar: AppBar(
        title: async.maybeWhen(
          data: (d) {
            final other = (d.thread['other'] as Map?) ?? const {};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(other['full_name'] as String? ?? 'Conversation',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text(other['specialization_display'] as String? ?? '',
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            );
          },
          orElse: () => const Text('Conversation'),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/messages'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  const Center(child: Text('Could not load thread.')),
              data: (d) {
                if (d.messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_outlined,
                              size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          const Text(
                            'No messages yet — say hello.',
                            style: TextStyle(
                                color: MedUnityColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                // Auto-scroll to bottom on first build with data
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollCtrl.hasClients) {
                    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  itemCount: d.messages.length,
                  itemBuilder: (_, i) {
                    final m = d.messages[i];
                    return _MessageBubble(
                      message: m,
                      onLongPress: () => _confirmDeleteMessage(m),
                    );
                  },
                );
              },
            ),
          ),
          _Composer(
            controller: _composer,
            onSend: _send,
            sending: _sending,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final VoidCallback onLongPress;
  const _MessageBubble({
    required this.message,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isMine = message['is_mine'] as bool? ?? false;
    final body = message['body'] as String? ?? '';
    final created = message['created_at'] as String?;
    final timeLabel = _formatTime(created);

    final bubbleColor =
        isMine ? MedUnityColors.primary : Colors.grey[200]!;
    final textColor = isMine ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: onLongPress,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft:
                            isMine ? const Radius.circular(16) : Radius.zero,
                        bottomRight:
                            isMine ? Radius.zero : const Radius.circular(16),
                      ),
                    ),
                    child: Text(
                      body,
                      style: TextStyle(color: textColor, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    color: MedUnityColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message…',
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: MedUnityColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  return DateFormat('h:mm a').format(dt.toLocal());
}
