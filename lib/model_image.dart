import 'dart:io';
import 'dart:typed_data';
import 'package:heif_converter/heif_converter.dart';
import 'bot_reference_image.dart';

/// Use real PNG bytes for every vision request, including older attachments.
Future<Uint8List> modelImageBytes(String path) async {
  var source = path;
  final lower = path.toLowerCase();
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    try {
      final converted = await HeifConverter.convert(path);
      if (converted != null) {
        source = converted;
      } else {
        // HEIC 转换失败，尝试直接读取（某些系统可能支持）
        // 如果不支持会在后续 readAsBytes 时抛出异常
      }
    } catch (e) {
      // HEIC 转换器异常，尝试直接读取原图
    }
  }

  // 对于其他格式（jpg、png、webp、gif、bmp 等），直接处理
  try {
    return prepareBotReferenceImage(await File(source).readAsBytes());
  } catch (e) {
    throw FormatException('无法读取图片文件：$e');
  }
}
