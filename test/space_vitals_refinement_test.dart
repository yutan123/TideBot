import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/bot_vital_model.dart';
import 'package:tide_bot/bot_data_page.dart';
import 'package:tide_bot/daily_quote_output.dart';
import 'package:tide_bot/sleep_timeline.dart';
import 'package:tide_bot/theme.dart';
import 'package:tide_bot/world_book_preview_window.dart';

void main() {
  group('single daily quote', () {
    test('one quote survives unchanged', () {
      expect(singleDailyQuote('慢慢来，也能走得很远。'), '慢慢来，也能走得很远。');
    });
    test('multiple lines and numbered alternatives become one', () {
      expect(singleDailyQuote('今日一言：\n1. 慢慢来。\n2. 向前走。'), '慢慢来。');
      expect(singleDailyQuote('慢慢来。也要向前走。'), '慢慢来。');
      expect(singleDailyQuote('第一条|||第二条'), '第一条');
    });
    test('thoughts and decorative quotes never leak', () {
      expect(singleDailyQuote('<inner_thought>给出两条</inner_thought>\n「慢慢来。」'),
          '慢慢来。');
      expect(singleDailyQuote(' \n '), isNotEmpty);
    });
  });
  group('hourly average heart rate', () {
    int rate(
            {bool asleep = false,
            String activity = '休息',
            double stress = 3,
            double quality = 85,
            double temperature = 36.5,
            double previous = 72}) =>
        hourlyMeanHeartRate(
            previous: previous,
            asleep: asleep,
            activity: activity,
            stress: stress,
            sleepQuality: quality,
            temperature: temperature,
            noise: 0);
    test('sleep lowers the mean; exercise raises it without abrupt jumps', () {
      expect(rate(asleep: true), lessThan(rate()));
      expect(rate(activity: '跑步运动'), greaterThan(rate()));
      expect((rate(activity: '跑步运动') - 72).abs(), lessThanOrEqualTo(14));
    });
    test('stress, poor sleep and fever affect the hourly mean', () {
      expect(rate(stress: 9), greaterThan(rate()));
      expect(rate(quality: 45), greaterThan(rate()));
      expect(rate(temperature: 38.2), greaterThan(rate()));
    });
    test('long simulation stays bounded and gradual', () {
      var previous = 72.0;
      for (var i = 0; i < 1000; i++) {
        final next = rate(
            asleep: i % 24 < 7,
            activity: '运动',
            temperature: 38.5,
            previous: previous);
        expect(next, inInclusiveRange(45, 135));
        expect((next - previous).abs(), lessThanOrEqualTo(14));
        previous = next.toDouble();
      }
    });
    test('edited heart rate does not revert to defaults', () {
      for (final initial in [48.0, 95.0, 120.0, 132.0]) {
        var current = initial;
        for (var hour = 0; hour < 48; hour++) {
          current = rate(previous: current).toDouble();
        }
        expect(current, initial);
      }
    });
    test('temperature continues from the saved value', () {
      expect(nextBodyTemperature(38.5, sick: false, noise: 0), 38.5);
      expect(nextBodyTemperature(35.5, sick: false, noise: 1),
          closeTo(35.6, .001));
      expect(
          nextBodyTemperature(38.5, sick: true, noise: 0), closeTo(38.6, .001));
    });
    test('heart charts retain each hourly sample, weight stays daily', () {
      final now = DateTime.now();
      final data = <String, dynamic>{
        'samples': [
          {
            'time':
                now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
            'day': 'today',
            'heart': 65,
            'weight': 50
          },
          {
            'time': now.millisecondsSinceEpoch,
            'day': 'today',
            'heart': 78,
            'weight': 50
          },
        ]
      };
      expect(metricPoints(data, 3, body: 'heart').length, 2);
      expect(metricPoints(data, 3, body: 'weight').length, 1);
    });
  });
  Widget host(Widget child, {double scale = 1}) => TideBotThemeProvider(
        theme: TideTheme(),
        child: MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: SingleChildScrollView(
                  child: SizedBox(width: 320, child: child))),
        )),
      );
  testWidgets(
      'sleep timeline uses geometric marks and selects a short awakening',
      (tester) async {
    Map<String, dynamic>? selected;
    final start = DateTime(2026, 10, 14, 23).millisecondsSinceEpoch;
    final segments = <Map<String, dynamic>>[
      {'start': start, 'end': start + 3600000, 'state': '睡眠'},
      {'start': start + 3600000, 'end': start + 3660000, 'state': '清醒'},
      {'start': start + 3660000, 'end': start + 7200000, 'state': '睡眠'},
    ];
    await tester.pumpWidget(
        host(SleepTimeline(segments: segments, onSelect: (s) => selected = s)));
    expect(find.byIcon(Icons.bedtime_rounded), findsNothing);
    expect(find.byIcon(Icons.wb_sunny_rounded), findsNothing);
    expect(find.byType(SleepStateMark), findsNWidgets(2));
    final track = find.descendant(
        of: find.byType(SleepTimeline), matching: find.byType(CustomPaint));
    final rect = tester.getRect(track);
    await tester.tapAt(Offset(
        rect.left + 4 + (rect.width - 8) * 3630000 / 7200000, rect.center.dy));
    expect(selected?['state'], '清醒');
    expect(tester.takeException(), isNull);
  });
  testWidgets('world book adapts to large fonts and changing entry heights',
      (tester) async {
    final memories = <Map<String, dynamic>>[
      {'content': '短条目', 'timestamp': 1},
      {'content': '很长的条目内容' * 15, 'timestamp': 2},
      {'content': '第三条世界书内容', 'timestamp': 3},
      {'content': '最后一条', 'timestamp': 4},
    ];
    Widget preview(int start) => host(
        WorldBookPreviewWindow(
            memories: memories,
            startIndex: start,
            onSelect: (_) {},
            formatTimestamp: (t) => '10月15日 16:18'),
        scale: 2);
    await tester.pumpWidget(preview(0));
    final stamps = find.text('10月15日 16:18');
    final dividers = find.byType(Divider);
    expect(tester.getBottomLeft(stamps.at(0)).dy,
        lessThan(tester.getTopLeft(dividers.at(0)).dy));
    expect(tester.getBottomLeft(stamps.at(1)).dy,
        lessThan(tester.getTopLeft(dividers.at(1)).dy));
    await tester.pumpWidget(preview(1));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
  });
}
