import 'dart:io';

import 'package:flutter/services.dart';

class MediaPreprocessor {
  static const MethodChannel _channel = MethodChannel('tidebot.native.channel');

  static const int _maxDocumentBytes = 1024 * 1024;
  static const Set<String> _textExtensions = {
    'txt',
    'md',
    'markdown',
    'json',
    'csv',
    'xml',
    'html',
    'htm',
    'yaml',
    'yml',
    'log',
    'ini',
  };

  Future<String> imageFallbackText(String path) async {
    final file = File(path);
    if (!await file.exists()) return '[图片文件不存在，无法读取内容]';

    final stat = await file.stat();
    final name = path.split(Platform.pathSeparator).last;
    try {
      final text = await _channel.invokeMethod<String>(
        'recognizeText',
        {'path': path},
      );
      final normalized = text?.trim() ?? '';
      if (normalized.isNotEmpty) {
        return '[图片 OCR 文字（文件：$name，${stat.size} bytes）]\n$normalized';
      }
    } on PlatformException catch (_) {
      // Metadata remains useful when the device does not provide OCR.
    }
    return '[图片元数据：文件=$name，大小=${stat.size} bytes。未配置识图模型，且未识别到可用文字。]';
  }

  Future<String> documentText(String path) async {
    final file = File(path);
    if (!await file.exists()) return '[文档文件不存在，无法读取正文]';

    final name = path.split(Platform.pathSeparator).last;
    final extension =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final stat = await file.stat();
    if (!_textExtensions.contains(extension)) {
      return '[已附加文档：$name。当前仅能安全读取文本类文档；请将 PDF、Office 或扫描件转换为 TXT/Markdown/CSV 后再发送。]';
    }
    if (stat.size > _maxDocumentBytes) {
      return '[已附加文档：$name。文件超过 1 MB，为避免占用过多上下文，未读取正文。]';
    }

    try {
      final text = await file.readAsString();
      final trimmed = text.trim();
      if (trimmed.isEmpty) return '[文档：$name。正文为空。]';
      return '[文档正文：$name]\n$trimmed';
    } catch (e) {
      return '[文档：$name。读取失败：$e]';
    }
  }

  Future<Map<String, dynamic>> prepareVideo(String path) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'prepareVideo',
      {'path': path, 'intervalMs': 3000},
    );
    return result ?? {'error': '视频预处理未返回结果'};
  }
}
