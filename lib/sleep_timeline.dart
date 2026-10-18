import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'bot_vital_model.dart';
import 'theme.dart';

String _clock(dynamic value) {
  final t = DateTime.fromMillisecondsSinceEpoch(vitalInt(value));
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Quiet geometric legend, shared by the timeline and its detail rows.
class SleepStateMark extends StatelessWidget {
  const SleepStateMark({super.key, required this.asleep, required this.color});
  final bool asleep;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 20,
        child: Center(
            child: Container(
          width: asleep ? 5 : 9,
          height: asleep ? 16 : 9,
          decoration: BoxDecoration(
            color: asleep ? color : Colors.transparent,
            border: asleep ? null : Border.all(color: color, width: 1.8),
            borderRadius: BorderRadius.circular(5),
          ),
        )),
      );
}

/// Two calm lanes preserve real time proportions, even for a brief awakening.
/// The full track is a hit area so short intervals remain easy to inspect.
class SleepTimeline extends StatelessWidget {
  const SleepTimeline(
      {super.key, required this.segments, required this.onSelect});
  final List<Map<String, dynamic>> segments;
  final ValueChanged<Map<String, dynamic>> onSelect;
  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final theme = TideTheme.of(context);
    final start = vitalInt(segments.first['start']);
    final end = vitalInt(segments.last['end']);
    final duration = math.max(1, end - start);
    const awake = Color(0xffc89e65);
    return Column(children: [
      Row(children: [
        SleepStateMark(asleep: true, color: theme.primary),
        Text('睡眠', style: TextStyle(fontSize: 11, color: theme.textWeak)),
        const SizedBox(width: 18),
        const SleepStateMark(asleep: false, color: awake),
        Text('清醒', style: TextStyle(fontSize: 11, color: theme.textWeak)),
      ]),
      const SizedBox(height: 10),
      LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final fraction = ((details.localPosition.dx - 4) /
                          math.max(1, constraints.maxWidth - 8))
                      .clamp(0.0, 1.0);
                  final time = start + duration * fraction;
                  onSelect(segments.firstWhere(
                      (segment) => time < vitalInt(segment['end']),
                      orElse: () => segments.last));
                },
                child: Semantics(
                  label: '睡眠时间线，${_clock(start)}至${_clock(end)}，点击查看时段',
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 104),
                    painter: _SleepTrackPainter(
                        segments, theme.primary, awake, theme.divider),
                  ),
                ),
              )),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_clock(start),
            style: TextStyle(fontSize: 11, color: theme.textFaint)),
        Text('点击查看时段', style: TextStyle(fontSize: 10, color: theme.textFaint)),
        Text(_clock(end),
            style: TextStyle(fontSize: 11, color: theme.textFaint)),
      ]),
    ]);
  }
}

class _SleepTrackPainter extends CustomPainter {
  _SleepTrackPainter(
      this.segments, this.sleepColor, this.awakeColor, this.divider);
  final List<Map<String, dynamic>> segments;
  final Color sleepColor, awakeColor, divider;
  @override
  void paint(Canvas canvas, Size size) {
    final start = vitalInt(segments.first['start']);
    final duration = math.max(1, vitalInt(segments.last['end']) - start);
    final trackHeight = 14.0;
    final centerY = size.height / 2;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, centerY - trackHeight / 2, size.width - 8, trackHeight),
      const Radius.circular(7),
    );
    canvas.drawRRect(
      trackRect,
      Paint()..color = divider.withValues(alpha: .2),
    );
    final path = Path();
    final points = <Offset>[];
    for (final segment in segments) {
      final asleep = segment['state'] == '睡眠';
      final x1 = 4 +
          (vitalInt(segment['start']) - start) / duration * (size.width - 8);
      final x2 =
          4 + (vitalInt(segment['end']) - start) / duration * (size.width - 8);
      points.add(Offset(x1, asleep ? 1.0 : 0.0));
      points.add(Offset(x2, asleep ? 1.0 : 0.0));
    }
    if (points.isEmpty) return;
    path.moveTo(points.first.dx, centerY);
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final currentY = centerY + (current.dy - 0.5) * 0;
      final nextY = centerY + (next.dy - 0.5) * 0;
      if (current.dy != next.dy) {
        final transitionWidth = math.min(12.0, (next.dx - current.dx) / 2);
        path.lineTo(current.dx, currentY);
        path.cubicTo(
          current.dx + transitionWidth / 2,
          currentY,
          next.dx - transitionWidth / 2,
          nextY,
          next.dx,
          nextY,
        );
      } else {
        path.lineTo(next.dx, nextY);
      }
    }
    canvas.save();
    canvas.clipRRect(trackRect);
    final gradientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackHeight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final segment in segments) {
      final asleep = segment['state'] == '睡眠';
      final x1 = 4 +
          (vitalInt(segment['start']) - start) / duration * (size.width - 8);
      final x2 =
          4 + (vitalInt(segment['end']) - start) / duration * (size.width - 8);
      if (x2 - x1 < 0.5) continue;
      final segmentPath = Path()
        ..moveTo(x1, centerY)
        ..lineTo(x2, centerY);
      gradientPaint.color = asleep ? sleepColor : awakeColor;
      canvas.drawPath(segmentPath, gradientPaint);
    }
    for (var i = 0; i < segments.length - 1; i++) {
      final current = segments[i];
      final next = segments[i + 1];
      if (current['state'] != next['state']) {
        final x = 4 +
            (vitalInt(current['end']) - start) / duration * (size.width - 8);
        final transitionWidth = 16.0;
        final transitionRect = Rect.fromLTWH(
          x - transitionWidth / 2,
          centerY - trackHeight / 2,
          transitionWidth,
          trackHeight,
        );
        final isToSleep = next['state'] == '睡眠';
        gradientPaint.shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors:
              isToSleep ? [awakeColor, sleepColor] : [sleepColor, awakeColor],
        ).createShader(transitionRect);
        canvas.drawRect(transitionRect, gradientPaint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SleepTrackPainter oldDelegate) => true;
}
