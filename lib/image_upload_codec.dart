import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Fits a photo inside a landscape/portrait 1080p frame without upscaling.
(int, int) imageUploadSize(int width, int height) {
  final landscape = width >= height;
  final maxWidth = landscape ? 1920 : 1080;
  final maxHeight = landscape ? 1080 : 1920;
  final scaleX = maxWidth / width;
  final scaleY = maxHeight / height;
  final scale = scaleX < scaleY ? scaleX : scaleY;
  if (scale >= 1) return (width, height);
  return (
    (width * scale).round().clamp(1, maxWidth),
    (height * scale).round().clamp(1, maxHeight),
  );
}

/// Pixels have already been oriented and composited onto white by Flutter.
Uint8List encodeUploadJpeg((Uint8List, int, int) data) {
  final image = img.Image.fromBytes(
    width: data.$2,
    height: data.$3,
    bytes: data.$1.buffer,
    bytesOffset: data.$1.offsetInBytes,
    numChannels: 4,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
