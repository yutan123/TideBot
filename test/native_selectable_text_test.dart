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
  final nativeCalls = <MethodCall>[];
  final disposedViews = <int>[];

  setUp(() {
    channels.clear();
    nativeCalls.clear();
    disposedViews.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      final args = call.arguments as Map? ?? {};
      if (call.method == 'create') {
        viewId = args['id'] as int;
        final channel = MethodChannel('tidebot/native_selectable_text/$viewId');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          if (call.method == 'update') latest = call.arguments as Map;
          return null;
        });
        return 0;
      }
      if (call.method == 'dispose') disposedViews.add(args['id'] as int);
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

  Widget app(String text,
          {double width = 240,
          double scale = 1,
          NativeTextHeightCache? cache}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: width,
              child: NativeSelectableText(text,
                  heightCache: cache,
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
      'hybrid text hides before pop completes and uses route-bound text',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('历史日志列表')),
    ));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        body: SizedBox(
            width: 240,
            child: NativeSelectableText('退出时不应残留的详情文字',
                nativeInteraction: true, style: TextStyle(fontSize: 12))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(nativeCalls.lastWhere((c) => c.method == 'setVisible').arguments,
        {'visible': true});
    final outgoingId = viewId;
    nativeCalls.clear();
    navigator.currentState!.pop();
    await tester.pump();
    expect(
        nativeCalls.any((c) =>
            c.method == 'setVisible' &&
            (c.arguments as Map)['visible'] == false),
        isTrue);
    expect(disposedViews, isNot(contains(outgoingId)));
    expect(find.text('退出时不应残留的详情文字'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(disposedViews, contains(outgoingId));
    expect(find.text('退出时不应残留的详情文字'), findsNothing);
    expect(find.text('历史日志列表'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('history row reuses measured height after lazy disposal',
      (tester) async {
    final cache = NativeTextHeightCache();
    await tester.pumpWidget(app('历史日志测量缓存', cache: cache));
    await tester.pumpAndSettle();
    await reportHeight(tester, 360);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app('历史日志测量缓存', cache: cache));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AndroidView)).height, 360);
    await tester.pumpWidget(app('历史日志测量缓存', width: 200, cache: cache));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AndroidView)).height, isNot(360));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

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
