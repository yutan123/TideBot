import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

class MediaPreprocessor {
  static const MethodChannel _channel = MethodChannel('tidebot.native.channel');

  // 防止单个附件占满聊天上下文。
  static const int _maxDocumentBytes = 1024 * 1024;
  static const int _maxExtractedCharacters = 120000;

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
  static const Set<String> _officeExtensions = {'docx', 'xlsx', 'pptx'};

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
      // 设备 OCR 不可用时仍向模型提供文件元数据。
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
    if (stat.size > _maxDocumentBytes) {
      return '[已附加文档：$name。文件超过 1 MB，为避免占用过多上下文，未读取正文。]';
    }

    try {
      late final String text;
      late final String source;
      if (_textExtensions.contains(extension)) {
        text = await file.readAsString();
        source = '文本正文';
      } else if (_officeExtensions.contains(extension)) {
        text = await _officeText(file, extension);
        source = 'Office 正文';
      } else if (extension == 'pdf') {
        text = await _pdfText(path);
        source = 'PDF 本机 OCR';
      } else {
        return '[已附加文档：$name。暂不支持 .$extension；可发送 TXT、Markdown、CSV、DOCX、XLSX、PPTX 或 PDF。]';
      }

      final normalized = _normalizeText(text);
      if (normalized.isEmpty) {
        return '[文档：$name。未提取到可用正文；若这是扫描件，请确保页面清晰后重试。]';
      }
      final limited = normalized.length > _maxExtractedCharacters
          ? '${normalized.substring(0, _maxExtractedCharacters)}\n[正文过长，已截取前 $_maxExtractedCharacters 个字符]'
          : normalized;
      return '[文档$source：$name]\n$limited';
    } catch (e) {
      return '[文档：$name。正文提取失败：$e；文件仍已附加，但不会伪装成已解析。]';
    }
  }

  Future<String> _pdfText(String path) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'extractPdfText',
      {'path': path, 'maxPages': 3, 'maxChars': _maxExtractedCharacters},
    );
    if (result == null) throw StateError('PDF OCR 未返回结果');
    final error = result['error']?.toString().trim() ?? '';
    if (error.isNotEmpty) throw StateError(error);
    return result['text']?.toString() ?? '';
  }

  Future<String> _officeText(File file, String extension) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final entries = <ArchiveFile>[];

    for (final entry in archive.files) {
      final entryPath = entry.name;
      final wanted = switch (extension) {
        'docx' => entryPath == 'word/document.xml' ||
            (entryPath.startsWith('word/') &&
                entryPath.endsWith('.xml') &&
                !entryPath.contains('/_rels/')),
        'xlsx' => entryPath == 'xl/sharedStrings.xml' ||
            (entryPath.startsWith('xl/worksheets/') &&
                entryPath.endsWith('.xml')),
        'pptx' =>
          entryPath.startsWith('ppt/slides/') && entryPath.endsWith('.xml'),
        _ => false,
      };
      if (wanted && entry.isFile) entries.add(entry);
    }

    entries.sort((a, b) => a.name.compareTo(b.name));
    final buffer = StringBuffer();
    for (final entry in entries) {
      final xml = utf8.decode(entry.content, allowMalformed: true);
      buffer.writeln(_xmlToText(xml));
      if (buffer.length >= _maxExtractedCharacters) break;
    }
    return buffer.toString();
  }

  String _xmlToText(String xml) {
    // Office XML uses tags to separate text runs. Strip those tags here;
    // unknown XML entities are intentionally retained rather than risking
    // malformed content or false text conversion.
    return xml.replaceAll(RegExp(r'<[^>]+>'), ' ');
  }

  String _normalizeText(String value) => value
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  Future<Map<String, dynamic>> prepareVideo(String path) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'prepareVideo',
      {'path': path, 'intervalMs': 3000},
    );
    return result ?? {'error': '视频预处理未返回结果'};
  }
}
