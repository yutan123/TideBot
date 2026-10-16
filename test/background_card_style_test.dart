import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/theme.dart';
import 'package:tide_bot/ui_components.dart';
import 'package:tide_bot/tide_liquid_glass.dart';

class _TestTheme extends TideTheme {
  _TestTheme(
      {required this.background,
      required this.glassEnabled,
      required this.dark});
  final bool background;
  final bool glassEnabled;
  final bool dark;
  @override
  bool get hasGlobalBackground => background;
  @override
  bool get enableLiquidGlass => glassEnabled;
  @override
  bool get isDark => dark;
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('glass off preserves normal card decoration, dark=$dark',
        (tester) async {
      Future<List<Decoration?>> decorations(bool background) async {
        final theme =
            _TestTheme(background: background, glassEnabled: false, dark: dark);
        await tester.pumpWidget(TideBotThemeProvider(
          theme: theme,
          child: const MaterialApp(
            home: Column(children: [
              FrostCard(liquid: true, child: Text('card')),
              GlassCard(liquid: true, child: Text('button')),
            ]),
          ),
        ));
        expect(find.byType(TideLiquidGlass), findsNothing);
        final cards = find.byWidgetPredicate(
            (widget) => widget is FrostCard || widget is GlassCard);
        return tester
            .widgetList<Container>(
                find.descendant(of: cards, matching: find.byType(Container)))
            .map((container) => container.decoration)
            .toList();
      }

      final normal = await decorations(false);
      final background = await decorations(true);
      expect(normal, hasLength(2));
      expect(background, normal);
      final theme =
          _TestTheme(background: true, glassEnabled: false, dark: dark);
      expect(theme.onBackgroundStrong, theme.textStrong);
      expect(theme.onBackgroundWeak, theme.textWeak);
    });
  }

  test('glass requires both an image and the enabled preference', () {
    for (final background in [false, true]) {
      for (final enabled in [false, true]) {
        final theme = _TestTheme(
            background: background, glassEnabled: enabled, dark: false);
        expect(theme.useLiquidGlass, background && enabled);
      }
    }
  });
}
