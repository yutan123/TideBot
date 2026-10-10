import 'dart:io';
import 'dart:typed_data';
import 'package:heif_converter/heif_converter.dart';
import 'bot_reference_image.dart';

/// Use real PNG bytes for every vision request, including older attachments.
Future<Uint8List> modelImageBytes(String path) async {
  var source = path;
  final lower = path.toLowerCase();
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    final converted = await HeifConverter.convert(path);
    if (converted == null) {
      throw const FormatException('无法转换 HEIC 图片，请选择 JPG 或 PNG 图片');
    }
    source = converted;
  }
  return prepareBotReferenceImage(await File(source).readAsBytes());
}
