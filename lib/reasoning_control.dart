import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

class ReasoningControl extends StatefulWidget {
  const ReasoningControl(
      {super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  static const efforts = ['low', 'medium', 'high', 'xhigh', 'max'];
  static const labels = ['轻度', '中', '高', '极高', '最高'];
  @override
  State<ReasoningControl> createState() => _ReasoningControlState();
}

class _ReasoningControlState extends State<ReasoningControl>
    with TickerProviderStateMixin {
  late final AnimationController _clock;
  late final AnimationController _transition;
  late Animation<double> _position;
  double _phase = 0;
  Duration _previous = Duration.zero;
  int get _index => math.max(0, ReasoningControl.efforts.indexOf(widget.value));
  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _position = AlwaysStoppedAnimation(_index.toDouble());
    _transition = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _clock =
        AnimationController(vsync: this, duration: const Duration(seconds: 60))
          ..addListener(_tick);
  }

  void _tick() {
    final elapsed = _clock.lastElapsedDuration ?? Duration.zero;
    final delta = (elapsed - _previous).inMicroseconds / 1000000;
    _previous = elapsed;
    if (delta >= 0)
      _phase = (_phase + delta * (.10 + _position.value * .065)) % 1;
  }

  @override
  void didUpdateWidget(covariant ReasoningControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _position = Tween<double>(begin: _position.value, end: _index.toDouble())
          .chain(CurveTween(curve: Curves.easeOutCubic))
          .animate(_transition);
      _transition.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _transition.duration =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 300);
    if (!_reduceMotion && !_clock.isAnimating) {
      _previous = Duration.zero;
      _clock.repeat();
    } else if (_reduceMotion) {
      _clock.stop();
    }
  }

  void _select(int index) {
    if (index != _index) widget.onChanged(ReasoningControl.efforts[index]);
  }

  @override
  void dispose() {
    _clock.dispose();
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Equal columns align both labels with the five stops exactly.
      final inset = width / 10;
      void seek(Offset local) {
        final index =
            ((local.dx - inset) / (width - inset * 2) * 4).round().clamp(0, 4);
        _select(index);
      }

      Widget labels(bool chinese) => Row(
          children: List.generate(
              5,
              (i) => Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _select(i),
                      child: AnimatedDefaultTextStyle(
                        duration: _reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
                        style: TextStyle(
                          fontFamily: 'TideFont',
                          fontSize: chinese ? 12 : 10,
                          fontWeight:
                              i == _index ? FontWeight.w600 : FontWeight.w400,
                          color:
                              i == _index ? theme.textStrong : theme.textWeak,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                              chinese
                                  ? ReasoningControl.labels[i]
                                  : ReasoningControl.efforts[i],
                              textAlign: TextAlign.center,
                              maxLines: 1),
                        ),
                      ),
                    ),
                  )));
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          labels(true),
          Semantics(
            label: '思考程度',
            value: '${ReasoningControl.labels[_index]} ${widget.value}',
            increasedValue:
                _index < 4 ? ReasoningControl.labels[_index + 1] : null,
            decreasedValue:
                _index > 0 ? ReasoningControl.labels[_index - 1] : null,
            onIncrease: _index < 4 ? () => _select(_index + 1) : null,
            onDecrease: _index > 0 ? () => _select(_index - 1) : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => seek(details.localPosition),
              onHorizontalDragStart: (details) => seek(details.localPosition),
              onHorizontalDragUpdate: (details) => seek(details.localPosition),
              child: RepaintBoundary(
                  child: CustomPaint(
                size: Size(width, 36),
                painter: _ReasoningTrack(
                  repaint: Listenable.merge([_clock, _transition]),
                  phase: () => _phase,
                  position: () => _position.value,
                  dark: Theme.of(context).brightness == Brightness.dark,
                ),
              )),
            ),
          ),
          labels(false),
        ]),
      );
    });
  }
}

class _ReasoningTrack extends CustomPainter {
  _ReasoningTrack(
      {required Listenable repaint,
      required this.phase,
      required this.position,
      required this.dark})
      : super(repaint: repaint);
  final double Function() phase;
  final double Function() position;
  final bool dark;
  static const _colors = [
    Color(0xFF6B968E),
    Color(0xFF588D8A),
    Color(0xFF717DAC),
    Color(0xFF956FB0),
    Color(0xFFB55DDD)
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 40) return;
    final level = position().clamp(0.0, 4.0);
    final lower = level.floor();
    final accent = Color.lerp(
        _colors[lower], _colors[math.min(4, lower + 1)], level - lower)!;
    final galaxy = (level - 3).clamp(0.0, 1.0);
    final t = phase();
    final rect = Rect.fromLTWH(0, 7, size.width, 22);
    final rail = RRect.fromRectAndRadius(rect, const Radius.circular(11));
    final inset = size.width / 10;
    final x = inset + (size.width - inset * 2) * level / 4;
    // All effects and the thumb shadow share one clip and one position.
    canvas.save();
    canvas.clipRRect(rail);
    canvas.drawRect(
        rect,
        Paint()
          ..color = dark ? const Color(0xFF2C303B) : const Color(0xFFE3E7EB));
    final active = Rect.fromLTRB(0, rect.top, x + 10, rect.bottom);
    canvas.save();
    canvas.clipRect(active);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [
            Color.lerp(accent.withValues(alpha: .65), const Color(0xFF2836AE),
                galaxy)!,
            Color.lerp(accent, const Color(0xFF8134DC), galaxy)!,
            Color.lerp(accent, const Color(0xFFE153D5), galaxy)!,
          ]).createShader(rect));
    // Soft ribbons and fine orbiting particles accompany every level.
    for (var i = -1; i < 3; i++) {
      final center = ((t + i / 2) * size.width * 2);
      final beam = Rect.fromLTWH(center - 35, rect.top, 70, rect.height);
      canvas.drawRect(
          beam,
          Paint()
            ..shader = LinearGradient(colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: .16 + galaxy * .12),
              Colors.transparent,
            ]).createShader(beam));
    }
    for (var i = 0; i < 32; i++) {
      final px = ((i * .61803398875 + t * (i.isEven ? 1 : 2)) % 1) * size.width;
      final py = rect.center.dy +
          math.sin(t * math.pi * 2 + i * 2.4) * (5 + galaxy * 3);
      final brightness = .25 + .55 * (.5 + .5 * math.sin(t * math.pi * 2 + i));
      final opacity = brightness * (i < 10 ? 1 : galaxy);
      if (opacity <= 0) continue;
      canvas.drawCircle(Offset(px, py), i % 5 == 0 ? 1 : .55,
          Paint()..color = Colors.white.withValues(alpha: opacity));
      if (i < 5) {
        canvas.drawLine(
            Offset(px - 4 - level, py),
            Offset(px, py),
            Paint()
              ..strokeWidth = .6
              ..color = Colors.white.withValues(alpha: opacity * .45));
      }
      if (galaxy > 0 && i % 7 == 0) {
        canvas.drawLine(
            Offset(px, py - 2),
            Offset(px, py + 2),
            Paint()
              ..strokeWidth = .6
              ..color = Colors.white.withValues(alpha: opacity * galaxy));
      }
    }
    canvas.restore();
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
          Offset(inset + (size.width - inset * 2) * i / 4, rect.center.dy),
          1.7,
          Paint()
            ..color = i <= level
                ? Colors.white.withValues(alpha: .7)
                : (dark ? Colors.white38 : const Color(0xFF9BA4AD)));
    }
    final thumb = Offset(x, rect.center.dy);
    canvas.drawCircle(
        thumb + const Offset(0, 1),
        10,
        Paint()
          ..color = Colors.black.withValues(alpha: .22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(
        thumb,
        8.5,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFE4E9EF)],
          ).createShader(Rect.fromCircle(center: thumb, radius: 8.5)));
    canvas.drawCircle(
        thumb,
        8.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7
          ..color = Colors.white.withValues(alpha: .9));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ReasoningTrack oldDelegate) => true;
}
