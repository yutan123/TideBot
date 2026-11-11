import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// The values remain the provider's existing five reasoning effort levels.
class ReasoningControl extends StatefulWidget {
  const ReasoningControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const efforts = ['low', 'medium', 'high', 'xhigh', 'max'];
  static const labels = ['轻度', '中', '高', '极高', '最高'];

  @override
  State<ReasoningControl> createState() => _ReasoningControlState();
}

class _ReasoningControlState extends State<ReasoningControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  double _phase = 0;
  Duration _previous = Duration.zero;
  bool _animate = true;

  int get _index => math.max(0, ReasoningControl.efforts.indexOf(widget.value));

  @override
  void initState() {
    super.initState();
    _clock =
        AnimationController(vsync: this, duration: const Duration(seconds: 60))
          ..addListener(_tick);
  }

  void _tick() {
    final elapsed = _clock.lastElapsedDuration ?? Duration.zero;
    final delta = (elapsed - _previous).inMicroseconds / 1000000;
    _previous = elapsed;
    if (delta >= 0) _phase = (_phase + delta * (0.18 + _index * 0.14)) % 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = !MediaQuery.disableAnimationsOf(context);
    if (_animate && !_clock.isAnimating) {
      _previous = Duration.zero;
      _clock.repeat();
    } else if (!_animate) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = _index == 4;
    final accent = max ? const Color(0xFFD76BFF) : const Color(0xFF17C9FF);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Column(
              key: ValueKey(_index),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ReasoningControl.labels[_index],
                    style: TextStyle(
                      color: accent,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                            color: accent.withValues(alpha: .35),
                            blurRadius: 10)
                      ],
                    )),
                Text(ReasoningControl.efforts[_index],
                    style: TextStyle(
                        color: TideTheme.of(context).textWeak, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          RepaintBoundary(
            child: SizedBox(
              height: 48,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                      painter: _ReasoningTrack(
                          clock: _clock, phase: () => _phase, index: _index)),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 26,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      disabledActiveTrackColor: Colors.transparent,
                      disabledInactiveTrackColor: Colors.transparent,
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                      thumbColor: Colors.transparent,
                      overlayColor: Colors.transparent,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 16,
                          elevation: 0,
                          pressedElevation: 0),
                      overlayShape: SliderComponentShape.noOverlay,
                      showValueIndicator: ShowValueIndicator.never,
                    ),
                    child: Slider(
                      padding: EdgeInsets.zero,
                      value: _index.toDouble(),
                      min: 0,
                      max: 4,
                      divisions: 4,
                      semanticFormatterCallback: (value) =>
                          '思考程度：${ReasoningControl.labels[value.round()]}',
                      onChanged: (value) {
                        final effort = ReasoningControl.efforts[value.round()];
                        if (effort != widget.value) widget.onChanged(effort);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasoningTrack extends CustomPainter {
  _ReasoningTrack(
      {required Animation<double> clock,
      required this.phase,
      required this.index})
      : super(repaint: clock);

  final double Function() phase;
  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 32) return;
    final t = phase();
    final max = index == 4;
    final accent = max ? const Color(0xFFD54CFF) : const Color(0xFF00BDFF);
    final rect = Rect.fromLTWH(0, size.height / 2 - 13, size.width, 26);
    final track = RRect.fromRectAndRadius(rect, const Radius.circular(13));
    final x = 16 + (size.width - 32) * index / 4;
    canvas.drawRRect(track, Paint()..color = const Color(0xFF293541));
    canvas.drawRRect(
        track,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFB7D8FF).withValues(alpha: .18));
    canvas.save();
    canvas.clipRRect(track);
    // Keep a visible flowing current even at the first stop.
    for (var i = -1; i <= 1; i++) {
      final sweep = Rect.fromLTWH(
          (t + i) * (size.width + 80) - 80, rect.top, 80, rect.height);
      canvas.drawRect(
          sweep,
          Paint()
            ..shader = LinearGradient(colors: [
              Colors.transparent,
              accent.withValues(alpha: .24),
              Colors.transparent,
            ]).createShader(sweep));
    }
    final active = Rect.fromLTRB(0, rect.top, x, rect.bottom);
    canvas.clipRect(active);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: max
                ? const [
                    Color(0xFF072DFF),
                    Color(0xFF6525FF),
                    Color(0xFFF02BFF),
                    Color(0xFF7800FF)
                  ]
                : const [Color(0xFF00B8FF), Color(0xFF007AFF)],
          ).createShader(rect));
    // Moving ribbons keep every level illuminated, including the first stop.
    for (var i = -1; i < 3; i++) {
      final center = (t + i / 2) * (size.width + 90) - 45;
      canvas.save();
      canvas.translate(center, rect.center.dy);
      canvas.rotate(-.35);
      final beam = Rect.fromCenter(
          center: Offset.zero, width: max ? 70 : 46, height: 80);
      canvas.drawRect(
          beam,
          Paint()
            ..shader = LinearGradient(colors: [
              Colors.transparent,
              (max ? const Color(0xFFFFA5FB) : Colors.white)
                  .withValues(alpha: max ? .48 : .26),
              Colors.transparent,
            ]).createShader(beam));
      canvas.restore();
    }
    if (max) {
      for (var i = 0; i < 36; i++) {
        final px =
            ((i * .61803398875 + t * (i.isEven ? 1 : .45)) % 1) * size.width;
        final py = rect.top + 3 + ((i * .381966) % 1) * 20;
        final brightness = .3 + .7 * (.5 + .5 * math.sin(t * math.pi * 2 + i));
        canvas.drawCircle(
            Offset(px, py),
            i % 5 == 0 ? 1.15 : .65,
            Paint()
              ..color =
                  Color.lerp(const Color(0xFFB3D8FF), Colors.white, brightness)!
                      .withValues(alpha: brightness));
      }
    }
    canvas.restore();
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
          Offset(16 + (size.width - 32) * i / 4, rect.center.dy),
          2.1,
          Paint()
            ..color =
                i <= index ? const Color(0xFFDDF7FF) : const Color(0xFF9CAAB9));
    }
    canvas.drawRRect(
        track,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [accent.withValues(alpha: .5), Colors.transparent])
              .createShader(rect));
    final thumb = Offset(x, rect.center.dy);
    canvas.drawCircle(
        thumb,
        17,
        Paint()
          ..color = accent.withValues(alpha: .5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawCircle(thumb, 15, Paint()..color = Colors.white);
    canvas.drawCircle(
        thumb,
        15,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFDBF0FF).withValues(alpha: .7));
  }

  @override
  bool shouldRepaint(covariant _ReasoningTrack oldDelegate) =>
      oldDelegate.index != index;
}
