import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/log_session_detail_page.dart';

void main() {
  testWidgets(
      'native focus reveal does not move history but dragging still does',
      (tester) async {
    final controller = ScrollController(initialScrollOffset: 250);
    final tallRow = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: ListView(
        controller: controller,
        physics: const HistoryLogScrollPhysics(),
        children: [
          SizedBox(key: tallRow, height: 2000),
          const SizedBox(height: 1000),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    final before = controller.offset;
    tallRow.currentContext!.findRenderObject()!.showOnScreen(
          duration: const Duration(milliseconds: 100),
        );
    await tester.pumpAndSettle();
    expect(controller.offset, before);
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
