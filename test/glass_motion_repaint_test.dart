import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/glass_motion_repaint.dart';

class MotionNotifier extends ValueNotifier<int> {
  MotionNotifier() : super(0);
  bool get observed => hasListeners;
}

class PaintCounter extends CustomPainter {
  int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
  }

  @override
  bool shouldRepaint(covariant PaintCounter oldDelegate) => false;
}

void main() {
  testWidgets(
      'motion repaints glass inside nested cached layers without rebuilding content',
      (tester) async {
    final motion = MotionNotifier();
    final painter = PaintCounter();
    final child = RepaintBoundary(
        child: RepaintBoundary(
            child: CustomPaint(size: const Size(100, 100), painter: painter)));
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child:
            Center(child: GlassMotionRepaint(motion: motion, child: child))));
    final before = painter.paints;
    await tester.pump();
    expect(painter.paints, before);
    motion.value++;
    await tester.pump();
    expect(painter.paints, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    expect(motion.observed, isFalse);
    motion.dispose();
  });

  testWidgets('changing the motion source removes the old subscription',
      (tester) async {
    final first = MotionNotifier();
    final second = MotionNotifier();
    Widget build(Listenable motion) => Directionality(
        textDirection: TextDirection.ltr,
        child: GlassMotionRepaint(
            motion: motion, child: const SizedBox(width: 100, height: 100)));
    await tester.pumpWidget(build(first));
    expect(first.observed, isTrue);
    await tester.pumpWidget(build(second));
    expect(first.observed, isFalse);
    expect(second.observed, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(second.observed, isFalse);
    first.dispose();
    second.dispose();
  });
}
