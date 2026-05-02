import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';

import 'consultant_live_service.dart';

/// One-shot AlarmManager wakeups that auto-start / auto-stop the live service
/// at the boundaries of the consultant's `working_schedule`.
///
/// IST is hardcoded — matches the backend's `consultants.schedule.IST`.
class ConsultantScheduleAlarm {
  static const int _startAlarmId = 7001;
  static const int _stopAlarmId = 7002;

  static const Map<String, int> _dayIndex = {
    'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
  };

  static Future<void> initialize() async {
    await AndroidAlarmManager.initialize();
  }

  /// Cancel any pending start/stop alarms.
  static Future<void> cancelAll() async {
    await AndroidAlarmManager.cancel(_startAlarmId);
    await AndroidAlarmManager.cancel(_stopAlarmId);
  }

  /// Compute and register the next start/stop alarm pair.
  /// Schedule shape: `[{day:'mon', start:'11:00', end:'17:00'}, ...]`
  /// Mobility mode is passed through so the started service knows its cadence.
  static Future<void> scheduleNext({
    required List<Map<String, String>> workingSchedule,
    required String mobilityMode,
  }) async {
    await cancelAll();
    if (workingSchedule.isEmpty) return;

    final nextStart = _nextWindowStart(workingSchedule);
    if (nextStart == null) return;
    final matchingEnd = _matchingEnd(workingSchedule, nextStart);

    await AndroidAlarmManager.oneShotAt(
      nextStart,
      _startAlarmId,
      _onScheduleStart,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      params: {'mobility_mode': mobilityMode},
    );
    if (matchingEnd != null) {
      await AndroidAlarmManager.oneShotAt(
        matchingEnd,
        _stopAlarmId,
        _onScheduleStop,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
    }
  }

  // ── Date math (IST) ─────────────────────────────────────────────────────────

  static DateTime _nowIst() => DateTime.now().toUtc().add(const Duration(
        hours: 5, minutes: 30,
      ));

  static DateTime? _nextWindowStart(List<Map<String, String>> schedule) {
    final nowIst = _nowIst();
    DateTime? best;
    for (final w in schedule) {
      final dayKey = (w['day'] ?? '').toLowerCase();
      final dayIdx = _dayIndex[dayKey];
      if (dayIdx == null) continue;
      final start = _parseHHmm(w['start']);
      if (start == null) continue;

      var candidate = DateTime(nowIst.year, nowIst.month, nowIst.day,
          start.hour, start.minute);
      // Walk forward to the matching weekday
      while (candidate.weekday != dayIdx || !candidate.isAfter(nowIst)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      // Convert IST candidate to local-equivalent absolute UTC instant the alarm
      // will fire at — AndroidAlarmManager uses the device's local zone which is
      // usually IST anyway, but we normalise to be safe.
      final ist = candidate.toUtc().subtract(const Duration(hours: 5, minutes: 30));
      final localFire = ist.toLocal();
      if (best == null || localFire.isBefore(best)) best = localFire;
    }
    return best;
  }

  static DateTime? _matchingEnd(
    List<Map<String, String>> schedule,
    DateTime startInLocal,
  ) {
    // Convert local fire-time back to IST weekday for matching.
    final ist = startInLocal.toUtc().add(const Duration(hours: 5, minutes: 30));
    for (final w in schedule) {
      final dayKey = (w['day'] ?? '').toLowerCase();
      final dayIdx = _dayIndex[dayKey];
      if (dayIdx == null || dayIdx != ist.weekday) continue;
      final start = _parseHHmm(w['start']);
      if (start == null || start.hour != ist.hour || start.minute != ist.minute) {
        continue;
      }
      final end = _parseHHmm(w['end']);
      if (end == null) return null;
      final endIst = DateTime(ist.year, ist.month, ist.day, end.hour, end.minute);
      return endIst.toUtc().subtract(const Duration(hours: 5, minutes: 30)).toLocal();
    }
    return null;
  }

  static _Hm? _parseHHmm(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return _Hm(h, m);
  }
}

class _Hm {
  final int hour;
  final int minute;
  _Hm(this.hour, this.minute);
}

// ── Top-level alarm callbacks (must be entry points for AOT) ─────────────────

@pragma('vm:entry-point')
Future<void> _onScheduleStart(int id, Map<String, dynamic> params) async {
  final mode = (params['mobility_mode'] as String?) ?? 'mobile';
  if (kDebugMode) {
    // ignore: avoid_print
    print('ConsultantScheduleAlarm: window start fired ($mode)');
  }
  await ConsultantLiveService.start(mobilityMode: mode);
}

@pragma('vm:entry-point')
Future<void> _onScheduleStop(int id, Map<String, dynamic> params) async {
  if (kDebugMode) {
    // ignore: avoid_print
    print('ConsultantScheduleAlarm: window end fired');
  }
  await ConsultantLiveService.stop();
}
