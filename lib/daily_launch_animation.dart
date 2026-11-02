import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Plays before mounting the destination; completion follows the animation clock.
class DailyLaunchAnimation extends StatefulWidget {
  final Widget child;
  final bool force;
  const DailyLaunchAnimation({
    super.key,
    required this.child,
    this.force = false,
  });
  @override
  State<DailyLaunchAnimation> createState() => _DailyLaunchAnimationState();
}

class _DailyLaunchAnimationState extends State<DailyLaunchAnimation>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _visible = true;
  bool _started = false;
  String? _today;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1600),
          animationBehavior: AnimationBehavior.preserve,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) unawaited(_complete());
        });
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      _today = '${now.year}-${now.month}-${now.day}';
      if (!widget.force && prefs.getString('launch_animation_date') == _today) {
        if (mounted) setState(() => _visible = false);
        return;
      }
    } catch (_) {
      // Still play the full transition when the date cannot be read.
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _started = true;
      if (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _controller.forward(from: 0);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _complete() async {
    if (!mounted) return;
    setState(() => _visible = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_today != null)
        await prefs.setString('launch_animation_date', _today!);
    } catch (_) {
      // A failed date write should only cause the animation to play again.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_visible || !_started) return;
    if (state == AppLifecycleState.resumed) {
      _controller.forward();
    } else {
      _controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;
    final theme = TideTheme.of(context);
    return Material(
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
    final release = Curves.easeIn.transform(
      ((progress - .38) / .62).clamp(0, 1),
    );
    final base = color.withValues(alpha: dark ? .42 : .34);
    for (final side in [-1.0, 1.0]) {
      final start = Offset(center.dx + side * size.width * .52, center.dy);
      final end = Offset(
        center.dx + side * (18 + release * size.width * .44),
        center.dy,
      );
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
