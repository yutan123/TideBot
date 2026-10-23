import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/native_selectable_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late int viewId;
  late Map<dynamic, dynamic> latest;
  final channels = <MethodChannel>[];

  setUp(() {
    channels.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      final args = call.arguments as Map? ?? {};
      if (call.method == 'create') {
        viewId = args['id'] as int;
        final channel = MethodChannel('tidebot/native_selectable_text/$viewId');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          latest = call.arguments as Map;
          return null;
        });
        return 0;
      }
      if (call.method == 'resize') {
        return {'width': args['width'], 'height': args['height']};
      }
      return null;
    });
  });

  tearDown(() {
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Widget app(String text, {double width = 240, double scale = 1}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: width,
              child: NativeSelectableText(text,
                  style: const TextStyle(fontFamily: 'TideFont', fontSize: 12)),
            ),
          ),
        ),
      );

  Future<void> reportHeight(WidgetTester tester, double height,
      {int? revision}) async {
    await messenger.handlePlatformMessage(
      'tidebot/native_selectable_text/$viewId',
      const StandardMethodCodec().encodeMethodCall(MethodCall('heightChanged', {
        'revision': revision ?? latest['revision'],
        'width': latest['width'],
        'height': height,
      })),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'native height determines layout while selection stays in AndroidView',
      (tester) async {
    await tester.pumpWidget(app('较长的日志文字\n第二行'));
    await tester.pumpAndSettle();
    expect(find.byType(AndroidView), findsOneWidget);
    expect(latest['fontFamily'], 'TideFont');
    await reportHeight(tester, 180);
    expect(tester.getSize(find.byType(AndroidView)).height, 180);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'reused views update text, width and scaling and reject stale measurements',
      (tester) async {
    await tester.pumpWidget(app('旧日志'));
    await tester.pumpAndSettle();
    final oldRevision = latest['revision'] as int;
    final oldId = viewId;
    await reportHeight(tester, 160);
    await tester.pumpWidget(app('新日志\n新内容', width: 180, scale: 1.5));
    await tester.pumpAndSettle();
    expect(viewId, oldId);
    expect(latest['text'], '新日志\n新内容');
    expect(latest['width'], 180);
    expect(latest['fontSize'], 18);
    await reportHeight(tester, 480, revision: oldRevision);
    expect(tester.getSize(find.byType(AndroidView)).height, isNot(480));
    await reportHeight(tester, 200);
    expect(tester.getSize(find.byType(AndroidView)).height, 200);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
