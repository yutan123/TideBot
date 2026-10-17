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
    final width = math.max(0.0, size.width - 8);
    final paint = Paint()..strokeCap = StrokeCap.round;
    final awakeY = size.height * .17;
    final sleepY = size.height * .80;
    for (final y in [awakeY, sleepY]) {
      canvas.drawLine(
          Offset(4, y),
          Offset(size.width - 4, y),
          paint
            ..color = divider.withValues(alpha: .45)
            ..strokeWidth = 1);
    }
    double? previousY;
    for (final segment in segments) {
      final asleep = segment['state'] == '睡眠';
      final x1 = 4 + (vitalInt(segment['start']) - start) / duration * width;
      final x2 = 4 + (vitalInt(segment['end']) - start) / duration * width;
      final y = asleep ? sleepY : awakeY;
      if (previousY != null && previousY != y) {
        final connector = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4.5
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [awakeColor, sleepColor],
          ).createShader(Rect.fromLTRB(x1 - 3, awakeY, x1 + 3, sleepY));
        canvas.drawLine(Offset(x1, previousY), Offset(x1, y), connector);
      }
      canvas.drawLine(
          Offset(x1, y),
          Offset(x2, y),
          paint
            ..color = asleep ? sleepColor : awakeColor
            ..strokeWidth = asleep ? 9 : 5);
      previousY = y;
    }
  }

  @override
  bool shouldRepaint(covariant _SleepTrackPainter oldDelegate) => true;
}
