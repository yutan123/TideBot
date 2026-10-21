import 'dart:math';

int vitalInt(dynamic value, [int fallback = 0]) =>
    (value is num ? value.toInt() : int.tryParse('$value')) ?? fallback;
double vitalDouble(dynamic value, [double fallback = 0]) =>
    (value is num ? value.toDouble() : double.tryParse('$value')) ?? fallback;
List<Map<String, dynamic>> vitalList(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];

/// Calendar time, including an explicitly marked following day.
DateTime? vitalTime(String day, String clock) {
  final match =
      RegExp(r'^(次日)?([01]\d|2[0-3]):([0-5]\d)$').firstMatch(clock.trim());
  final date = DateTime.tryParse(day);
  if (match == null || date == null) return null;
  return DateTime(date.year, date.month, date.day + (match[1] == null ? 0 : 1),
      int.parse(match[2]!), int.parse(match[3]!));
}

/// Merge intersecting awake intervals before subtracting them from sleep.
List<Map<String, dynamic>> sleepSegments(Map<String, dynamic> sleep,
    {int? until}) {
  final start = vitalInt(sleep['start']);
  final end = until ?? vitalInt(sleep['end'], vitalInt(sleep['planned_end']));
  if (start <= 0 || end <= start) return [];
  final awake = vitalList(sleep['awake'])
      .map((e) => {
            ...e,
            'start': max(start, vitalInt(e['start'])),
            'end': min(end, vitalInt(e['end']))
          })
      .where((e) => vitalInt(e['end']) > vitalInt(e['start']))
      .toList()
    ..sort((a, b) => vitalInt(a['start']).compareTo(vitalInt(b['start'])));
  final merged = <Map<String, dynamic>>[];
  for (final item in awake) {
    if (merged.isNotEmpty &&
        vitalInt(item['start']) <= vitalInt(merged.last['end'])) {
      merged.last['end'] =
          max(vitalInt(merged.last['end']), vitalInt(item['end']));
      if (merged.last['reason'] != item['reason'])
        merged.last['reason'] = '短暂清醒与聊天';
    } else {
      merged.add(Map.of(item));
    }
  }
  final result = <Map<String, dynamic>>[];
  var cursor = start;
  for (final item in merged) {
    if (vitalInt(item['start']) > cursor)
      result.add({
        'start': cursor,
        'end': item['start'],
        'state': '睡眠',
        'reason': '连续睡眠'
      });
    result.add({...item, 'state': '清醒'});
    cursor = vitalInt(item['end']);
  }
  if (cursor < end)
    result.add({'start': cursor, 'end': end, 'state': '睡眠', 'reason': '连续睡眠'});
  return result;
}

/// Guidance uses this sleep session, so midnight does not reset awakenings.
String sleepReplyGuidance(Map<String, dynamic> sleep, {required int now}) {
  final end =
      min(now + 1, vitalInt(sleep['end'], vitalInt(sleep['planned_end'])));
  final count = sleepSegments(sleep, until: end)
      .where((segment) => segment['state'] == '清醒')
      .length;
  final caution = count >= 2
      ? '当晚清醒次数过多，不建议回复；除非确有必要必须回复，否则建议选择不回复，调用 choose_silence，不输出正文。危机与紧急求助仍应及时回应。'
      : '';
  return '\n【睡眠期间】现在是你的睡觉时间。对方发来了消息，你可以直接自然回复，也可以不回复；不回复必须调用 choose_silence，不输出正文。回复后短暂清醒，之后继续睡。当晚已清醒$count次。$caution不需要解释系统规则。';
}

Map<String, dynamic> settleSleep(Map<String, dynamic> sleep) {
  final segments = sleepSegments(sleep);
  int minutes(String kind) => segments.where((e) => e['state'] == kind).fold(
      0, (s, e) => s + (vitalInt(e['end']) - vitalInt(e['start'])) ~/ 60000);
  final slept = minutes('睡眠');
  final awake = minutes('清醒');
  final interruptions = segments.where((e) => e['state'] == '清醒').length;
  final score = (100 -
          max(0, 420 - slept) / 7 -
          max(0, slept - 540) / 15 -
          awake * .35 -
          interruptions * 4)
      .round()
      .clamp(0, 100);
  return {
    ...sleep,
    'minutes': slept,
    'awake_minutes': awake,
    'quality': score,
    'segments': segments
  };
}

/// Sample each schedule block once, then distribute it over its hours.
List<Map<String, dynamic>> stepPlan(
    String day, List<Map<String, dynamic>> timeline, Random random) {
  final result = <Map<String, dynamic>>[];
  for (var i = 0; i < timeline.length; i++) {
    final item = timeline[i];
    final start = vitalTime(day, '${item['time']}');
    var end = vitalTime(day, '${item['end_time']}');
    if (start == null || end == null) continue;
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    final planned = max(0, vitalInt(item['steps']));
    final sleeping = '${item['activity']}'.contains('睡');
    final steps = sleeping || planned == 0
        ? 0
        : max(0, planned + random.nextInt(401) - 200);
    result.add({
      'id': '$day:$i',
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'steps': steps,
      'planned': planned,
      'activity': item['activity']
    });
  }
  return result;
}

/// Continue from the latest value without reverting to an initial baseline.
int hourlyMeanHeartRate(
    {required double previous,
    required bool asleep,
    required String activity,
    required double stress,
    required double sleepQuality,
    required double temperature,
    required double noise}) {
  final exertion = RegExp('跑步|健身|运动|骑行|游泳|球').hasMatch(activity)
      ? 24.0
      : RegExp('散步|步行|逛街|通勤').hasMatch(activity)
          ? 9.0
          : 0.0;
  final change = (asleep ? -1.0 : exertion / 12) +
      (asleep ? 0 : (stress.clamp(0, 10) - 3) * .25) +
      (sleepQuality < 60 && !asleep ? 1 : 0) +
      max(0.0, temperature - 37) * .8 +
      noise.clamp(-2, 2);
  return (previous + change.clamp(-4, 4)).clamp(45, 135).round();
}

/// Daily temperature continues from the saved value with small changes.
double nextBodyTemperature(double previous,
        {required bool sick, required double noise}) =>
    (previous + noise.clamp(-1, 1) * .1 + (sick ? .1 : 0))
        .clamp(34, 42)
        .toDouble();
