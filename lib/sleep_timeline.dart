import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'bot_vital_model.dart';
import 'theme.dart';

String _clock(dynamic value) {
  final t = DateTime.fromMillisecondsSinceEpoch(vitalInt(value));
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

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

/// The ribbon retains real duration. Separate beacons and event chips keep even
/// a minute of wakefulness visible without exaggerating its duration.
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
    final awakenings = segments.where((s) => s['state'] == '清醒').toList();
    const awake = Color(0xffC99A51);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 18, runSpacing: 8, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          SleepStateMark(asleep: true, color: theme.primary),
          Text('睡眠', style: TextStyle(fontSize: 11, color: theme.textWeak)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const SleepStateMark(asleep: false, color: awake),
          Text('清醒 · ${awakenings.length}次',
              style: TextStyle(fontSize: 11, color: theme.textWeak)),
        ]),
      ]),
      const SizedBox(height: 8),
      LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final width = math.max(1.0, constraints.maxWidth - 8);
                  double center(Map<String, dynamic> s) =>
                      4 +
                      ((vitalInt(s['start']) + vitalInt(s['end'])) / 2 -
                              start) /
                          duration *
                          width;
                  if (details.localPosition.dy < 48 && awakenings.isNotEmpty) {
                    final nearest = awakenings.reduce((a, b) =>
                        (center(a) - details.localPosition.dx).abs() <=
                                (center(b) - details.localPosition.dx).abs()
                            ? a
                            : b);
                    if ((center(nearest) - details.localPosition.dx).abs() <=
                        22) {
                      onSelect(nearest);
                      return;
                    }
                  }
                  final fraction =
                      ((details.localPosition.dx - 4) / width).clamp(0.0, 1.0);
                  final time = start + duration * fraction;
                  onSelect(segments.firstWhere((s) => time < vitalInt(s['end']),
                      orElse: () => segments.last));
                },
                child: Semantics(
                  label:
                      '睡眠时间线，${_clock(start)}至${_clock(end)}，清醒${awakenings.length}次，点击查看时段',
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 112),
                    painter: _SleepTrackPainter(
                        segments, theme.primary, awake, theme.divider),
                  ),
                ),
              )),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_clock(start),
            style: TextStyle(fontSize: 11, color: theme.textFaint)),
        Text('按实际时长绘制', style: TextStyle(fontSize: 10, color: theme.textFaint)),
        Text(_clock(end),
            style: TextStyle(fontSize: 11, color: theme.textFaint)),
      ]),
      const SizedBox(height: 12),
      if (awakenings.isEmpty)
        Text('这一段休息没有清醒记录',
            style: TextStyle(fontSize: 11, color: theme.textWeak))
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < awakenings.length; i++)
            ActionChip(
              avatar: Text('${i + 1}',
                  style: const TextStyle(color: awake, fontSize: 11)),
              label: Text(
                  '${_clock(awakenings[i]['start'])} · ${math.max(1, ((vitalInt(awakenings[i]['end']) - vitalInt(awakenings[i]['start'])) / 60000).ceil())}分',
                  style: TextStyle(fontSize: 11, color: theme.textStrong)),
              backgroundColor: awake.withValues(alpha: .10),
              side: BorderSide(color: awake.withValues(alpha: .24)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onPressed: () => onSelect(awakenings[i]),
            ),
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
    if (size.width <= 8) return;
    final start = vitalInt(segments.first['start']);
    final duration = math.max(1, vitalInt(segments.last['end']) - start);
    double x(num time) => 4 + (time - start) / duration * (size.width - 8);
    const y = 76.0, height = 18.0;
    final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(4, y - height / 2, size.width - 8, height),
        const Radius.circular(9));
    for (var i = 0; i <= 8; i++) {
      final px = 4 + i / 8 * (size.width - 8);
      canvas.drawLine(
          Offset(px, y + 16),
          Offset(px, y + (i.isEven ? 23 : 20)),
          Paint()
            ..color = divider.withValues(alpha: .55)
            ..strokeWidth = 1);
    }
    canvas.drawRRect(track, Paint()..color = divider.withValues(alpha: .2));
    canvas.save();
    canvas.clipRRect(track);
    for (final s in segments) {
      final color = s['state'] == '睡眠' ? sleepColor : awakeColor;
      final rect = Rect.fromLTRB(x(vitalInt(s['start'])), y - height / 2,
          x(vitalInt(s['end'])), y + height / 2);
      if (rect.width <= 0) continue;
      canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: .55),
                color.withValues(alpha: .92)
              ],
            ).createShader(rect));
      canvas.drawLine(
          Offset(rect.left, rect.top + 2),
          Offset(rect.right, rect.top + 2),
          Paint()
            ..color = color.withValues(alpha: .35)
            ..strokeWidth = 1);
    }
    canvas.restore();
    for (final s in segments.where((s) => s['state'] == '清醒')) {
      final center = x((vitalInt(s['start']) + vitalInt(s['end'])) / 2);
      canvas.drawLine(
          Offset(center, 41),
          Offset(center, y - height / 2),
          Paint()
            ..color = awakeColor.withValues(alpha: .5)
            ..strokeWidth = 1);
      canvas.drawCircle(Offset(center, 29), 15,
          Paint()..color = awakeColor.withValues(alpha: .09));
      canvas.drawCircle(Offset(center, 29), 10,
          Paint()..color = awakeColor.withValues(alpha: .18));
      final diamond = Path()
        ..moveTo(center, 22)
        ..lineTo(center + 5, 29)
        ..lineTo(center, 36)
        ..lineTo(center - 5, 29)
        ..close();
      canvas.drawPath(diamond, Paint()..color = awakeColor);
      canvas.drawCircle(Offset(center, y), 2.5, Paint()..color = awakeColor);
    }
  }

  @override
  bool shouldRepaint(covariant _SleepTrackPainter old) => true;
}
