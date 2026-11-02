import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/log_session_detail_page.dart';
import 'package:tide_bot/log_text.dart';

void main() {
  const menu = MethodChannel('tidebot/selection_menu');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final processCalls = <MethodCall>[];

  setUp(() {
    processCalls.clear();
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.processText, (call) async {
      processCalls.add(call);
      if (call.method == 'ProcessText.queryTextActions') {
        return {'device.translate': '系统翻译'};
      }
      return null;
    });
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(menu, (call) async {
      calls.add(call);
      return call.method == 'show' ? true : null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.processText, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(menu, null);
  });

  testWidgets('both long-log handles drag across native toolbar dismissal',
      (tester) async {
    final text =
        List.generate(70, (i) => 'line $i alpha beta gamma delta\n').join();
    final scroll = ScrollController(initialScrollOffset: 200);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: scroll,
          physics: const HistoryLogScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            LogText(text, color: Colors.black),
            const SizedBox(height: 300),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
      of: find.byType(LogText),
      matching: find.byType(RichText),
    ));
    final word = text.indexOf('beta', text.indexOf('line 5 '));
    final box = paragraph
        .getBoxesForSelection(
            TextSelection(baseOffset: word + 1, extentOffset: word + 2))
        .single;
    await tester.longPressAt(paragraph.localToGlobal(box.toRect().center));
    await tester.pumpAndSettle();
    final original = paragraph.selections.single;
    expect(text.substring(original.start, original.end), 'beta');
    final offset = scroll.offset;
    final show =
        calls.lastWhere((call) => call.method == 'show').arguments as Map;
    final id = show['id'] as int;
    final types = (show['items'] as List).map((item) => (item as Map)['type']);
    expect(types, contains('copy'));
    expect(types, isNot(contains('cut')));
    expect(types, isNot(contains('paste')));

    final endBox = paragraph.getBoxesForSelection(original).last;
    final end = await tester.startGesture(
        paragraph.localToGlobal(endBox.toRect().bottomRight) +
            const Offset(10, 10));
    await tester.pump();
    expect(calls.map((call) => call.method), contains('suspend'));
    // Android may dismiss its floating window while the handle gesture is active.
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      menu.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('dismissed', {'id': id})),
      (_) {},
    );
    await end.moveBy(const Offset(24, 0));
    await tester.pump();
    await end.moveBy(const Offset(42, 0));
    await tester.pump();
    final extended = paragraph.selections.single;
    expect(extended.end, greaterThan(original.end));
    expect(extended.start, original.start);
    await end.up();
    await tester.pumpAndSettle();
    expect(calls.last.method, 'show');
    expect((calls.last.arguments as Map)['id'], isA<int>());
    expect(scroll.offset, offset);

    final startBox = paragraph.getBoxesForSelection(extended).first;
    final start = await tester.startGesture(
        paragraph.localToGlobal(startBox.toRect().bottomLeft) +
            const Offset(-10, 10));
    await tester.pump();
    expect(calls.map((call) => call.method), contains('suspend'));
    await start.moveBy(const Offset(-24, 0));
    await tester.pump();
    await start.moveBy(const Offset(-36, 0));
    await tester.pump();
    final adjusted = paragraph.selections.single;
    expect(adjusted.start, lessThan(extended.start));
    expect(adjusted.end, extended.end);
    await start.up();
    await tester.pumpAndSettle();
    expect(calls.last.method, 'show');
    expect(scroll.offset, offset);
    final finalMenu = calls.last.arguments as Map;
    final actions = finalMenu['items'] as List;
    final translate =
        actions.indexWhere((item) => (item as Map)['label'] == '系统翻译');
    expect(translate, greaterThanOrEqualTo(0));
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      menu.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('action', {
        'id': finalMenu['id'],
        'index': translate,
      })),
      (_) {},
    );
    await tester.pumpAndSettle();
    final processed = processCalls
        .lastWhere((call) => call.method == 'ProcessText.processTextAction');
    expect(processed.arguments, [
      'device.translate',
      text.substring(adjusted.start, adjusted.end),
      true
    ]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    scroll.dispose();
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
