import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/android_selection_menu.dart';

void main() {
  const channel = MethodChannel('tidebot/selection_menu');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return call.method == 'show' ? true : null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> send(String method, Map<String, Object> args) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'tidebot/selection_menu',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  testWidgets('native cut edits the original field and ignores stale actions',
      (tester) async {
    final controller = TextEditingController(text: 'hello world');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TextField(
      controller: controller,
      contextMenuBuilder: androidTextContextMenu,
      selectionControls: materialTextSelectionHandleControls,
      style: const TextStyle(fontFamily: 'TideFont', fontSize: 19),
    ))));
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.showToolbar();
    await tester.pump();
    await tester.pump();
    final args = Map<Object?, Object?>.from(
        calls.lastWhere((c) => c.method == 'show').arguments as Map);
    final id = args['id'] as int;
    final items = args['items'] as List;
    final cut = items.indexWhere((item) => (item as Map)['type'] == 'cut');
    expect(cut, greaterThanOrEqualTo(0));
    // Standard labels come from Android resources, never Flutter's default English.
    expect((items[cut] as Map)['label'], isNull);
    await send('action', {'id': id + 100, 'index': cut});
    expect(controller.text, 'hello world');
    await send('action', {'id': id, 'index': cut});
    await tester.pump();
    expect(controller.text, ' world');
    expect(tester.widget<TextField>(find.byType(TextField)).style!.fontFamily,
        'TideFont');
    expect(
        tester.widget<TextField>(find.byType(TextField)).style!.fontSize, 19);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls.any((call) => call.method == 'hide'), isTrue);
    controller.dispose();
  });

  testWidgets('legal-style SelectionArea uses the native toolbar',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SelectionArea(
      contextMenuBuilder: androidSelectionContextMenu,
      child: Text('Agreement text'),
    ))));
    // Exercise selection through the user's long-press path.
    await tester.longPress(find.text('Agreement text'));
    await tester.pump();
    await tester.pump();
    expect(calls.any((call) => call.method == 'show'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
