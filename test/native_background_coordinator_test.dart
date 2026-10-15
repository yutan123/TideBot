import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/native_background_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tidebot.native.channel');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('coalesces synchronization bursts and drains changes during a request',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var calls = 0;
    Future<void>? queued;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'synchronizeBackgroundTasks');
      calls++;
      if (calls == 1) queued = NativeBackgroundCoordinator.synchronize();
      return null;
    });
    await Future.wait(
        List.generate(8, (_) => NativeBackgroundCoordinator.synchronize()));
    await queued;
    expect(calls, 2);
  });

  test('a channel failure does not prevent the next synchronization', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      calls++;
      if (calls == 1) throw PlatformException(code: 'SYNC_FAILED');
      return null;
    });
    await NativeBackgroundCoordinator.synchronize();
    await NativeBackgroundCoordinator.synchronize();
    expect(calls, 2);
  });
}
