import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tide_bot/app_log_service.dart';
import 'package:tide_bot/live_log_view.dart';

void main() {
  final logs = AppLogService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await logs.setEnabled(false);
    await logs.setEnabled(true);
    for (var i = 0; i < 80; i++) {
      logs.add('TEST', '日志 $i ${'content ' * (i % 5 + 1)}');
    }
  });

  tearDown(() async {
    await logs.setEnabled(false);
  });

  testWidgets(
      'new output follows bottom but never interrupts reading or a drag',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(height: 220, child: LiveLogView(color: Colors.black)),
      ),
    ));
    await tester.pumpAndSettle();
    final list = find.byType(ListView);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.extentAfter, lessThanOrEqualTo(1));

    logs.add('TEST', '底部新增日志');
    await tester.pumpAndSettle();
    expect(position.extentAfter, lessThanOrEqualTo(1));

    await tester.drag(list, const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(position.extentAfter, greaterThan(1));
    final readingOffset = position.pixels;
    logs.add('TEST', '阅读旧记录时新增日志');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(position.pixels, closeTo(readingOffset, 0.01));

    // A log refresh queued before the user's drag must also yield to the user.
    position.jumpTo(position.maxScrollExtent);
    logs.add('TEST', '即将开始拖动');
    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    final draggingOffset = position.pixels;
    logs.add('TEST', '手指拖动中新增日志');
    await tester.pump();
    expect(position.pixels, closeTo(draggingOffset, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();

    // Explicitly returning to the end resumes following subsequent output.
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    logs.add('TEST', '恢复跟随');
    await tester.pumpAndSettle();
    expect(position.extentAfter, lessThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
}
