import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/bot_vital_model.dart';
import 'package:tide_bot/bot_data_page.dart';

void main() {
  final start = DateTime(2026, 10, 12, 23, 30).millisecondsSinceEpoch;
  final end = DateTime(2026, 10, 13, 7, 30).millisecondsSinceEpoch;
  Map<String, dynamic> night(List<Map<String, dynamic>> awake) =>
      {'start': start, 'end': end, 'planned_end': end, 'awake': awake};
  test('calendar clocks accept following day and reject invalid values', () {
    expect(vitalTime('2026-10-12', '次日07:30'), DateTime(2026, 10, 13, 7, 30));
    expect(vitalTime('2026-10-12', '24:00'), isNull);
    expect(vitalTime('bad', '07:30'), isNull);
  });
  test('uninterrupted overnight sleep totals eight hours', () {
    final settled = settleSleep(night([]));
    expect(settled['minutes'], 480);
    expect(settled['awake_minutes'], 0);
    expect(settled['quality'], 100);
  });
  test('overlapping chat and natural waking count once', () {
    final settled = settleSleep(night([
      {'start': start + 600000, 'end': start + 1200000, 'reason': '自然清醒'},
      {'start': start + 900000, 'end': start + 1800000, 'reason': '回复消息'},
    ]));
    expect(settled['awake_minutes'], 20);
    expect(settled['minutes'], 460);
    expect(
        vitalList(settled['segments']).where((e) => e['state'] == '清醒').length,
        1);
  });
  test('out of range and invalid waking intervals are clipped', () {
    final settled = settleSleep(night([
      {'start': start - 600000, 'end': start + 300000},
      {'start': end - 300000, 'end': end + 600000},
      {'start': end + 600000, 'end': end + 1200000},
      {'start': start + 1200000, 'end': start + 600000},
    ]));
    expect(settled['awake_minutes'], 10);
    expect(settled['minutes'], 470);
  });
  test('live timeline stops at the requested time', () {
    final segments = sleepSegments(night([]), until: start + 3600000);
    expect(segments.single['end'], start + 3600000);
  });
  test('step plans stay within 200 steps and keep sleep at zero', () {
    for (var seed = 0; seed < 100; seed++) {
      final plan = stepPlan(
          '2026-10-12',
          [
            {
              'time': '12:00',
              'end_time': '13:00',
              'activity': '散步',
              'steps': 1000
            },
            {
              'time': '23:30',
              'end_time': '次日07:30',
              'activity': '睡觉',
              'steps': 600
            },
          ],
          Random(seed));
      expect(plan.first['steps'], inInclusiveRange(800, 1200));
      expect(plan.last['steps'], 0);
      expect(plan.last['end'], end);
    }
  });
  test('sleep trend respects selected date range', () {
    final now = DateTime.now();
    expect(
        metricPoints({
          'sleep_history': [
            {
              'end':
                  now.subtract(const Duration(days: 40)).millisecondsSinceEpoch,
              'minutes': 480
            },
            {'end': now.millisecondsSinceEpoch, 'minutes': 450},
          ]
        }, 0, days: 7)
            .length,
        1);
  });
  test('today step curve retains hourly progress', () {
    final now = DateTime.now();
    final time = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final data = {
      'samples': [
        {'time': time, 'day': 'today', 'steps': 0},
        {'time': time + 3600000, 'day': 'today', 'steps': 1000},
      ]
    };
    expect(metricPoints(data, 4, days: 1).length, 2);
    expect(metricPoints(data, 4, days: 7).length, 1);
  });
  testWidgets('six compact square cards fit a narrow screen', (tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
        child: SizedBox.square(
            dimension: 136,
            child: VitalMetricCard(data: const {
              'weight': 68,
              'steps': 10000,
              'health': '康复中',
              'illness': '轻微肠胃不适'
            }, index: i)),
      ))));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'metric $i');
    }
  });
}
