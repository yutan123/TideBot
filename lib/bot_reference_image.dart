import 'dart:typed_data';
import 'dart:ui' as ui;
// Image conversion uses the engine codec without explicit decode dimensions.

/// Validate and resize locally; document providers need not expose a media URI.
Future<Uint8List> prepareBotReferenceImage(Uint8List bytes) async {
  if (bytes.isEmpty) throw const FormatException('所选图片为空，请重新选择');
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('图片不能超过 20 MB');
  }
  // Decode at the native size first. Android codecs can reject explicit output
  // dimensions for some JPEGs (including photos with orientation metadata).
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    ui.Image? resized;
    try {
      final image = frame.image;
      final longest = image.width > image.height ? image.width : image.height;
      if (longest > 2048) {
        final scale = 2048 / longest;
        final width = (image.width * scale).round().clamp(1, 2048);
        final height = (image.height * scale).round().clamp(1, 2048);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
              0, 0, image.width.toDouble(), image.height.toDouble()),
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        final picture = recorder.endRecording();
        try {
          resized = await picture.toImage(width, height);
        } finally {
          picture.dispose();
        }
      }
      final data =
          await (resized ?? image).toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const FormatException('无法读取图片，请换一张图片');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      resized?.dispose();
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
