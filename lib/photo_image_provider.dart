import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:heif_converter/heif_converter.dart';

/// A HEIF display copy never replaces the original attachment used for uploads.
Future<File> photoDisplayFile(String path) async {
  final lower = path.toLowerCase();
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    try {
      final converted = await HeifConverter.convert(path);
      if (converted != null) return File(converted);
    } catch (_) {
      // Some systems can decode the original even when the plugin fails.
    }
  }
  return File(path);
}

ImageProvider<Object> photoImageProvider(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    return _HeifDisplayImage(path);
  }
  return FileImage(File(path));
}

class _HeifDisplayImage extends ImageProvider<_HeifDisplayImage> {
  const _HeifDisplayImage(this.path);
  final String path;

  @override
  Future<_HeifDisplayImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _HeifDisplayImage key,
    ImageDecoderCallback decode,
  ) =>
      MultiFrameImageStreamCompleter(
        codec: _decode(decode),
        scale: 1,
        debugLabel: path,
      );

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final file = await photoDisplayFile(path);
    return decode(await ui.ImmutableBuffer.fromFilePath(file.path));
  }

  @override
  bool operator ==(Object other) =>
      other is _HeifDisplayImage && path == other.path;
  @override
  int get hashCode => path.hashCode;
}
