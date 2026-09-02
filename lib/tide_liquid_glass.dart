import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'theme.dart';

enum TideGlassPreset { base, dock, accentCapsule }

class TideLiquidGlass extends StatefulWidget {
  const TideLiquidGlass.base({
    super.key,
    required this.child,
    this.radius = 12,
    this.padding,
    this.interactive = false,
    this.clipExpansion = EdgeInsets.zero,
  })  : premium = false,
        preset = TideGlassPreset.base;

  const TideLiquidGlass.dock({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding,
    this.interactive = false,
    this.clipExpansion = EdgeInsets.zero,
  })  : premium = false,
        preset = TideGlassPreset.dock;

  const TideLiquidGlass.accentCapsule({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding,
    this.interactive = false,
    this.clipExpansion = EdgeInsets.zero,
  })  : premium = false,
        preset = TideGlassPreset.accentCapsule;

  const TideLiquidGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding,
    this.interactive = false,
    this.premium = false,
    this.preset = TideGlassPreset.base,
    this.clipExpansion = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool interactive;
  final bool premium;
  final TideGlassPreset preset;
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
    if (!theme.hasGlobalBackground && widget.preset == TideGlassPreset.base) {
      return _content();
    }
    final settings = _settingsFor(theme);
    final isPremium = widget.premium || widget.preset != TideGlassPreset.base;
    final glass = AdaptiveGlass(
      shape: LiquidRoundedRectangle(borderRadius: widget.radius),
      settings: settings,
      quality: isPremium ? GlassQuality.premium : GlassQuality.minimal,
      useOwnLayer: true,
      allowElevation: isPremium,
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

  LiquidGlassSettings _settingsFor(TideTheme theme) {
    final isPremium = widget.premium || widget.preset != TideGlassPreset.base;
    final (
      thickness,
      blur,
      refractiveIndex,
      chromaticAberration,
      lightIntensity,
      fresnelStrength
    ) = switch (widget.preset) {
      TideGlassPreset.base => (18.0, 1.7, 1.18, .10, .58, .68),
      TideGlassPreset.dock => (20.0, 1.9, 1.21, .12, .64, .74),
      TideGlassPreset.accentCapsule => (18.0, 1.7, 1.19, .11, .60, .70),
    };
    return LiquidGlassSettings(
      glassColor: theme.isDark
          ? const Color(0x4D1B2028)
          : widget.preset == TideGlassPreset.accentCapsule
              ? theme.primary.withValues(alpha: .16)
              : const Color(0x38F8FBFF),
      thickness: isPremium ? thickness : 9,
      blur: isPremium ? blur : 2.2,
      refractiveIndex: isPremium ? refractiveIndex : 1.06,
      chromaticAberration: isPremium ? chromaticAberration : .002,
      lightAngle: 5.35,
      lightIntensity: isPremium ? lightIntensity : .28,
      fresnelStrength: isPremium ? fresnelStrength : .34,
      saturation: 1.08,
      ambientStrength: .05,
      glowIntensity: widget.interactive ? .12 : 0,
      backerColor:
          theme.isDark ? const Color(0x52151A22) : const Color(0x30FFFFFF),
    );
  }

  Widget _content() => Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: widget.child,
      );
}
