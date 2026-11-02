import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'data_transfer.dart';
import 'json_records.dart';
import 'db.dart';

class FullBackupService {
  static const _dbName = 'tidebot.db';

  static Future<({String name, File file})> create() async {
    final work = await DataTransfer.workspace();
    try {
      final db = await DBManager().database;
      final dbPath = '${await getDatabasesPath()}/$_dbName';
      final snapshot = File('${work.path}/$_dbName');
      final docs = await getApplicationDocumentsDirectory();
      final files = <String, String>{'tidebot.db': snapshot.path};
      if (await docs.exists()) {
        await for (final item in docs.list(
          recursive: true,
          followLinks: false,
        )) {
          if (item is! File) continue;
          final relative = p.relative(item.path, from: docs.path);
          if (relative == 'tidebot_dev_logs.json' ||
              relative.startsWith('TideBot/exports/'))
            continue;
          files['documents/$relative'] = item.path;
        }
      }
      final dbSize = await File(dbPath).length();
      final wal = File('$dbPath-wal');
      final walSize = await wal.exists() ? await wal.length() : 0;
      await DataTransfer.ensureSpace(
        work,
        await DataTransfer.totalBytes(
              files.values.where((v) => v != snapshot.path),
            ) +
            2 * (dbSize + walSize),
      );
      // Freeze writers while copying DB and WAL; works with older SQLite too.
      await db.transaction((txn) async {
        await File(dbPath).copy(snapshot.path);
        if (await wal.exists()) await wal.copy('${snapshot.path}-wal');
      }, exclusive: true);
      final copy = await openDatabase(snapshot.path, singleInstance: false);
      try {
        final result = await copy.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        if (result.isNotEmpty && (result.first.values.first as num) != 0) {
          throw StateError('数据库快照忙，请稍后重试');
        }
      } finally {
        await copy.close();
      }
      final prefs = await SharedPreferences.getInstance();
      final preferences = File('${work.path}/preferences.json');
      final sink = preferences.openWrite();
      try {
        sink.write('{');
        var first = true;
        for (final key in prefs.getKeys()) {
          if (!first) sink.write(',');
          first = false;
          sink.write('${jsonEncode(key)}:${jsonEncode(prefs.get(key))}');
          await sink.flush();
        }
        sink.write('}');
      } finally {
        await sink.close();
      }
      files['preferences.json'] = preferences.path;
      final name =
          'tidebot_backup_${DateTime.now().millisecondsSinceEpoch}.zip';
      final file = File('${work.path}/$name');
      await DataTransfer.ensureSpace(
        work,
        await DataTransfer.totalBytes(files.values),
      );
      await DataTransfer.zip(file.path, files);
      return (name: name, file: file);
    } catch (_) {
      await work.delete(recursive: true);
      rethrow;
    }
  }

  static Future<bool> export() => DataTransfer.exclusive(() async {
    final backup = await create();
    try {
      return await DataTransfer.save(
            backup.file,
            backup.name,
            'application/zip',
          ) !=
          null;
    } finally {
      await backup.file.parent.delete(recursive: true);
    }
  });

  static Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static Future<bool> restore() => DataTransfer.exclusive(() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return false;
    final work = await DataTransfer.workspace();
    var preserveRecovery = false;
    try {
      await DataTransfer.extract(path, work.path);
      final source = File('${work.path}/$_dbName');
      final preferences = File('${work.path}/preferences.json');
      if (!await source.exists() || !await preferences.exists()) {
        throw const FormatException('不是有效的 TideBot 完整备份');
      }
      // Validate one preference at a time; retaining the complete decoded map
      // doubled the live preferences during a full restore.
      await for (final record in JsonRecords.read(
        preferences,
        arrays: const {},
      )) {
        final value = record.value;
        if (value is! bool &&
            value is! num &&
            value is! String &&
            !(value is List && value.every((item) => item is String))) {
          throw const FormatException('备份设置格式无效');
        }
      }
      final check = await openDatabase(
        source.path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        final result = await check.rawQuery('PRAGMA quick_check');
        if (result.length != 1 || result.first.values.first != 'ok') {
          throw const FormatException('备份数据库损坏');
        }
      } finally {
        await check.close();
      }
      final dbPath = '${await getDatabasesPath()}/$_dbName';
      final docs = await getApplicationDocumentsDirectory();
      await DataTransfer.ensureSpace(
        docs,
        await DataTransfer.directoryBytes(work),
      );
      final prefs = await SharedPreferences.getInstance();
      final oldPrefs = File('${work.path}/old_preferences.json');
      final oldSink = oldPrefs.openWrite();
      try {
        oldSink.write('{');
        var first = true;
        for (final key in prefs.getKeys()) {
          if (!first) oldSink.write(',');
          first = false;
          oldSink.write('${jsonEncode(key)}:${jsonEncode(prefs.get(key))}');
          await oldSink.flush();
        }
        oldSink.write('}');
      } finally {
        await oldSink.close();
      }
      final rollback = Directory('${work.path}/rollback');
      await rollback.create();
      await DBManager().close();
      var movedDatabase = false;
      var movedDocuments = false;
      try {
        for (final suffix in ['', '-wal', '-shm']) {
          final file = File('$dbPath$suffix');
          if (await file.exists())
            await file.rename('${rollback.path}/db$suffix');
        }
        movedDatabase = true;
        await source.copy(dbPath);
        if (await docs.exists()) {
          await docs.rename('${rollback.path}/documents');
          movedDocuments = true;
        }
        await docs.create(recursive: true);
        final restored = Directory('${work.path}/documents');
        if (await restored.exists())
          await DataTransfer.copyDirectory(restored, docs);
        await _setPreferences(prefs, preferences);
      } catch (_) {
        try {
          await DBManager().close();
          if (movedDatabase) {
            for (final suffix in ['', '-wal', '-shm']) {
              await _deleteIfExists('$dbPath$suffix');
            }
          }
          for (final suffix in ['', '-wal', '-shm']) {
            final old = File('${rollback.path}/db$suffix');
            if (await old.exists()) await old.rename('$dbPath$suffix');
          }
          if (movedDocuments) {
            if (await docs.exists()) await docs.delete(recursive: true);
            await Directory('${rollback.path}/documents').rename(docs.path);
          }
          await _setPreferences(prefs, oldPrefs);
        } catch (_) {
          preserveRecovery = true;
          throw StateError('恢复中断，原始数据保留在 ${rollback.path}，请勿清理缓存');
        }
        rethrow;
      }
      return true;
    } finally {
      if (!preserveRecovery) await work.delete(recursive: true);
    }
  });

  static Future<void> _setPreferences(
    SharedPreferences prefs,
    File values,
  ) async {
    if (!await prefs.clear()) throw StateError('无法清理旧设置');
    await for (final entry in JsonRecords.read(values, arrays: const {})) {
      final key = entry.key;
      final value = entry.value;
      bool saved;
      if (value is bool) {
        saved = await prefs.setBool(key, value);
      } else if (value is int) {
        saved = await prefs.setInt(key, value);
      } else if (value is double) {
        saved = await prefs.setDouble(key, value);
      } else if (value is String) {
        saved = await prefs.setString(key, value);
      } else if (value is List && value.every((item) => item is String)) {
        saved = await prefs.setStringList(key, value.cast<String>());
      } else {
        throw const FormatException('备份设置格式无效');
      }
      if (!saved) throw StateError('无法恢复设置：$key');
    }
  }
}
