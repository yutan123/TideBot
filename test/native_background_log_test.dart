import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tide_bot/app_log_service.dart';
import 'package:tide_bot/native_background_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tidebot.native.channel');

  tearDown(() async {
    await AppLogService.instance.setEnabled(false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('native logs recover after drain failure and respect disabled logging',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppLogService.instance.setEnabled(true);
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'drainBackgroundLogs');
      calls++;
      if (calls == 1) throw PlatformException(code: 'LOG_FAILED');
      return jsonEncode([
        {'time': DateTime.now().millisecondsSinceEpoch, 'message': '主动回复请求开始'}
      ]);
    });
    await NativeBackgroundCoordinator.refreshLogs();
    await NativeBackgroundCoordinator.refreshLogs();
    expect(
        AppLogService.instance.entries.any((entry) =>
            entry.level == 'PROACTIVE_NATIVE' &&
            entry.message.contains('主动回复请求开始')),
        isTrue);
    await AppLogService.instance.setEnabled(false);
    await NativeBackgroundCoordinator.refreshLogs();
    expect(calls, 2);
  });
  test(
      'keeps complete request context, original time and levels without polling noise',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppLogService.instance.setEnabled(true);
    final now = DateTime.now().millisecondsSinceEpoch;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => '''[
      {"time":${now + 1000},"message":"任务开始：vitals:bot"},
      {"time":${now + 2000},"message":"任务结束：status=success"},
      {"time":${now + 2500},"message":"主动回复已安排：bot=bot"},
      {"time":${now + 3000},"level":"PROACTIVE_REQUEST","message":"完整请求：system 人设，上下文 user 提问，tools choose_silence，Bearer secret123"},
      {"time":${now + 4000},"level":"PROACTIVE_NATIVE","message":"主动回复结束：sent"}
    ]''');
    await NativeBackgroundCoordinator.refreshLogs();
    final native = AppLogService.instance.entries
        .where((entry) => entry.level.startsWith('PROACTIVE'))
        .toList();
    expect(native, hasLength(2));
    expect(native.first.level, 'PROACTIVE_REQUEST');
    expect(native.first.time.millisecondsSinceEpoch, now + 3000);
    expect(native.first.message,
        contains('system 人设，上下文 user 提问，tools choose_silence'));
    expect(native.first.message, isNot(contains('secret123')));
    expect(native.first.message, isNot(contains('[1970')));
    expect(native.last.time.millisecondsSinceEpoch, now + 4000);
  });
  test('drops queued logs before enabling and retains new logs', () async {
    SharedPreferences.setMockInitialValues({});
    final oldTime = DateTime.now().subtract(const Duration(days: 1));
    await AppLogService.instance.setEnabled(true);
    final boundary = AppLogService.instance.entries.first.time;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => jsonEncode([
                  {'time': oldTime.millisecondsSinceEpoch, 'message': '旧异常'},
                  {'time': boundary.millisecondsSinceEpoch, 'message': '开启边界'},
                  {
                    'time': DateTime.now().millisecondsSinceEpoch,
                    'message': '新记录'
                  },
                ]));
    await NativeBackgroundCoordinator.refreshLogs();
    final messages = AppLogService.instance.entries.map((e) => e.message);
    expect(messages, isNot(contains('旧异常')));
    expect(messages, containsAll(['开启边界', '新记录']));
  });

  test('late native batch cannot leak into a reopened logging session',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppLogService.instance.setEnabled(true);
    final previous = DateTime.now().subtract(const Duration(days: 1));
    final batch = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => batch.future);
    final refresh = NativeBackgroundCoordinator.refreshLogs();
    await Future<void>.delayed(Duration.zero);
    await AppLogService.instance.setEnabled(false);
    await AppLogService.instance.setEnabled(true);
    batch.complete(jsonEncode([
      {'time': previous.millisecondsSinceEpoch, 'message': '上一轮记录'},
      {'time': DateTime.now().millisecondsSinceEpoch, 'message': '本轮记录'},
    ]));
    await refresh;
    final messages = AppLogService.instance.entries.map((e) => e.message);
    expect(messages, isNot(contains('上一轮记录')));
    expect(messages, contains('本轮记录'));
  });
}
