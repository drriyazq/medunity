import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/client.dart';
import '../../theme.dart';
import '../messaging/messaging_provider.dart';
import 'support_provider.dart';

class RequestsTab extends ConsumerStatefulWidget {
  const RequestsTab({super.key});

  @override
  ConsumerState<RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends ConsumerState<RequestsTab> {
  String _type = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(requestsProvider);

    return Column(
      children: [
        // Type filter — 4 chips, horizontally scrollable so they don't squeeze
        // labels at large font scales.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _TypeChip(
                  label: 'All',
                  selected: _type == '',
                  onTap: () { setState(() => _type = ''); ref.read(requestsProvider.notifier).load(); },
                ),
                const SizedBox(width: 8),
                _TypeChip(
                  label: '🏥 Coverage',
                  selected: _type == 'coverage',
                  onTap: () { setState(() => _type = 'coverage'); ref.read(requestsProvider.notifier).load(type: 'coverage'); },
                ),
                const SizedBox(width: 8),
                _TypeChip(
                  label: '🏢 Space',
                  selected: _type == 'space_lending',
                  onTap: () { setState(() => _type = 'space_lending'); ref.read(requestsProvider.notifier).load(type: 'space_lending'); },
                ),
                const SizedBox(width: 8),
                _TypeChip(
                  label: '👨‍⚕️ Find Associate',
                  selected: _type == 'find_associate',
                  onTap: () { setState(() => _type = 'find_associate'); ref.read(requestsProvider.notifier).load(type: 'find_associate'); },
                ),
              ],
            ),
          ),
        ),

        // Post request button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showCreateRequest(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Post a Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: MedUnityColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),

        // List
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('Could not load requests.')),
            data: (requests) {
              if (requests.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.handshake_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text('No open requests right now.',
                          style: TextStyle(color: MedUnityColors.textSecondary)),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref.read(requestsProvider.notifier).load(type: _type),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _RequestCard(request: requests[i], ref: ref),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCreateRequest(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateRequestSheet(ref: ref),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? MedUnityColors.primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : Colors.black87,
            )),
      ),
    );
  }
}

// ── Request card ──────────────────────────────────────────────────────────────

class _RequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final WidgetRef ref;
  const _RequestCard({required this.request, required this.ref});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _acting = false;

  static const _typeConfig = {
    'coverage': (icon: Icons.swap_horiz, color: Colors.blue, label: 'Patient Coverage'),
    'space_lending': (icon: Icons.business, color: Colors.teal, label: 'Space Lending'),
    'find_associate': (
      icon: Icons.medical_services_outlined,
      color: Color(0xFF8E24AA),
      label: 'Find Associate',
    ),
  };

  Future<void> _accept() async {
    setState(() => _acting = true);
    final dio = widget.ref.read(dioProvider);
    try {
      final resp = await dio.post('/support/requests/${widget.request['id']}/accept/');
      widget.ref.read(requestsProvider.notifier)
          .updateRequest(Map<String, dynamic>.from(resp.data as Map));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not accept request.')),
        );
      }
    }
    if (mounted) setState(() => _acting = false);
  }

  Future<void> _close() async {
    final dio = widget.ref.read(dioProvider);
    try {
      await dio.post('/support/requests/${widget.request['id']}/close/');
      widget.ref.read(requestsProvider.notifier).removeRequest(widget.request['id'] as int);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.request['request_type'] as String? ?? 'coverage';
    final cfg = _typeConfig[type] ?? _typeConfig['coverage']!;
    final isMine = widget.request['is_mine'] as bool? ?? false;
    final iAccepted = widget.request['i_accepted'] as bool? ?? false;
    final status = widget.request['status'] as String? ?? 'open';

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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cfg.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(cfg.icon, color: cfg.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.request['title'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                      '${widget.request['requester_name']} · ${widget.request['requester_specialization']}',
                      style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if ((widget.request['description'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(widget.request['description'] as String,
                style: const TextStyle(fontSize: 13)),
          ],

          if ((widget.request['city'] as String? ?? '').isNotEmpty ||
              widget.request['start_dt'] != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if ((widget.request['city'] as String? ?? '').isNotEmpty) ...[
                  const Icon(Icons.location_on_outlined, size: 14, color: MedUnityColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(widget.request['city'] as String,
                      style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary)),
                  const SizedBox(width: 12),
                ],
                if (widget.request['start_dt'] != null) ...[
                  const Icon(Icons.calendar_today_outlined, size: 14, color: MedUnityColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(_formatDt(widget.request['start_dt'] as String?),
                      style: const TextStyle(fontSize: 12, color: MedUnityColors.textSecondary)),
                ],
              ],
            ),
          ],

          const SizedBox(height: 12),

          if (_acting)
            const LinearProgressIndicator()
          else if (status == 'open') ...[
            if (!isMine) ...[
              if (type == 'find_associate')
                // Find-Associate posts go straight to chat — clinics want to
                // vet associates before "accepting" anyone.
                SizedBox(
                  width: double.infinity,
                  child: _MessageRequesterButton(
                    profId: widget.request['requester_id'] as int?,
                    label: 'Message Clinic',
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _accept,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[600],
                            foregroundColor: Colors.white),
                        child: const Text('I Can Help'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MessageRequesterButton(
                      profId: widget.request['requester_id'] as int?,
                      label: 'Message',
                    ),
                  ],
                ),
            ] else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _close,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
                  child: const Text('Close Request'),
                ),
              ),
          ] else if (status == 'accepted') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    iAccepted
                        ? 'You accepted this request (+15 pts)'
                        : 'Covered by ${widget.request['accepted_by_name'] ?? 'a colleague'}',
                    style: const TextStyle(color: Colors.green, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDt(String? dt) {
    if (dt == null) return '';
    try {
      final d = DateTime.parse(dt).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return dt;
    }
  }
}

// ── Create request sheet ──────────────────────────────────────────────────────

class _CreateRequestSheet extends StatefulWidget {
  final WidgetRef ref;
  const _CreateRequestSheet({required this.ref});

  @override
  State<_CreateRequestSheet> createState() => _CreateRequestSheetState();
}

class _CreateRequestSheetState extends State<_CreateRequestSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  String _type = 'coverage';
  DateTime? _startDt;
  DateTime? _endDt;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose(); _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null) return;
    setState(() {
      if (isStart) _startDt = date; else _endDt = date;
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) { setState(() => _error = 'Title is required.'); return; }
    setState(() { _loading = true; _error = null; });
    final dio = widget.ref.read(dioProvider);
    try {
      final resp = await dio.post('/support/requests/', data: {
        'request_type': _type,
        'title': title,
        'description': _descCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        if (_startDt != null) 'start_dt': _startDt!.toIso8601String(),
        if (_endDt != null) 'end_dt': _endDt!.toIso8601String(),
      });
      widget.ref.read(requestsProvider.notifier)
          .prependRequest(Map<String, dynamic>.from(resp.data as Map));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() { _loading = false; _error = 'Could not post request.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmtDate = (DateTime? d) => d == null ? 'Pick date' : '${d.day}/${d.month}/${d.year}';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Post a Request',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              // Type — 3 options, horizontally scrollable so labels don't clip.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _TypeChip(label: '🏥 Patient Coverage', selected: _type == 'coverage',
                        onTap: () => setState(() => _type = 'coverage')),
                    const SizedBox(width: 8),
                    _TypeChip(label: '🏢 Space Lending', selected: _type == 'space_lending',
                        onTap: () => setState(() => _type = 'space_lending')),
                    const SizedBox(width: 8),
                    _TypeChip(label: '👨‍⚕️ Find Associate', selected: _type == 'find_associate',
                        onTap: () => setState(() => _type = 'find_associate')),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              TextField(controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title *', border: OutlineInputBorder(),
                      hintText: 'e.g. Need coverage for 3 days — vacation')),
              const SizedBox(height: 12),
              TextField(controller: _descCtrl, maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Details (optional)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _cityCtrl,
                  decoration: const InputDecoration(labelText: 'City / Area', border: OutlineInputBorder())),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(true),
                      icon: const Icon(Icons.calendar_today, size: 14),
                      label: Text(fmtDate(_startDt), style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(false),
                      icon: const Icon(Icons.calendar_today, size: 14),
                      label: Text(fmtDate(_endDt), style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: MedUnityColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Post Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageRequesterButton extends ConsumerStatefulWidget {
  final int? profId;
  final String label;
  const _MessageRequesterButton({required this.profId, required this.label});

  @override
  ConsumerState<_MessageRequesterButton> createState() =>
      _MessageRequesterButtonState();
}

class _MessageRequesterButtonState
    extends ConsumerState<_MessageRequesterButton> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy || widget.profId == null) return;
    setState(() => _busy = true);
    final id = await startThreadWith(ref, widget.profId!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) {
      context.push('/messages/$id');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open conversation.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy || widget.profId == null ? null : _open,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chat_bubble_outline, size: 16),
      label: Text(widget.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: MedUnityColors.primary,
        side: const BorderSide(color: MedUnityColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}
