import 'dart:math' as math;

import 'package:flutter/material.dart';

class CallWavePainter extends CustomPainter {
  final double phase;
  final double strength;
  final Color color;

  const CallWavePainter({
    required this.phase,
    required this.strength,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var band = 0; band < 3; band++) {
      final radius = 76.0 + band * 22 + phase * 5;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 + strength * 1.3
        ..color = color.withValues(
          alpha: (.10 + strength * .18) * (1 - band * .18),
        );
      final path = Path();
      for (var i = 0; i <= 72; i++) {
        final angle = i / 72 * math.pi * 2;
        final ripple = (0.6 + strength * 8) *
            (1 + band * .25) *
            (.55 + .45 * math.sin(angle * 5 + phase * 6 + band));
        final point = Offset(
          center.dx + math.cos(angle) * (radius + ripple),
          center.dy + math.sin(angle) * (radius + ripple),
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CallWavePainter old) =>
      old.phase != phase || old.strength != strength || old.color != color;
}
