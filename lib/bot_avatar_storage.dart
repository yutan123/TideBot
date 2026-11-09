import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

/// Store a real square PNG; circular masking belongs to presentation only.
Future<String> saveSquareBotAvatar(
  String sourcePath, {
  ui.Rect? cropRect,
}) async {
  final codec = await ui.instantiateImageCodec(
    await File(sourcePath).readAsBytes(),
  );
  try {
    final frame = await codec.getNextFrame();
    final source = frame.image;
    try {
      final side = math.min(source.width, source.height).toDouble();
      final requested = cropRect ??
          ui.Rect.fromLTWH(
            (source.width - side) / 2,
            (source.height - side) / 2,
            side,
            side,
          );
      if (!requested.isFinite ||
          requested.width <= 0 ||
          (requested.width - requested.height).abs() > 0.01) {
        throw ArgumentError('头像裁剪范围必须为有效正方形');
      }
      // Clamp rounding error at the image edges without adding empty borders.
      final cropSide = math.min(requested.width, side);
      final crop = ui.Rect.fromLTWH(
        requested.left.clamp(0.0, source.width - cropSide).toDouble(),
        requested.top.clamp(0.0, source.height - cropSide).toDouble(),
        cropSide,
        cropSide,
      );
      final outputSide = math.max(1, math.min(cropSide.round(), 512));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        crop,
        ui.Rect.fromLTWH(0, 0, outputSide.toDouble(), outputSide.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        final square = await picture.toImage(outputSide, outputSide);
        try {
          final bytes = await square.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) throw StateError('头像编码失败');
          final directory = await getApplicationDocumentsDirectory();
          final file = File(
            '${directory.path}/avatar_${DateTime.now().microsecondsSinceEpoch}.png',
          );
          await file.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
            flush: true,
          );
          return file.path;
        } finally {
          square.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      source.dispose();
    }
  } finally {
    codec.dispose();
  }
}
