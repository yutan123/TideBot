import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_typing_state.dart';

void main() {
  late ChatTypingState state;
  setUp(() => state = ChatTypingState());
  tearDown(() => state.dispose());

  test('a new process has no activity even when an old process had a request',
      () {
    final oldProcess = ChatTypingState();
    oldProcess.begin('bot');
    expect(oldProcess.isTyping('bot'), isTrue);
    expect(state.isTyping('bot'), isFalse);
    oldProcess.dispose();
  });

  test('completion clears typing synchronously and close is idempotent', () {
    final lease = state.begin('bot');
    expect(state.isTyping('bot'), isTrue);
    lease.close();
    lease.close();
    expect(lease.isClosed, isTrue);
    expect(state.isTyping('bot'), isFalse);
  });

  test('old request completion cannot clear another active request', () {
    final first = state.begin('bot');
    final second = state.begin('bot');
    first.close();
    expect(state.isTyping('bot'), isTrue);
    second.close();
    expect(state.isTyping('bot'), isFalse);
  });

  test('bots have independent typing states', () {
    final first = state.begin('a');
    state.begin('b');
    first.close();
    expect(state.isTyping('a'), isFalse);
    expect(state.isTyping('b'), isTrue);
  });

  test('failure still releases the activity in finally', () async {
    Future<void> failedRequest() async {
      final lease = state.begin('bot');
      try {
        throw StateError('network failure');
      } finally {
        lease.close();
      }
    }

    await expectLater(failedRequest(), throwsStateError);
    expect(state.isTyping('bot'), isFalse);
  });

  testWidgets('abandoned activity expires without clearing a newer request',
      (tester) async {
    final old = state.begin('bot', lifetime: const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    final current = state.begin('bot', lifetime: const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(old.isClosed, isTrue);
    expect(state.isTyping('bot'), isTrue);
    old.close();
    expect(state.isTyping('bot'), isTrue);
    await tester.pump(const Duration(seconds: 4));
    expect(current.isClosed, isTrue);
    expect(state.isTyping('bot'), isFalse);
  });

  testWidgets('a reopened page observes the live request and its completion',
      (tester) async {
    final lease = state.begin('bot');
    Widget page() => MaterialApp(
            home: ListenableBuilder(
          listenable: state,
          builder: (_, __) => Text(state.isTyping('bot') ? 'typing' : 'idle'),
        ));
    await tester.pumpWidget(page());
    expect(find.text('typing'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    expect(find.text('typing'), findsOneWidget);
    lease.close();
    await tester.pump();
    expect(find.text('typing'), findsNothing);
    expect(find.text('idle'), findsOneWidget);
  });

  test('chat page never reads or writes the legacy persisted typing flag', () {
    final source = File('lib/ui_chat_room.dart').readAsStringSync();
    expect(source, isNot(contains(r"'chat_typing_$")));
    expect(source, contains('ChatTypingState.instance.addListener'));
    expect(source, contains('ChatTypingState.instance.removeListener'));
    expect(source, isNot(contains('await _setTypingState')));
    expect(
        source,
        contains(
            '// Always release, including an early return/failed handoff'));
  });
}
