import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// A short once-per-day transition. Android already showed the brand mark.
class DailyLaunchAnimation extends StatefulWidget {
  final Widget child;
  const DailyLaunchAnimation({super.key, required this.child});

  @override
  State<DailyLaunchAnimation> createState() => _DailyLaunchAnimationState();
}

class _DailyLaunchAnimationState extends State<DailyLaunchAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepare());
    });
  }

  Future<void> _prepare() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final now = DateTime.now();
      final today = '${now.year}-${now.month}-${now.day}';
      if (prefs.getString('launch_animation_date') == today) return;
      await prefs
          .setString('launch_animation_date', today)
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() => _visible = true);
      _controller.forward();
      _timer = Timer(const Duration(milliseconds: 1600), _dismiss);
    } catch (_) {
      // This decorative transition must never delay access to the app.
    }
  }

  void _dismiss() {
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_visible)
          Material(
            color: theme.bgColor,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _TideTransitionPainter(
                  progress: Curves.easeInOutCubic.transform(_controller.value),
                  color: theme.primary,
                  dark: theme.isDark,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    );
  }
}

class _TideTransitionPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool dark;
  const _TideTransitionPainter({
    required this.progress,
    required this.color,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final approach = Curves.easeOut.transform((progress / .45).clamp(0, 1));
    final release =
        Curves.easeIn.transform(((progress - .38) / .62).clamp(0, 1));
    final base = color.withValues(alpha: dark ? .42 : .34);
    for (final side in [-1.0, 1.0]) {
      final start = Offset(center.dx + side * size.width * .52, center.dy);
      final end = Offset(
          center.dx + side * (18 + release * size.width * .44), center.dy);
      final point = Offset.lerp(start, end, approach)!;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = base.withValues(alpha: base.a * (1 - release));
      canvas.drawArc(
        Rect.fromCircle(center: point, radius: 34 + release * 44),
        side < 0 ? -.95 : 2.2,
        1.15,
        false,
        paint,
      );
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = base.withValues(alpha: base.a * (1 - release));
    canvas.drawCircle(center, 10 + release * size.shortestSide * .58, ring);
  }

  @override
  bool shouldRepaint(covariant _TideTransitionPainter old) =>
      old.progress != progress || old.color != color || old.dark != dark;
}
