import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'data_transfer.dart';
import 'json_records.dart';
import 'transfer_media.dart';
import 'db.dart';

class FullBackupService {
  static const _dbName = 'tidebot.db';
  static const _native = MethodChannel('tidebot.native.channel');
  static Future<void> restartToApply() =>
      _native.invokeMethod<void>('restartForRestore');

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
              relative.startsWith('TideBot/exports/')) continue;
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

  static Future<bool> restore() => DataTransfer.exclusive(() async {
        return await DataTransfer.pickImport<bool>(const ['zip'], (path) async {
              final work = await DataTransfer.workspace();
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
                      !(value is List &&
                          value.every((item) => item is String))) {
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
                final docs = await getApplicationDocumentsDirectory();
                final restoredPaths = RestoredDocuments(
                  Directory('${work.path}/documents'),
                  docs,
                );
                await _relocateDatabase(source, restoredPaths.mapPath);
                final mappedPreferences = File(
                  '${work.path}/restored_preferences.json',
                );
                final mappedSink = mappedPreferences.openWrite();
                try {
                  mappedSink.write('{');
                  var first = true;
                  await for (final record in JsonRecords.read(
                    preferences,
                    arrays: const {},
                  )) {
                    if (!first) mappedSink.write(',');
                    first = false;
                    final value = await mapTransferValue(
                      record.value,
                      restoredPaths.mapPath,
                    );
                    mappedSink.write(
                      '${jsonEncode(record.key)}:${jsonEncode(value)}',
                    );
                    await mappedSink.flush();
                  }
                  mappedSink.write('}');
                } finally {
                  await mappedSink.close();
                }
                await DataTransfer.ensureSpace(
                  docs,
                  await DataTransfer.directoryBytes(work),
                );
                await _requireReauthorization(source);
                await _native.invokeMethod<bool>(
                    'stageFullRestore', {'path': work.path});
                return true;
              } finally {
                await work.delete(recursive: true);
              }
            }) ??
            false;
      });

  // Rewrite only the extracted snapshot, before touching live data. Bounded
  // pages keep large chat databases from being retained in memory.
  static Future<void> _relocateDatabase(
    File source,
    Future<String> Function(String) mapPath,
  ) async {
    final db = await openDatabase(source.path, singleInstance: false);
    String quote(String name) => '"${name.replaceAll('"', '""')}"';
    try {
      await db.transaction((txn) async {
        final tables = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        );
        for (final table in tables) {
          final tableName = table['name'] as String;
          final name = quote(tableName);
          // Process-local leases must never survive restoration.
          if (tableName == 'media_storage_uses' ||
              tableName == 'media_storage_worker') {
            await txn.delete(tableName);
            continue;
          }
          var offset = 0;
          while (true) {
            final rows = await txn.rawQuery(
              'SELECT rowid AS "__transfer_rowid__", * FROM $name ORDER BY rowid LIMIT 100 OFFSET ?',
              [offset],
            );
            if (rows.isEmpty) break;
            for (final row in rows) {
              final updates = <String, Object?>{};
              for (final entry in row.entries) {
                if (entry.key == '__transfer_rowid__' || entry.value is! String)
                  continue;
                final mapped = await mapTransferValue(entry.value, mapPath);
                if (mapped != entry.value) updates[entry.key] = mapped;
              }
              if (updates.isNotEmpty) {
                await txn.rawUpdate(
                  'UPDATE $name SET ${updates.keys.map((key) => '${quote(key)} = ?').join(', ')} WHERE rowid = ?',
                  [...updates.values, row['__transfer_rowid__']],
                );
              }
            }
            offset += rows.length;
          }
        }
      });
      final result = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      if (result.isNotEmpty && result.first.values.first != 0) {
        throw StateError('恢复数据库忙，请稍后重试');
      }
    } finally {
      await db.close();
    }
  }

  static Future<void> _requireReauthorization(File source) async {
    final db = await openDatabase(source.path, singleInstance: false);
    try {
      final tables = (await db
              .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((row) => row['name'])
          .toSet();
      await db.transaction((txn) async {
        if (tables.contains('mcp_servers')) {
          await txn.update('mcp_servers', {
            'enabled': 0,
            'status': 'disconnected',
            'error': '备份不包含安全存储凭据，请重新填写鉴权信息后启用'
          });
        }
        if (tables.contains('skill_tools')) {
          await txn.update('skill_tools', {'enabled': 0, 'authorized': 0},
              where: "executor IN ('http', 'mcp_proxy')");
        }
        if (tables.contains('voice_call_records')) {
          await txn.update('voice_call_records', {'status': 'ended'},
              where: "status IN ('ringing', 'active')");
          await txn.update(
              'chat_history', {'call_status': 'ended', 'content': '[语音通话，已结束]'},
              where:
                  "type = 'voice_call_card' AND call_status IN ('ringing', 'active')");
        }
      });
      final checkpoint = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      if (checkpoint.isNotEmpty && checkpoint.first.values.first != 0) {
        throw StateError('备份数据库忙，请重新导入');
      }
    } finally {
      await db.close();
    }
  }
}
