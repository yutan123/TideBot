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
}
