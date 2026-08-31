import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tide_bot/future_task_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tidebot.native.channel');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'scheduleFutureTask') return true;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('schedules native alarms with stable task fields', () async {
    final scheduled = await FutureTaskScheduler.schedule({
      'id': 'task-1',
      'run_at': 1720000000000,
      'title': 'Review | notes',
    });

    expect(scheduled, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'scheduleFutureTask');
    expect(calls.single.arguments, {
      'taskId': 'task-1',
      'triggerAt': 1720000000000,
      'title': 'Review | notes',
    });
  });

  test('does not schedule invalid tasks', () async {
    expect(await FutureTaskScheduler.schedule(const {}), isFalse);
    expect(calls, isEmpty);
  });

  test('cancels a native alarm by task id', () async {
    await FutureTaskScheduler.cancel('task-1');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'cancelFutureTask');
    expect(calls.single.arguments, {'taskId': 'task-1'});
  });
}
