import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/life_schedule_service.dart';

void main() {
  group('life schedule response parsing', () {
    const payload =
        '{"theme":"工作日","mood":"专注","outfit":"衬衫和长裤","timeline":[{"time":"09:00","end_time":"10:00","activity":"写作"}]}';

    test('parses fenced JSON', () {
      final parsed = parseLifeSchedulePayload('```json\n$payload\n```');
      expect(parsed?['theme'], '工作日');
      expect(parsed?['timeline'], isA<List>());
    });

    test('parses JSON wrapped in a JSON string', () {
      final parsed = parseLifeSchedulePayload(jsonEncode(payload));
      expect(parsed?['mood'], '专注');
    });

    test('extracts a balanced object from surrounding text', () {
      final parsed = parseLifeSchedulePayload('结果如下：\n$payload\n生成完毕');
      expect(parsed?['outfit'], '衬衫和长裤');
    });
  });

  group('life schedule current activity', () {
    test('validates normal clock times', () {
      expect(isLifeScheduleClockTime('09:00'), isTrue);
      expect(isLifeScheduleClockTime('23:59'), isTrue);
      expect(isLifeScheduleClockTime('9:00'), isFalse);
      expect(isLifeScheduleClockTime(r'09:\d0'), isFalse);
    });

    final row = <String, dynamic>{
      'theme': '工作日',
      'mood': '专注',
      'outfit_style': '简约',
      'outfit': '衬衫和长裤',
      'timeline_json': jsonEncode([
        {
          'time': '09:00',
          'end_time': '10:00',
          'activity': '写作',
          'weather': '晴',
          'rigid': false,
        },
        {
          'time': '11:00',
          'end_time': '12:00',
          'activity': '散步',
          'weather': '晴',
          'rigid': false,
        },
        {
          'time': '23:00',
          'end_time': '次日09:00',
          'activity': '睡觉',
          'weather': '晴',
          'rigid': false,
        },
      ]),
    };

    test('does not keep an ended activity active during a gap', () {
      final context = compactLifeScheduleContext(
        row,
        at: DateTime(2026, 9, 25, 10, 30),
      );
      expect(context, contains('当前安排：当前没有安排'));
      expect(context, isNot(contains('当前安排：09:00-10:00 写作')));
    });

    test('selects an activity only inside its time interval', () {
      final context = compactLifeScheduleContext(
        row,
        at: DateTime(2026, 9, 25, 11, 30),
      );
      expect(context, contains('当前安排：11:00-12:00 散步'));
    });

    test('selects the overnight sleep entry after midnight', () {
      final context = compactLifeScheduleContext(
        row,
        at: DateTime(2026, 9, 26, 2, 0),
      );
      expect(context, contains('当前安排：23:00-次日09:00 睡觉'));
    });
  });
}
