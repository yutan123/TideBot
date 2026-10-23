import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/request_execution_lease.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tidebot.native.channel');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'beginRequestExecution' ||
          call.method == 'renewRequestExecution') {
        return {'foreground': true};
      }
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('overlapping requests retain distinct ownership and release once',
      () async {
    final first = await RequestExecutionLease.acquire();
    final second = await RequestExecutionLease.acquire();
    final starts =
        calls.where((c) => c.method == 'beginRequestExecution').toList();
    expect(starts[0].arguments['id'], isNot(starts[1].arguments['id']));
    await first.release();
    await first.release();
    expect(calls.where((c) => c.method == 'endRequestExecution'), hasLength(1));
    await second.release();
    expect(calls.where((c) => c.method == 'endRequestExecution'), hasLength(2));
    expect(calls.map((c) => c.method), [
      'beginRequestExecution',
      'beginRequestExecution',
      'synchronizeBackgroundTasks',
      'endRequestExecution',
      'synchronizeBackgroundTasks',
      'endRequestExecution',
    ]);
  });

  testWidgets('renews long requests and stops renewal after completion',
      (tester) async {
    final pending = RequestExecutionLease.acquire();
    await tester.pump();
    final lease = await pending;
    await tester.pump(const Duration(minutes: 1));
    expect(
        calls.where((c) => c.method == 'renewRequestExecution'), hasLength(1));
    final release = lease.release();
    await tester.pump();
    await release;
    await tester.pump(const Duration(minutes: 2));
    expect(
        calls.where((c) => c.method == 'renewRequestExecution'), hasLength(1));
    debugDefaultTargetPlatformOverride = null;
  });

  test('promotion rejection does not fail the model request', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'REQUEST_PROTECTION_FAILED');
    });
    final lease = await RequestExecutionLease.acquire();
    await lease.release();
    expect(calls.map((c) => c.method), ['beginRequestExecution']);
  });

  test('failed deadline handoff still releases protection', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'synchronizeBackgroundTasks') {
        throw PlatformException(code: 'SYNC_FAILED');
      }
      return null;
    });
    final lease = await RequestExecutionLease.acquire();
    await lease.release();
    expect(calls.last.method, 'endRequestExecution');
  });

  test('non-Android requests do not start a native service', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final lease = await RequestExecutionLease.acquire();
    await lease.release();
    expect(calls, isEmpty);
  });
  test('acquire waits for native foreground readiness before returning',
      () async {
    final ready = Completer<Map<String, bool>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'beginRequestExecution') return ready.future;
      return null;
    });
    var acquired = false;
    final pending = RequestExecutionLease.acquire().then((lease) {
      acquired = true;
      return lease;
    });
    await Future<void>.delayed(Duration.zero);
    expect(acquired, isFalse);
    ready.complete({'foreground': true});
    final lease = await pending;
    expect(acquired, isTrue);
    await lease.release();
  });

  test('background and resume renew only live requests', () async {
    final lease = await RequestExecutionLease.acquire();
    final binding = WidgetsBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(
        calls.where((c) => c.method == 'renewRequestExecution'), hasLength(2));
    await lease.release();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(
        calls.where((c) => c.method == 'renewRequestExecution'), hasLength(2));
  });

  test('renewal failure does not prevent final release', () async {
    final lease = await RequestExecutionLease.acquire();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'renewRequestExecution') {
        throw PlatformException(code: 'REQUEST_PROTECTION_FAILED');
      }
      return null;
    });
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    await lease.release();
    expect(calls.last.method, 'endRequestExecution');
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
