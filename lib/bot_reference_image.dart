import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

/// Validate and resize locally; document providers need not expose a media URI.
Future<Uint8List> prepareBotReferenceImage(Uint8List bytes) async {
  if (bytes.isEmpty) throw const FormatException('所选图片为空，请重新选择');
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('图片不能超过 20 MB');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await PaintingBinding.instance.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      final longest = width > height ? width : height;
      final scale = longest > 2048 ? 2048 / longest : 1.0;
      return ui.TargetImageSize(
        width: (width * scale).round().clamp(1, 2048),
        height: (height * scale).round().clamp(1, 2048),
      );
    },
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const FormatException('无法读取图片，请换一张图片');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
