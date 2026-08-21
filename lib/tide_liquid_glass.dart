import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme.dart';

class TideLiquidGlass extends StatefulWidget {
  const TideLiquidGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding,
    this.interactive = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool interactive;

  @override
  State<TideLiquidGlass> createState() => _TideLiquidGlassState();
}

class _TideLiquidGlassState extends State<TideLiquidGlass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!TideTheme.of(context).hasGlobalBackground) return _content();
    final shape = BorderRadius.circular(widget.radius);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: widget.interactive ? (_) => _press.forward() : null,
      onTapUp: widget.interactive ? (_) => _press.reverse() : null,
      onTapCancel: widget.interactive ? () => _press.reverse() : null,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) => Transform.scale(
          scale: 1 - _press.value * 0.025,
          child: Transform.translate(
            offset: Offset(0, _press.value * 1.5),
            child: child,
          ),
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: shape,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.48),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: shape,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.42),
                              Colors.white.withValues(alpha: 0.10),
                              Colors.white.withValues(alpha: 0.02),
                            ],
                            stops: const [0, 0.22, 0.7],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _content(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() => Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: widget.child,
      );
}
