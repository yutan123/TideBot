import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';

class FullBackupService {
  static const _dbName = 'tidebot.db';

  static Future<({String name, List<int> bytes})> create() async {
    final db = await DBManager().database;
    await db.execute('PRAGMA wal_checkpoint(FULL)');
    final dbPath = '${await getDatabasesPath()}/$_dbName';
    final archive = Archive();
    final dbBytes = await File(dbPath).readAsBytes();
    archive.addFile(ArchiveFile('tidebot.db', dbBytes.length, dbBytes));
    final prefs = await SharedPreferences.getInstance();
    final values = <String, dynamic>{};
    for (final key in prefs.getKeys()) values[key] = prefs.get(key);
    final preferencesBytes = utf8.encode(jsonEncode(values));
    archive.addFile(ArchiveFile(
        'preferences.json', preferencesBytes.length, preferencesBytes));
    final docs = await getApplicationDocumentsDirectory();
    if (await docs.exists()) {
      await for (final item in docs.list(recursive: true, followLinks: false)) {
        if (item is! File || item.path.endsWith('tidebot_dev_logs.json'))
          continue;
        final relative = item.path.substring(docs.path.length + 1);
        final fileBytes = await item.readAsBytes();
        archive.addFile(
            ArchiveFile('documents/$relative', fileBytes.length, fileBytes));
      }
    }
    return (
      name: 'tidebot_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
      bytes: ZipEncoder().encode(archive),
    );
  }

  static Future<void> export() async {
    final backup = await create();
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: '导出 TideBot 完整备份',
      fileName: backup.name,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: Uint8List.fromList(backup.bytes),
    );
    if (saved == null) throw StateError('已取消导出');
  }

  static Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static Future<void> _clearDirectory(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final item in directory.list(followLinks: false)) {
      await item.delete(recursive: true);
    }
  }

  static Future<void> restore() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    final path = picked?.files.single.path;
    if (bytes == null && path == null) throw StateError('未选择备份文件');
    final archive =
        ZipDecoder().decodeBytes(bytes ?? await File(path!).readAsBytes());
    final dbEntry = archive.findFile('tidebot.db');
    final prefsEntry = archive.findFile('preferences.json');
    if (dbEntry == null || prefsEntry == null)
      throw const FormatException('不是有效的 TideBot 完整备份');
    await DBManager().close();
    final dbPath = '${await getDatabasesPath()}/$_dbName';
    await _deleteIfExists(dbPath);
    await _deleteIfExists('$dbPath-wal');
    await _deleteIfExists('$dbPath-shm');
    await File(dbPath).writeAsBytes(dbEntry.content as List<int>, flush: true);
    final docs = await getApplicationDocumentsDirectory();
    await _clearDirectory(docs);
    await docs.create(recursive: true);
    for (final entry in archive.files
        .where((e) => e.name.startsWith('documents/') && e.isFile)) {
      final relative = entry.name.substring('documents/'.length);
      if (relative.isEmpty || relative.contains('..')) continue;
      final file = File('${docs.path}/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content as List<int>, flush: true);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final raw = jsonDecode(utf8.decode(prefsEntry.content as List<int>)) as Map;
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is bool)
        await prefs.setBool(entry.key, value);
      else if (value is int)
        await prefs.setInt(entry.key, value);
      else if (value is double)
        await prefs.setDouble(entry.key, value);
      else if (value is String)
        await prefs.setString(entry.key, value);
      else if (value is List)
        await prefs.setStringList(
            entry.key, value.map((e) => e.toString()).toList());
    }
  }
}
