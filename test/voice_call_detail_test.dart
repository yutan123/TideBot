import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tide_bot/chat_event_bus.dart';
import 'package:tide_bot/db.dart';
import 'package:tide_bot/theme.dart';
import 'package:tide_bot/voice_call_card.dart';
import 'package:tide_bot/voice_call_detail_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.tekartik.sqflite');
  var summary = '';
  var failRead = false;

  setUp(() {
    summary = '';
    failRead = false;
    databaseFactory = databaseFactorySqflitePlugin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map? ?? {};
      final sql = args['sql']?.toString() ?? '';
      switch (call.method) {
        case 'getDatabasesPath':
          return '/test/voice_calls';
        case 'openDatabase':
          return {'id': 1};
        case 'query':
          if (sql.contains('PRAGMA user_version')) {
            return [
              {'user_version': 34}
            ];
          }
          if (sql.contains('schema_repair_version')) {
            return [
              {'value': '36'}
            ];
          }
          if (sql.contains('FROM voice_call_records')) {
            if (failRead) throw PlatformException(code: 'storage_unavailable');
            return [
              {
                'id': 'call_test',
                'bot_id': 'bot_test',
                'status': 'ended',
                'duration': 65,
                'timestamp': 1700000000000,
                'summary': summary,
                'transcript': '用户：明天一起看电影\n机器人：好，晚上见。',
              }
            ];
          }
          return <Map<String, Object?>>[];
        case 'update':
          return 1;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    await DBManager().close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget app(Widget child) => TideBotThemeProvider(
        theme: TideTheme(),
        child: MaterialApp(home: child),
      );

  testWidgets('transcript is available before summary and stays after update',
      (tester) async {
    await tester.pumpWidget(app(const VoiceCallDetailPage(
      callId: 'call_test',
      botName: '测试机器人',
    )));
    await tester.pumpAndSettle();
    expect(find.text('用户：明天一起看电影'), findsOneWidget);
    expect(find.text('通话摘要'), findsNothing);
    expect(find.text('通话记录不存在'), findsNothing);

    summary = '我们约好明天晚上一起看电影。';
    ChatEventBus.instance.publish(const ChatEvent(
      type: ChatEventType.updated,
      messageId: 'card_call_test',
    ));
    await tester.pumpAndSettle();
    expect(find.text(summary), findsOneWidget);
    expect(find.text('用户：明天一起看电影'), findsOneWidget);
    expect(tester.getTopLeft(find.text('通话摘要')).dy,
        lessThan(tester.getTopLeft(find.text('通话原文')).dy));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read failures offer retry instead of reporting a missing record',
      (tester) async {
    failRead = true;
    await tester.pumpWidget(app(const VoiceCallDetailPage(
      callId: 'call_test',
      botName: '测试机器人',
    )));
    await tester.pumpAndSettle();
    expect(find.text('通话记录不存在'), findsNothing);
    expect(find.text('通话记录读取失败，点击重试'), findsOneWidget);
    failRead = false;
    await tester.tap(find.text('通话记录读取失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('用户：明天一起看电影'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final role in ['user', 'assistant']) {
    testWidgets('$role call card has an opaque background', (tester) async {
      await tester.pumpWidget(app(Scaffold(
        body: VoiceCallCard(
          botName: '测试机器人',
          message: {'id': 'card_call_test', 'role': role, 'duration': 65},
        ),
      )));
      final card = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere((widget) =>
              widget.constraints?.maxWidth != null &&
              widget.decoration is BoxDecoration);
      expect((card.decoration as BoxDecoration).color?.a, 1.0);
    });
  }
}
