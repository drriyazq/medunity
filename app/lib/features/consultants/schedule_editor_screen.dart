import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import 'live_provider.dart';

const _kDays = [
  ('mon', 'Monday'), ('tue', 'Tuesday'), ('wed', 'Wednesday'),
  ('thu', 'Thursday'), ('fri', 'Friday'), ('sat', 'Saturday'),
  ('sun', 'Sunday'),
];

class ScheduleEditorScreen extends ConsumerStatefulWidget {
  const ScheduleEditorScreen({super.key});
  @override
  ConsumerState<ScheduleEditorScreen> createState() =>
      _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends ConsumerState<ScheduleEditorScreen> {
  List<Map<String, String>> _schedule = [];
  bool _initialised = false;
  bool _saving = false;

  void _hydrate(List raw) {
    if (_initialised) return;
    _initialised = true;
    _schedule = raw
        .cast<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
        .toList();
  }

  Future<void> _addWindow() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _WindowEditorDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _schedule.add(result));
  }

  Future<void> _editWindow(int idx) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _WindowEditorDialog(initial: _schedule[idx]),
    );
    if (result == null || !mounted) return;
    setState(() => _schedule[idx] = result);
  }

  void _removeWindow(int idx) {
    setState(() => _schedule.removeAt(idx));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await ref
        .read(liveSettingsProvider.notifier)
        .save({'working_schedule': _schedule});
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Schedule saved.'),
        backgroundColor: Colors.green,
      ));
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save — check time formats.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  String _dayLabel(String key) =>
      _kDays.firstWhere((d) => d.$1 == key, orElse: () => (key, key)).$2;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(liveSettingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Working hours'),
        actions: [
          if (_initialised)
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('SAVE',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Could not load schedule.')),
        data: (s) {
          _hydrate(s['working_schedule'] as List? ?? []);
          // Group by day for display
          final byDay = <String, List<int>>{};
          for (var i = 0; i < _schedule.length; i++) {
            byDay.putIfAbsent(_schedule[i]['day']!, () => []).add(i);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Set the windows when you want to be Go Live automatically. '
                'Outside these windows, Go Live stays off unless you turn it on manually.',
                style:
                    TextStyle(fontSize: 13, color: MedUnityColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ..._kDays.map((d) {
                final indices = byDay[d.$1] ?? [];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.$2,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        if (indices.isEmpty)
                          const Text('No windows',
                              style: TextStyle(
                                  color: MedUnityColors.textSecondary,
                                  fontSize: 12)),
                        ...indices.map((idx) {
                          final w = _schedule[idx];
                          return Row(
                            children: [
                              Expanded(
                                child: Text('${w['start']} – ${w['end']}',
                                    style: const TextStyle(fontSize: 14)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _editWindow(idx),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                onPressed: () => _removeWindow(idx),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _addWindow,
                icon: const Icon(Icons.add),
                label: const Text('Add window'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WindowEditorDialog extends StatefulWidget {
  final Map<String, String>? initial;
  const _WindowEditorDialog({this.initial});
  @override
  State<_WindowEditorDialog> createState() => _WindowEditorDialogState();
}

class _WindowEditorDialogState extends State<_WindowEditorDialog> {
  String _day = 'mon';
  TimeOfDay _start = const TimeOfDay(hour: 11, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _day = init['day'] ?? 'mon';
      _start = _parse(init['start']) ?? _start;
      _end = _parse(init['end']) ?? _end;
    }
  }

  TimeOfDay? _parse(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _start = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add window' : 'Edit window'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _day,
            decoration: const InputDecoration(labelText: 'Day'),
            items: _kDays
                .map((d) =>
                    DropdownMenuItem(value: d.$1, child: Text(d.$2)))
                .toList(),
            onChanged: (v) => setState(() => _day = v ?? 'mon'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start'),
                  subtitle: Text(_hhmm(_start)),
                  onTap: () => _pick(start: true),
                ),
              ),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End'),
                  subtitle: Text(_hhmm(_end)),
                  onTap: () => _pick(start: false),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: () {
            if ((_end.hour * 60 + _end.minute) <=
                (_start.hour * 60 + _start.minute)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('End time must be after start time.'),
              ));
              return;
            }
            Navigator.pop(context, {
              'day': _day,
              'start': _hhmm(_start),
              'end': _hhmm(_end),
            });
          },
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}
