import 'package:flutter/material.dart';

import 'theme.dart';

/// A quiet, full-bleed canvas; no cropped light spots or fixed-size ornaments.
class DefaultChatBackground extends StatelessWidget {
  const DefaultChatBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final base = theme.pageBackground;
    final tint = theme.isDark ? 0.045 : 0.025;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.48, 1],
            colors: [
              base,
              Color.lerp(base, theme.primary, tint)!,
              Color.lerp(base, theme.primaryLight, tint * 1.6)!,
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
