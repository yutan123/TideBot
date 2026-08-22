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
          theme.isDark ? const Color(0x321B272D) : const Color(0x26F8FBFF),
      thickness: widget.premium ? 24 : 12,
      blur: widget.premium ? 7 : 5,
      refractiveIndex: widget.premium ? 1.16 : 1.08,
      chromaticAberration: widget.premium ? .012 : .004,
      lightAngle: 5.35,
      lightIntensity: widget.premium ? .62 : .38,
      fresnelStrength: widget.premium ? .82 : .45,
      saturation: 1.18,
      ambientStrength: .08,
      glowIntensity: widget.interactive ? .18 : 0,
      backerColor:
          theme.isDark ? const Color(0x2610181C) : const Color(0x12FFFFFF),
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
