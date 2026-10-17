import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tide_bot/chat_background_page.dart';
import 'package:tide_bot/theme.dart';

void main() {
  testWidgets('storage failure ends loading and retry attempts another read',
      (tester) async {
    databaseFactory = databaseFactorySqflitePlugin;
    var attempts = 0;
    const channel = MethodChannel('com.tekartik.sqflite');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      attempts++;
      throw PlatformException(code: 'storage_unavailable');
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(TideBotThemeProvider(
      theme: TideTheme(),
      child: const MaterialApp(home: ChatBackgroundPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('聊天背景读取失败，请重试'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    final beforeRetry = attempts;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, greaterThan(beforeRetry));
    expect(find.text('聊天背景读取失败，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
