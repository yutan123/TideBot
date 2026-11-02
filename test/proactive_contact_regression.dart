import 'package:tide_bot/proactive_contact.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final evening = buildProactiveContactTurn(
    now: DateTime(2026, 11, 1, 23, 59, 59),
    unansweredCount: 0,
    trigger: '定时联系',
  );
  final morning = buildProactiveContactTurn(
    now: DateTime(2026, 11, 2, 8),
    unansweredCount: 2,
    trigger: '已授权事件：提醒',
  );
  check(evening.contains('2026-11-01 23:59:59'), 'Evening clock');
  check(evening.contains('星期日'), 'Evening weekday');
  check(morning.contains('2026-11-02 08:00:00'), 'Refresh after midnight');
  check(morning.contains('星期一'), 'Refresh weekday');
  check(morning.contains('UTC'), 'Include local timezone');
  check(morning.contains('2 次'), 'Supply unanswered count');
  check(morning.contains('请更克制'), 'Adapt unanswered contact');
  check(!evening.contains('请更克制'), 'First contact has no unanswered warning');
  check(morning.contains('已授权事件：提醒'), 'Preserve trigger constraints');
  check(morning.contains('不是用户发言'), 'Identify synthetic task');
  check(
    buildProactiveContactTurn(
      now: DateTime(2026, 11, 2),
      unansweredCount: -1,
      trigger: '',
    ).contains('0 次'),
    'Normalize invalid count',
  );
  print(
    'PASS: proactive runtime date, midnight rollover, weekday, timezone, '
    'unanswered state and trigger preservation',
  );
}
