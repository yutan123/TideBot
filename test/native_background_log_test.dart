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
      return '[{"time":1000,"message":"主动回复请求开始"}]';
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => '''[
      {"time":1000,"message":"任务开始：vitals:bot"},
      {"time":2000,"message":"任务结束：status=success"},
      {"time":2500,"message":"主动回复已安排：bot=bot"},
      {"time":3000,"level":"PROACTIVE_REQUEST","message":"完整请求：system 人设，上下文 user 提问，tools choose_silence，Bearer secret123"},
      {"time":4000,"level":"PROACTIVE_NATIVE","message":"主动回复结束：sent"}
    ]''');
    await NativeBackgroundCoordinator.refreshLogs();
    final native = AppLogService.instance.entries
        .where((entry) => entry.level.startsWith('PROACTIVE'))
        .toList();
    expect(native, hasLength(2));
    expect(native.first.level, 'PROACTIVE_REQUEST');
    expect(native.first.time.millisecondsSinceEpoch, 3000);
    expect(native.first.message,
        contains('system 人设，上下文 user 提问，tools choose_silence'));
    expect(native.first.message, isNot(contains('secret123')));
    expect(native.first.message, isNot(contains('[1970')));
    expect(native.last.time.millisecondsSinceEpoch, 4000);
  });
}
