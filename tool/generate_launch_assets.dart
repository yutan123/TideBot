import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Regenerate the native launch bitmaps whenever the Flutter logo changes.
/// Run from the repository root: dart run tool/generate_launch_assets.dart
void main() {
  final source =
      img.decodePng(File('assets/images/logo.png').readAsBytesSync());
  if (source == null) throw StateError('Cannot decode assets/images/logo.png');
  final logo = img.copyResize(source,
      width: 480, height: 480, interpolation: img.Interpolation.cubic);
  final rounded = logo.convert(numChannels: 4);
  // Bake rounded, antialiased corners into both native launch images.
  // The source logo stays untouched and remains the single source of truth.
  const radius = 84.0;
  for (final pixel in rounded) {
    final x = pixel.x + .5;
    final y = pixel.y + .5;
    final dx =
        math.max(0.0, math.max(radius - x, x - (rounded.width - radius)));
    final dy =
        math.max(0.0, math.max(radius - y, y - (rounded.height - radius)));
    final coverage =
        (radius + .5 - math.sqrt(dx * dx + dy * dy)).clamp(0.0, 1.0);
    pixel.a = (pixel.a * coverage).round();
  }
  final directory = Directory('android/app/src/main/res/drawable-xxhdpi')
    ..createSync(recursive: true);
  for (final name in ['launch_logo', 'launch_logo_round']) {
    File('${directory.path}/$name.png')
        .writeAsBytesSync(img.encodePng(rounded));
    final stale = File('android/app/src/main/res/drawable-nodpi/$name.png');
    if (stale.existsSync()) stale.deleteSync();
  }
  stdout.writeln('Native launch images updated from assets/images/logo.png');
}
