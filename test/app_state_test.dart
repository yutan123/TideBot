import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tidebot.native.channel');
  final calls = <MethodCall>[];
  late Object owner;

  setUp(() {
    owner = Object();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    AppState.updateLifecycle(AppLifecycleState.resumed);
  });

  tearDown(() {
    AppState.hideChat(owner);
    AppState.updateLifecycle(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('home and other rooms do not suppress a bot message', () {
    expect(AppState.isViewingChat('bot-a'), isFalse);
    AppState.showChat('bot-b', owner);
    expect(AppState.isViewingChat('bot-a'), isFalse);
    expect(AppState.isViewingChat('bot-b'), isTrue);
  });

  test('background always permits alerts even with the matching room open', () {
    AppState.showChat('bot-a', owner);
    for (final lifecycle in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      AppState.updateLifecycle(lifecycle);
      expect(AppState.isViewingChat('bot-a'), isFalse, reason: '$lifecycle');
    }
    AppState.updateLifecycle(AppLifecycleState.resumed);
    expect(AppState.isViewingChat('bot-a'), isTrue);
  });

  test('covering or leaving a chat permits alerts again', () {
    AppState.showChat('bot-a', owner);
    expect(AppState.isViewingChat('bot-a'), isTrue);
    AppState.hideChat(owner);
    expect(AppState.isViewingChat('bot-a'), isFalse);
  });

  test('disposing a popped room cannot clear the room revealed underneath', () {
    final poppedOwner = Object();
    AppState.showChat('bot-a', poppedOwner);
    AppState.showChat('bot-a', owner);
    AppState.hideChat(poppedOwner);
    expect(AppState.isViewingChat('bot-a'), isTrue);
  });

  test('notifications without a valid bot are never suppressed', () {
    AppState.showChat('', owner);
    expect(AppState.isViewingChat(''), isFalse);
    expect(AppState.isViewingChat(null), isFalse);
  });

  test('chat visibility is mirrored to native delivery in navigation order',
      () async {
    AppState.showChat('bot-a', owner);
    AppState.hideChat(owner);
    await Future<void>.delayed(Duration.zero);
    expect(
        calls.map((call) => call.method), ['setVisibleChat', 'setVisibleChat']);
    expect(calls.map((call) => call.arguments), [
      {'botId': 'bot-a'},
      {'botId': null},
    ]);
  });
}
