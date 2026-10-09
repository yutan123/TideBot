import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_request_context.dart';
import 'package:tide_bot/holiday_calendar_service.dart';
import 'package:tide_bot/ops.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only last three messages contribute thoughts', () {
    final history = <Map<String, dynamic>>[
      {'role': 'assistant', 'inner_thought': '旧独白'},
      {'role': 'user'},
      {'role': 'assistant'},
      {'role': 'user'},
    ];
    expect(recentMessageThoughts(history), isEmpty);
    history.add({'role': 'assistant', 'inner_thought': ' 新独白 '});
    expect(recentMessageThoughts(history), ['新独白']);
  });
  test('memory time uses recorded timestamp, not update time', () {
    final stamp = DateTime(2026, 9, 25, 10, 30).millisecondsSinceEpoch;
    expect(memoryRecordedTime({'timestamp': stamp, 'updated_at': stamp + 1000}),
        DateTime(2026, 9, 25, 10, 30).toIso8601String());
    expect(memoryRecordedTime({}), '未知');
  });
  test('days off do not become festivals and lunar dates are exact', () {
    String line(DateTime now, String date) =>
        HolidayCalendarService.contextFor(now)
            .split('；')
            .firstWhere((s) => s.contains(date));
    expect(line(DateTime(2026, 10, 2), '2026-10-02'), isNot(contains('国庆节')));
    expect(line(DateTime(2026, 10, 1), '2026-10-01'), contains('国庆节'));
    expect(line(DateTime(2025, 10, 1), '2025-10-01'), isNot(contains('中秋节')));
    expect(line(DateTime(2025, 10, 6), '2025-10-06'), contains('中秋节'));
    expect(line(DateTime(2026, 4, 5), '2026-04-05'), contains('清明节'));
    expect(line(DateTime(2026, 2, 18), '2026-02-18'), isNot(contains('春节')));
  });
  test('daily wake passes repeat flag to native application alarm', () async {
    const channel = MethodChannel('tidebot.native.channel');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect(
        await OpsManager()
            .setSystemAlarm(0, 0, 'TideBot 日记补写', repeating: true),
        isTrue);
    expect(calls.single.method, 'scheduleFutureTask');
    expect(calls.single.arguments['repeating'], isTrue);
    final target = DateTime.fromMillisecondsSinceEpoch(
        calls.single.arguments['triggerAt']);
    expect(target.hour, 0);
    expect(target.minute, 0);
    expect(target.isAfter(DateTime.now()), isTrue);
  });
}
