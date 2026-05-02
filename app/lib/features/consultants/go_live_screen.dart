import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/local/hive_setup.dart';
import '../../services/consultant_live_service.dart';
import '../../services/consultant_schedule_alarm.dart';
import '../../theme.dart';
import 'consultants_provider.dart';
import 'live_provider.dart';

const _kConsentKey = 'consultant_live_consent_v1';

class GoLiveScreen extends ConsumerStatefulWidget {
  const GoLiveScreen({super.key});

  @override
  ConsumerState<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends ConsumerState<GoLiveScreen> {
  bool _busy = false;

  bool _hasConsented() {
    return HiveSetup.sessionBox.get(_kConsentKey) as bool? ?? false;
  }

  Future<void> _toggle(bool on) async {
    if (on && !_hasConsented()) {
      final ok = await context.push<bool>('/consultants/live-consent');
      if (ok != true) return;
      await HiveSetup.sessionBox.put(_kConsentKey, true);
    }

    setState(() => _busy = true);
    try {
      final settings =
          ref.read(liveSettingsProvider).valueOrNull ?? <String, dynamic>{};
      final mobility = (settings['mobility_mode'] as String?) ?? 'mobile';
      final schedule = (settings['working_schedule'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map((m) => m.map((k, v) => MapEntry(k, v.toString())))
              .toList() ??
          [];

      if (on) {
        final perms = await ConsultantLiveService.ensurePermissions();
        if (!perms) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Background location permission required to go live.'),
              backgroundColor: Colors.red,
            ));
          }
          return;
        }
        // Backend toggle (current GPS comes from clinic if not provided)
        final ok = await ref
            .read(availabilityProvider.notifier)
            .toggle(available: true);
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not toggle Go Live on the server.'),
              backgroundColor: Colors.red,
            ));
          }
          return;
        }
        await ConsultantLiveService.start(mobilityMode: mobility);
        if (schedule.isNotEmpty) {
          await ConsultantScheduleAlarm.scheduleNext(
            workingSchedule: schedule,
            mobilityMode: mobility,
          );
        }
      } else {
        await ConsultantLiveService.stop();
        await ConsultantScheduleAlarm.cancelAll();
        await ref
            .read(availabilityProvider.notifier)
            .toggle(available: false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setMobility(String mode) async {
    final ok = await ref
        .read(liveSettingsProvider.notifier)
        .save({'mobility_mode': mode});
    if (!ok || !mounted) return;
    // If service is already running, push the new cadence to it.
    if (await ConsultantLiveService.isRunning()) {
      await ConsultantLiveService.start(mobilityMode: mode);
    }
  }

  Future<void> _setRadius(int km) async {
    await ref
        .read(liveSettingsProvider.notifier)
        .save({'travel_radius_km': km});
  }

  String _summarizeSchedule(List schedule) {
    if (schedule.isEmpty) return 'No working hours set';
    final dayLabel = {
      'mon': 'Mon', 'tue': 'Tue', 'wed': 'Wed', 'thu': 'Thu',
      'fri': 'Fri', 'sat': 'Sat', 'sun': 'Sun',
    };
    final byDay = <String, List<Map>>{};
    for (final w in schedule.cast<Map>()) {
      final day = (w['day'] as String?) ?? '';
      byDay.putIfAbsent(day, () => []).add(w);
    }
    final parts = <String>[];
    for (final entry in byDay.entries) {
      final times = entry.value
          .map((w) => '${w['start']}–${w['end']}')
          .join(', ');
      parts.add('${dayLabel[entry.key] ?? entry.key} $times');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final availAsync = ref.watch(availabilityProvider);
    final settingsAsync = ref.watch(liveSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Go Live')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Big Go Live banner
          availAsync.when(
            loading: () => const _LoadingTile(),
            error: (_, __) => const _ErrorTile(text: 'Could not load status'),
            data: (avail) {
              final isLive = avail['is_available'] as bool? ?? false;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isLive
                      ? Colors.green.withOpacity(0.08)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isLive
                          ? Colors.green.withOpacity(0.4)
                          : Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      isLive ? Icons.gps_fixed : Icons.gps_off,
                      color: isLive ? Colors.green : Colors.grey[600],
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isLive ? 'You are LIVE' : 'Currently offline',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isLive
                                ? 'Doctors and clinics nearby can find you.'
                                : 'Turn on to share your location for emergency consults.',
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: isLive,
                      onChanged: _busy ? null : _toggle,
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          // Mobility mode
          settingsAsync.when(
            loading: () => const _LoadingTile(),
            error: (_, __) => const _ErrorTile(text: 'Could not load settings'),
            data: (s) {
              final mobility = (s['mobility_mode'] as String?) ?? 'mobile';
              final radius = (s['travel_radius_km'] as int?) ?? 5;
              final schedule = s['working_schedule'] as List? ?? [];
              final visibility = (s['visibility_mode'] as String?) ?? 'open';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('How do you work?'),
                  const Text(
                    'Mobile = location updates every 10 min. Stationary = every 30 min (saves battery).',
                    style: TextStyle(
                        fontSize: 12, color: MedUnityColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    value: 'mobile',
                    groupValue: mobility,
                    onChanged: (v) => v == null ? null : _setMobility(v),
                    title: const Text('Mobile (move during the day)'),
                  ),
                  RadioListTile<String>(
                    value: 'stationary',
                    groupValue: mobility,
                    onChanged: (v) => v == null ? null : _setMobility(v),
                    title: const Text('Stationary (work from one place)'),
                  ),

                  const SizedBox(height: 20),
                  const _SectionTitle('How far doctors can find you'),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: radius.toDouble(),
                          min: 1,
                          max: 50,
                          divisions: 49,
                          activeColor: MedUnityColors.primary,
                          label: '$radius km',
                          onChangeEnd: (v) => _setRadius(v.round()),
                          onChanged: (_) {},
                        ),
                      ),
                      SizedBox(
                        width: 50,
                        child: Text('$radius km',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('Working hours'),
                    subtitle: Text(_summarizeSchedule(schedule),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.push('/consultants/schedule-editor'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('Who can find you'),
                    subtitle: Text(
                        visibility == 'open'
                            ? 'Open — all matching doctors'
                            : 'Allowlist — only your approved doctors'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.push('/consultants/visibility-settings'),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 32),
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'When you are live, MedUnity shows a notification that location is being shared. '
              'Your exact location is never shown to other doctors — only used to filter who sees you nearby.',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
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
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
}

class _ErrorTile extends StatelessWidget {
  final String text;
  const _ErrorTile({required this.text});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(16), child: Text(text));
}
