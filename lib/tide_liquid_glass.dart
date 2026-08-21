import 'dart:ui';

import 'package:flutter/material.dart';
import 'theme.dart';

class TideDockMetrics {
  static const double height = 56;
  static const double bottomGap = 16;

  static double contentBottomInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + bottomGap + height + 24;

  static double fabBottom(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + bottomGap + height + 12;
}

enum TideLiquidGlassKind { card, dock, dialog, sheet }

class TideLiquidGlass extends StatelessWidget {
  const TideLiquidGlass({
    super.key,
    required this.child,
    this.radius = 18,
    this.kind = TideLiquidGlassKind.card,
    this.padding,
  });

  final Widget child;
  final double radius;
  final TideLiquidGlassKind kind;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final isDock = kind == TideLiquidGlassKind.dock;
    final fillAlpha = switch (kind) {
      TideLiquidGlassKind.dock => theme.isDark ? 0.58 : 0.44,
      TideLiquidGlassKind.dialog ||
      TideLiquidGlassKind.sheet =>
        theme.isDark ? 0.88 : 0.84,
      TideLiquidGlassKind.card => theme.isDark ? 0.70 : 0.64,
    };
    final radiusValue = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: radiusValue,
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: isDock ? 24 : 12, sigmaY: isDock ? 24 : 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface.withValues(alpha: fillAlpha),
            borderRadius: radiusValue,
            border: Border.all(
              color: Colors.white.withValues(alpha: theme.isDark ? 0.20 : 0.56),
              width: 0.7,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withValues(alpha: theme.isDark ? 0.22 : 0.10),
                blurRadius: isDock ? 24 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radiusValue,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white
                              .withValues(alpha: theme.isDark ? 0.16 : 0.45),
                          theme.primaryLight
                              .withValues(alpha: isDock ? 0.13 : 0.05),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.48, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ],
          ),
        ),
      ),
    );
  }
}
