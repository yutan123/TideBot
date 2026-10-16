import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final hasBackground in [false, true]) {
      testWidgets(
        'push and pop preserve background: $brightness, image=$hasBackground',
        (tester) async {
          final navigator = GlobalKey<NavigatorState>();
          final capture = GlobalKey();
          final background = hasBackground
              ? const Color(0xFF287A6F)
              : brightness == Brightness.dark
                  ? const Color(0xFF151820)
                  : const Color(0xFFF3F5FA);
          // Deliberately different from the page background: the default
          // Material transition exposes this surface during push and pop.
          const surface = Color(0xFFFF00FF);
          Widget page() => ColoredBox(
                color: hasBackground ? Colors.transparent : background,
                child: const Scaffold(backgroundColor: Colors.transparent),
              );
          await tester.pumpWidget(MaterialApp(
            navigatorKey: navigator,
            theme: ThemeData(
              platform: TargetPlatform.android,
              brightness: brightness,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.purple,
                brightness: brightness,
              ).copyWith(surface: surface),
              pageTransitionsTheme: tidePageTransitionsTheme,
            ),
            builder: (_, child) => RepaintBoundary(
              key: capture,
              child: ColoredBox(color: background, child: child!),
            ),
            home: page(),
          ));
          await tester.pumpAndSettle();

          Future<void> expectBackground() async {
            final pixel = await tester.runAsync(() async {
              final boundary = capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 1);
              try {
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                final offset =
                    ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
                return Color.fromARGB(
                  bytes.getUint8(offset + 3),
                  bytes.getUint8(offset),
                  bytes.getUint8(offset + 1),
                  bytes.getUint8(offset + 2),
                );
              } finally {
                image.dispose();
              }
            });
            expect(pixel, background);
          }

          await expectBackground();
          navigator.currentState!.push<void>(
            MaterialPageRoute(builder: (_) => page()),
          );
          await tester.pump();
          for (var frame = 0; frame < 6; frame++) {
            await tester.pump(const Duration(milliseconds: 50));
            await expectBackground();
          }
          await tester.pumpAndSettle();
          navigator.currentState!.pop();
          await tester.pump();
          for (var frame = 0; frame < 6; frame++) {
            await tester.pump(const Duration(milliseconds: 50));
            await expectBackground();
          }
          await tester.pumpAndSettle();
          await expectBackground();
        },
      );
    }
  }
}
