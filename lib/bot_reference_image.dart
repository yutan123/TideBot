import 'dart:ui' as ui;

import 'image_upload_codec.dart';
import 'package:flutter/foundation.dart';

/// Validate, resize and encode an image as JPEG for model/reference uploads.
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
      final (width, height) = imageUploadSize(image.width, image.height);
      if (width != image.width || height != image.height) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
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

      // JPEG has no alpha channel. Composite transparent images onto white
      // before encoding so transparent pixels do not become black.
      final source = resized ?? image;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
      canvas.drawImage(source, ui.Offset.zero, ui.Paint());
      final picture = recorder.endRecording();
      try {
        final opaque = await picture.toImage(source.width, source.height);
        try {
          final pixels = await opaque.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (pixels == null) {
            throw const FormatException('无法读取图片，请换一张图片');
          }
          return compute(encodeUploadJpeg, (
            pixels.buffer.asUint8List(
              pixels.offsetInBytes,
              pixels.lengthInBytes,
            ),
            source.width,
            source.height,
          ));
        } finally {
          opaque.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      resized?.dispose();
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
