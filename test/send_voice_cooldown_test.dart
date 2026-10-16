import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/send_voice_cooldown.dart';

void main() {
  testWidgets('voice is blocked immediately, then unlocked at two seconds',
      (tester) async {
    final cooldown = SendVoiceCooldown();
    addTearDown(cooldown.dispose);
    expect(cooldown.isBlocked, isFalse);
    cooldown.markSend();
    expect(cooldown.isBlocked, isTrue);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(cooldown.isBlocked, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(cooldown.isBlocked, isFalse);
  });

  testWidgets('another send restarts the two second window', (tester) async {
    final cooldown = SendVoiceCooldown();
    addTearDown(cooldown.dispose);
    cooldown.markSend();
    await tester.pump(const Duration(seconds: 1));
    cooldown.markSend();
    await tester.pump(const Duration(seconds: 1));
    expect(cooldown.isBlocked, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(cooldown.isBlocked, isFalse);
  });

  testWidgets('a rapid second tap after Send changes to Mic cannot record',
      (tester) async {
    final cooldown = SendVoiceCooldown();
    addTearDown(cooldown.dispose);
    var sent = false;
    var recordings = 0;
    await tester.pumpWidget(MaterialApp(
        home: ListenableBuilder(
      listenable: cooldown,
      builder: (_, __) => Center(
          child: IconButton(
        icon: Icon(sent ? Icons.mic : Icons.send),
        onPressed: !sent
            ? () {
                sent = true;
                cooldown.markSend();
              }
            : cooldown.isBlocked
                ? null
                : () => recordings++,
      )),
    )));
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    expect(recordings, 0);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byType(IconButton));
    expect(recordings, 1);
  });

  testWidgets('disposal cancels the timer and never notifies a dead page',
      (tester) async {
    final cooldown = SendVoiceCooldown();
    var notifications = 0;
    cooldown.addListener(() => notifications++);
    cooldown.markSend();
    expect(notifications, 1);
    cooldown.dispose();
    await tester.pump(const Duration(seconds: 3));
    expect(notifications, 1);
  });
}
