import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Quiet daily visual transition with no logo, product copy or call to action.
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
      duration: const Duration(milliseconds: 1800),
    );
    _prepare();
  }

  Future<void> _prepare() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    if (prefs.getString('launch_animation_date') == today) return;
    await prefs.setString('launch_animation_date', today);
    if (!mounted) return;
    setState(() => _visible = true);
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1900), _dismiss);
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
            color: theme.isDark ? Colors.black : Colors.white,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final progress =
                    Curves.easeInOutCubic.transform(_controller.value);
                return Stack(
                  children: [
                    _Glow(
                      alignment: Alignment(-.75 + progress * .6, -.45),
                      radius: 160 + progress * 120,
                      color: theme.primary.withValues(
                        alpha: theme.isDark ? .22 : .14,
                      ),
                    ),
                    _Glow(
                      alignment: Alignment(.85 - progress * .8, .55),
                      radius: 130 + progress * 150,
                      color: theme.primaryLight.withValues(
                        alpha: theme.isDark ? .18 : .12,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  final Alignment alignment;
  final double radius;
  final Color color;
  const _Glow({
    required this.alignment,
    required this.radius,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Container(
          width: radius,
          height: radius,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, Colors.transparent]),
          ),
        ),
      );
}

// ignore: unused_element
class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;
  const _RipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = color.withValues(alpha: (1 - phase) * .55);
      canvas.drawCircle(center, 16 + phase * size.width * .42, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
