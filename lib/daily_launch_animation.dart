import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

class DailyLaunchAnimation extends StatefulWidget {
  final Widget child;
  const DailyLaunchAnimation({super.key, required this.child});

  @override
  State<DailyLaunchAnimation> createState() => _DailyLaunchAnimationState();
}

class _DailyLaunchAnimationState extends State<DailyLaunchAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _logoOpacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _prepare();
  }

  Future<void> _prepare() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString('launch_animation_date') == today) return;
    await prefs.setString('launch_animation_date', today);
    if (!mounted) return;
    setState(() => _visible = true);
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 2500), _dismiss);
  }

  void _dismiss() {
    if (!mounted || !_visible) return;
    setState(() => _visible = false);
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
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: FadeTransition(
                      opacity: _logoOpacity,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: theme.surfaceVariant,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Icon(Icons.auto_awesome_rounded,
                                  size: 40, color: theme.primary),
                            ),
                            const SizedBox(height: 18),
                            Text('正在整理今天的陪伴',
                                style: TextStyle(
                                    color: theme.textStrong,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'TideFont')),
                            const SizedBox(height: 8),
                            Text('愿你今天也被温柔对待',
                                style: TextStyle(
                                    color: theme.textWeak,
                                    fontSize: 13,
                                    fontFamily: 'TideFont')),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 12,
                    child: TextButton(
                      onPressed: _dismiss,
                      child: Text('跳过',
                          style: TextStyle(
                              color: theme.textWeak, fontFamily: 'TideFont')),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
