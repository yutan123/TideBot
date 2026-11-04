import 'media_storage_service.dart';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'transfer_archive.dart';
import 'transfer_import_cache.dart';
import 'package:path_provider/path_provider.dart';

/// Only file paths cross the platform channel; file contents never do.
class DataTransfer {
  static const _channel = MethodChannel('tidebot.data_transfer');
  static bool _busy = false;
  static bool get isBusy => _busy;

  static Future<T> exclusive<T>(Future<T> Function() action) async {
    if (_busy) throw StateError('正在导入或导出数据，请等待完成');
    _busy = true;
    try {
      return await MediaStorageService.instance.withMediaUse(action, maintenance: true);
    } finally {
      _busy = false;
    }
  }

  /// Keeps the provider's cached input only while the importer is reading it.
  static Future<T?> pickImport<T>(
    List<String> extensions,
    Future<T> Function(String path) read,
  ) async {
    final temporary = await getTemporaryDirectory();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return null;
    return consumePickedImport(path, temporary, () => read(path));
  }

  static Future<Directory> workspace() async =>
      (await getTemporaryDirectory()).createTemp('tidebot_transfer_');

  static Future<String?> save(File file, String name, String mime) =>
      _channel.invokeMethod<String>('save', {
        'path': file.path,
        'name': name,
        'mime': mime,
      });

  static Future<void> zip(String destination, Map<String, String> files) =>
      Isolate.run(() => writeTransferZip(destination, files));

  static Future<int> totalBytes(Iterable<String> paths) async {
    var total = 0;
    for (final path in paths) {
      total += await File(path).length();
    }
    return total;
  }

  static Future<int> directoryBytes(Directory directory) async {
    var total = 0;
    await for (final item in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (item is File) total += await item.length();
    }
    return total;
  }

  static Future<void> ensureSpace(Directory directory, int needed) async {
    if (!await directory.exists()) await directory.create(recursive: true);
    final free = await _channel.invokeMethod<int>('freeSpace', {
      'path': directory.path,
    });
    // ZIP headers, growing metadata and a reserve for normal application work.
    if (free == null || free < needed + needed ~/ 20 + 32 * 1024 * 1024) {
      throw FileSystemException('存储空间不足，请释放空间后重试', directory.path);
    }
  }

  static Future<void> copyDirectory(Directory source, Directory target) async {
    await for (final item in source.list(recursive: true, followLinks: false)) {
      if (item is! File) continue;
      final file = File(
        p.join(target.path, p.relative(item.path, from: source.path)),
      );
      await file.parent.create(recursive: true);
      await item.copy(file.path);
    }
  }

  static Future<void> extract(String source, String destination) async {
    final size = await Isolate.run(() => transferZipSize(source));
    await ensureSpace(Directory(destination), size);
    await Isolate.run(() => extractTransferZip(source, destination));
  }
}
