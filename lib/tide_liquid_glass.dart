import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'theme.dart';

class TideLiquidGlass extends StatefulWidget {
  const TideLiquidGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding,
    this.interactive = false,
    this.premium = false,
    this.clipExpansion = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool interactive;
  final bool premium;
  final EdgeInsets clipExpansion;

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
    final theme = TideTheme.of(context);
    if (!theme.hasGlobalBackground) return _content();
    final settings = LiquidGlassSettings(
      glassColor:
          theme.isDark ? const Color(0x381B2028) : const Color(0x2AF8FBFF),
      thickness: widget.premium ? 18 : 9,
      blur: widget.premium ? 3.2 : 2.2,
      refractiveIndex: widget.premium ? 1.12 : 1.06,
      chromaticAberration: widget.premium ? .006 : .002,
      lightAngle: 5.35,
      lightIntensity: widget.premium ? .48 : .28,
      fresnelStrength: widget.premium ? .68 : .34,
      saturation: 1.08,
      ambientStrength: .05,
      glowIntensity: widget.interactive ? .12 : 0,
      backerColor:
          theme.isDark ? const Color(0x32151A22) : const Color(0x18FFFFFF),
    );
    final glass = AdaptiveGlass(
      shape: LiquidRoundedRectangle(borderRadius: widget.radius),
      settings: settings,
      quality: widget.premium ? GlassQuality.premium : GlassQuality.minimal,
      useOwnLayer: true,
      allowElevation: widget.premium,
      isInteractive: widget.interactive,
      clipExpansion: widget.clipExpansion,
      child: _content(),
    );
    if (!widget.interactive) return glass;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) => _press.reverse(),
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) => Transform.scale(
          scale: 1 - _press.value * 0.018,
          child: Transform.translate(
            offset: Offset(0, _press.value),
            child: child,
          ),
        ),
        child: glass,
      ),
    );
  }

  Widget _content() => Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: widget.child,
      );
}
