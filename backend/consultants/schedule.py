"""Working-schedule evaluator.

A consultant's `working_schedule` is a list of weekly windows:

    [
      {'day': 'mon', 'start': '11:00', 'end': '17:00'},
      {'day': 'tue', 'start': '11:00', 'end': '17:00'},
      ...
    ]

IST is hardcoded for MVP — revisit if MedUnity expands beyond India.
"""

from datetime import datetime, time, timedelta, timezone

IST = timezone(timedelta(hours=5, minutes=30))

DAY_INDEX = {
    'mon': 0, 'tue': 1, 'wed': 2, 'thu': 3, 'fri': 4, 'sat': 5, 'sun': 6,
}


def _parse_hhmm(s: str) -> time | None:
    try:
        h, m = s.split(':')
        return time(int(h), int(m))
    except (ValueError, AttributeError):
        return None


def is_within_schedule(schedule: list, now: datetime | None = None) -> bool:
    """Return True if `now` (or current IST time) falls in any schedule window."""
    if not schedule:
        return False
    now_ist = (now or datetime.now(IST)).astimezone(IST)
    today_idx = now_ist.weekday()
    now_t = now_ist.time()
    for window in schedule:
        day = window.get('day', '').lower()
        if DAY_INDEX.get(day) != today_idx:
            continue
        start = _parse_hhmm(window.get('start', ''))
        end = _parse_hhmm(window.get('end', ''))
        if not start or not end:
            continue
        if start <= now_t < end:
            return True
    return False


def next_window_start(schedule: list, after: datetime | None = None) -> datetime | None:
    """Return the next datetime (IST) when a schedule window opens, or None.

    Used by the Flutter alarm scheduler to decide when to wake up next.
    """
    if not schedule:
        return None
    after_ist = (after or datetime.now(IST)).astimezone(IST)
    candidates: list[datetime] = []
    for window in schedule:
        day = window.get('day', '').lower()
        day_idx = DAY_INDEX.get(day)
        if day_idx is None:
            continue
        start = _parse_hhmm(window.get('start', ''))
        if not start:
            continue
        days_ahead = (day_idx - after_ist.weekday()) % 7
        candidate = after_ist.replace(
            hour=start.hour, minute=start.minute, second=0, microsecond=0,
        ) + timedelta(days=days_ahead)
        if candidate <= after_ist:
            candidate += timedelta(days=7)
        candidates.append(candidate)
    return min(candidates) if candidates else None


def validate_schedule(schedule) -> list:
    """Normalize and validate a schedule payload. Returns cleaned list.

    Raises ValueError on bad input.
    """
    if schedule is None:
        return []
    if not isinstance(schedule, list):
        raise ValueError('schedule must be a list')
    cleaned = []
    for w in schedule:
        if not isinstance(w, dict):
            raise ValueError('schedule entries must be objects')
        day = (w.get('day') or '').lower()
        if day not in DAY_INDEX:
            raise ValueError(f'unknown day: {day!r}')
        start = _parse_hhmm(w.get('start', ''))
        end = _parse_hhmm(w.get('end', ''))
        if not start or not end:
            raise ValueError('start/end must be HH:MM')
        if end <= start:
            raise ValueError(f'{day}: end must be after start')
        cleaned.append({
            'day': day,
            'start': start.strftime('%H:%M'),
            'end': end.strftime('%H:%M'),
        })
    return cleaned
