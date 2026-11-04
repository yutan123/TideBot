import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'chat_event_bus.dart';
import 'db.dart';
import 'media_storage_policy.dart';
import 'model_image.dart';

/// Persistent, serial storage conversion. In-flight sends keep their originals
/// until every reader releases its database lease (including other isolates).
class MediaStorageService {
  MediaStorageService._();
  static final instance = MediaStorageService._();
  final _owner =
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
  bool _running = false;
  Timer? _retry;
  ReceivePort? _updates;
  static const _portName = 'tidebot.media.storage.updates';

  void startForeground() {
    if (_updates != null) return;
    final port = ReceivePort();
    _updates = port;
    ui.IsolateNameServer.removePortNameMapping(_portName);
    ui.IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    port.listen((dynamic data) {
      if (data is! Map || data['owner'] == _owner || data['message'] is! Map)
        return;
      _publishUpdate(Map<String, dynamic>.from(data['message'] as Map),
          remote: false);
    });
    kick();
  }

  void _publishUpdate(Map<String, dynamic> message, {bool remote = true}) {
    ChatEventBus.instance.publish(ChatEvent(
      type: ChatEventType.updated,
      botId: message['bot_id']?.toString(),
      messageId: message['id']?.toString(),
      message: message,
    ));
    if (remote)
      ui.IsolateNameServer.lookupPortByName(_portName)?.send({
        'owner': _owner,
        'message': message,
      });
  }

  static Future<void> ensureSchema(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS media_storage_jobs (
      source TEXT PRIMARY KEY, target TEXT, type TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS media_storage_uses (
      id TEXT PRIMARY KEY, expires INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS media_storage_worker (
      id INTEGER PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL
    )''');
  }

  /// Called inside the message transaction, so a crash cannot lose the job.
  static Future<void> enqueue(
      DatabaseExecutor db, Map<String, dynamic> msg) async {
    final type = msg['type']?.toString();
    final source = msg['file_path']?.toString() ?? '';
    if (!const {'audio', 'video', 'image'}.contains(type) ||
        source.isEmpty ||
        !p.isAbsolute(source) ||
        source.contains('.tide-v1.')) return;
    final setting = await db.query('kv_store',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['${type}_compression_enabled']);
    if (setting.isNotEmpty && setting.first['value'] == 'false') return;
    await db.insert('media_storage_jobs', {'source': source, 'type': type},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  void kick() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), () {
      unawaited(_drain().catchError((Object error, StackTrace stack) {
        print('[media storage] $error');
        _later();
      }));
    });
  }

  void _later() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 10), kick);
  }

  Future<String> resolve(String source) async {
    final db = await DBManager().database;
    final rows = await db.query('media_storage_jobs',
        columns: ['target'],
        where: "source = ? AND state IN ('cleanup', 'done')",
        whereArgs: [source],
        limit: 1);
    final target = rows.isEmpty ? null : rows.first['target'] as String?;
    return target != null && await File(target).exists() ? target : source;
  }

  Future<T> withMediaUse<T>(Future<T> Function() action,
      {bool maintenance = false}) async {
    final db = await DBManager().database;
    final id =
        '${maintenance ? 'maintenance:' : ''}$_owner:${DateTime.now().microsecondsSinceEpoch}:${Random().nextInt(1 << 32)}';
    Future<void> renew() => db
        .insert(
            'media_storage_uses',
            {
              'id': id,
              'expires': DateTime.now().millisecondsSinceEpoch + 120000,
            },
            conflictAlgorithm: ConflictAlgorithm.replace)
        .then((_) {});
    await renew();
    final timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(renew().catchError((Object e) {
        print('[media lease] $e');
      }));
    });
    try {
      if (maintenance) {
        // Restore replaces the database and documents: wait for conversion.
        while ((await db.query('media_storage_worker',
                where: 'expires > ?',
                whereArgs: [DateTime.now().millisecondsSinceEpoch],
                limit: 1))
            .isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      return await action();
    } finally {
      timer.cancel();
      final current = await DBManager().database;
      await current
          .delete('media_storage_uses', where: 'id = ?', whereArgs: [id]);
      kick();
    }
  }

  Future<bool> _maintenance(DatabaseExecutor db) async =>
      (await db.query('media_storage_uses',
              where: "id LIKE 'maintenance:%' AND expires > ?",
              whereArgs: [DateTime.now().millisecondsSinceEpoch],
              limit: 1))
          .isNotEmpty;

  Future<bool> _claim(Database db) => db.transaction((txn) async {
        if (await _maintenance(txn)) return false;
        final now = DateTime.now().millisecondsSinceEpoch;
        final rows = await txn.query('media_storage_worker', where: 'id = 1');
        if (rows.isNotEmpty &&
            rows.first['owner'] != _owner &&
            (rows.first['expires'] as int) > now) return false;
        await txn.insert(
            'media_storage_worker',
            {
              'id': 1,
              'owner': _owner,
              'expires': now + 120000,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        return true;
      });

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    Database? db;
    Timer? heartbeat;
    try {
      db = await DBManager().database;
      if (!await _claim(db)) {
        _later();
        return;
      }
      final database = db;
      heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(database
            .update('media_storage_worker',
                {'expires': DateTime.now().millisecondsSinceEpoch + 120000},
                where: 'id = 1 AND owner = ?', whereArgs: [_owner])
            .catchError((Object e) {
          print('[media worker] $e');
          return 0;
        }));
      });
      while (true) {
        if (await _maintenance(db)) {
          _later();
          break;
        }
        final jobs = await db.query('media_storage_jobs',
            where: "state IN ('pending', 'ready', 'cleanup') AND attempts < 3",
            limit: 1);
        if (jobs.isEmpty) break;
        final job = jobs.first;
        final source = job['source'] as String;
        final type = job['type'] as String;
        String? target = job['target'] as String?;
        try {
          if (job['state'] != 'cleanup') {
            if (await DBManager().getKV('${type}_compression_enabled') ==
                'false') {
              if (target != null) await _remove(target);
              await db.update('media_storage_jobs', {'state': 'skipped'},
                  where: 'source = ?', whereArgs: [source]);
              continue;
            }
            // Never delete or replace a system gallery/recordings source.
            if (!await _owned(source)) {
              await db.update('media_storage_jobs', {'state': 'skipped'},
                  where: 'source = ?', whereArgs: [source]);
              continue;
            }
            if (job['state'] != 'ready' ||
                target == null ||
                !await File(target).exists()) {
              final directory = await getApplicationDocumentsDirectory();
              final folder =
                  Directory(p.join(directory.path, 'chat_media', 'compressed'));
              await folder.create(recursive: true);
              target ??= p.join(
                  folder.path,
                  '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}.tide-v1.${type == 'audio' ? 'm4a' : type == 'video' ? 'mp4' : 'jpg'}');
              await db.update('media_storage_jobs', {'target': target},
                  where: 'source = ?', whereArgs: [source]);
              final useful = await _convert(source, target, type);
              if (!useful) {
                await _remove(target);
                await db.update('media_storage_jobs', {'state': 'skipped'},
                    where: 'source = ?', whereArgs: [source]);
                continue;
              }
              await db.update('media_storage_jobs', {'state': 'ready'},
                  where: 'source = ?', whereArgs: [source]);
            }
            // Reference switching and reader admission serialize in SQLite.
            final swapped = await db.transaction((txn) async {
              final now = DateTime.now().millisecondsSinceEpoch;
              await txn.delete('media_storage_uses',
                  where: 'expires < ?', whereArgs: [now]);
              if ((await txn.query('media_storage_uses', limit: 1)).isNotEmpty)
                return false;
              final lock = await txn.query('media_storage_worker',
                  where: 'id = 1 AND owner = ?', whereArgs: [_owner]);
              if (lock.isEmpty) return false;
              await txn.update('chat_history', {'file_path': target},
                  where: 'file_path = ?', whereArgs: [source]);
              await txn.update('media_storage_jobs', {'state': 'cleanup'},
                  where: 'source = ?', whereArgs: [source]);
              return true;
            });
            if (!swapped) {
              _later();
              break;
            }
          }
          if (target == null || !await File(target).exists()) {
            throw StateError('压缩副本不可访问，保留原文件');
          }
          await _replaceVideoHistory(source, target);
          final messages = await db.query('chat_history',
              where: 'file_path = ?', whereArgs: [target]);
          for (final message in messages) {
            _publishUpdate(Map<String, dynamic>.from(message));
          }
          final cleaned = await db.transaction((txn) async {
            await txn.delete('media_storage_uses',
                where: 'expires < ?',
                whereArgs: [DateTime.now().millisecondsSinceEpoch]);
            if ((await txn.query('media_storage_uses', limit: 1)).isNotEmpty)
              return false;
            if (!await _otherReference(txn, source) &&
                !await _preferenceReference(source)) await _remove(source);
            await txn.update('media_storage_jobs', {'state': 'done'},
                where: 'source = ?', whereArgs: [source]);
            return true;
          });
          if (!cleaned) {
            _later();
            break;
          }
        } catch (error) {
          // A half-written output is never reused after a failed attempt.
          final current = await db.query('media_storage_jobs',
              columns: ['state'], where: 'source = ?', whereArgs: [source]);
          if (current.first['state'] == 'pending' && target != null)
            await _remove(target);
          await db.rawUpdate(
              'UPDATE media_storage_jobs SET attempts = attempts + 1 WHERE source = ?',
              [source]);
          print('[media storage] 转换失败，保留原文件: $error');
          _later();
          break;
        }
      }
    } finally {
      heartbeat?.cancel();
      try {
        if (db != null) {
          await db.delete('media_storage_worker',
              where: 'id = 1 AND owner = ?', whereArgs: [_owner]);
        }
      } finally {
        _running = false;
      }
    }
  }

  Future<bool> _owned(String source) async {
    final path = await File(source).resolveSymbolicLinks();
    for (final root in [
      await getApplicationDocumentsDirectory(),
      await getTemporaryDirectory(),
      await getApplicationSupportDirectory()
    ]) {
      if (p.isWithin(await root.resolveSymbolicLinks(), path)) return true;
    }
    return false;
  }

  Future<bool> _otherReference(DatabaseExecutor db, String source) async {
    // Chat paths were switched above. Preserve files also used by avatars,
    // stickers, memories or settings instead of breaking those references.
    final tables = await db
        .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    for (final table in tables) {
      final name = table['name'] as String;
      if (name.startsWith('media_storage_') || name.startsWith('sqlite_'))
        continue;
      final quoted = '"${name.replaceAll('"', '""')}"';
      final columns = await db.rawQuery('PRAGMA table_info($quoted)');
      for (final column in columns) {
        if (!(column['type'] as String).toUpperCase().contains('TEXT'))
          continue;
        final key = '"${(column['name'] as String).replaceAll('"', '""')}"';
        if ((await db.rawQuery(
                'SELECT 1 FROM $quoted WHERE $key = ? OR instr($key, ?) > 0 LIMIT 1',
                [source, jsonEncode(source)]))
            .isNotEmpty) return true;
      }
    }
    return false;
  }

  Future<bool> _preferenceReference(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value == source || jsonEncode(value).contains(jsonEncode(source)))
        return true;
    }
    return false;
  }

  Future<void> _replaceVideoHistory(String source, String target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    for (final key
        in prefs.getKeys().where((key) => key.startsWith('video_history_'))) {
      final history = prefs.getStringList(key);
      if (history == null) continue;
      bool changed = false;
      final updated = history.map((raw) {
        final data = jsonDecode(raw);
        if (data is! Map) return raw;
        for (final field in ['original_video_path', 'audio_path']) {
          if (data[field] == source) {
            data[field] = target;
            changed = true;
          }
        }
        return jsonEncode(data);
      }).toList();
      if (changed) await prefs.setStringList(key, updated);
    }
  }

  Future<bool> _convert(String source, String target, String type) async {
    if (type == 'image') {
      // Keep animated pictures intact, rather than silently flattening them.
      if (!const {'.heic', '.heif'}
          .contains(p.extension(source).toLowerCase())) {
        final codec =
            await ui.instantiateImageCodec(await File(source).readAsBytes());
        try {
          if (codec.frameCount > 1) return false;
        } finally {
          codec.dispose();
        }
      }
      await File(target)
          .writeAsBytes(await modelImageBytes(source), flush: true);
    } else {
      final before = await _probe(source);
      final streams = before['streams'] as List? ?? [];
      final audio = streams
          .cast<Map>()
          .where((s) => s['codec_type'] == 'audio')
          .firstOrNull;
      final video = streams
          .cast<Map>()
          .where((s) => s['codec_type'] == 'video')
          .firstOrNull;
      final arguments = type == 'audio'
          ? audioStorageArguments((audio?['channels'] as num?)?.toInt() ?? 1,
              int.tryParse('${audio?['sample_rate']}') ?? 48000)
          : videoStorageArguments(_frameRate(video?['avg_frame_rate']));
      await _execute([
        '-y',
        '-threads',
        '2',
        '-i',
        source,
        ...arguments,
        '-threads',
        '2',
        target
      ]);
      await _execute(
          ['-v', 'error', '-xerror', '-i', target, '-f', 'null', '-']);
      final after = await _probe(target);
      if (!mediaDurationMatches(_duration(before), _duration(after)))
        throw const FormatException('压缩前后时长不一致');
      final output = (after['streams'] as List? ?? []).cast<Map>();
      if (audio != null && !output.any((s) => s['codec_type'] == 'audio'))
        throw const FormatException('压缩后音轨缺失');
      if (type == 'video' && !output.any((s) => s['codec_type'] == 'video'))
        throw const FormatException('压缩后画面缺失');
    }
    return await File(target).length() > 0 &&
        await File(target).length() < await File(source).length();
  }

  static double _frameRate(dynamic value) {
    final parts = '$value'.split('/');
    final a = double.tryParse(parts.first) ?? 0;
    final b = parts.length == 2 ? double.tryParse(parts.last) ?? 1 : 1;
    return b == 0 ? 0 : a / b;
  }

  static double _duration(Map info) =>
      double.tryParse('${(info['format'] as Map?)?['duration']}') ?? 0;
  static Future<Map> _probe(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation()?.getAllProperties();
    if (info == null) throw const FormatException('无法读取媒体信息');
    return info;
  }

  static Future<void> _execute(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    if (!ReturnCode.isSuccess(await session.getReturnCode()))
      throw const FormatException('媒体格式转换失败');
  }

  static Future<void> _remove(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Base64 is a transport encoding, not an audio format. Chat audio endpoints
  /// receive real PCM WAV bytes; the compact M4A stays untouched on disk.
  Future<Uint8List> chatAudioBytes(String path) =>
      withRequestAudio(path, (file) => File(file).readAsBytes(),
          forceWav: true);

  Future<T> withRequestAudio<T>(String path, Future<T> Function(String) send,
          {bool forceWav = false}) =>
      withMediaUse(() async {
        final source = await resolve(path);
        final extension = p.extension(source).toLowerCase();
        if ((!forceWav &&
                const {'.wav', '.mp3', '.m4a', '.mp4', '.webm', '.ogg', '.flac'}
                    .contains(extension)) ||
            extension == '.wav') return send(source);
        final root = await getTemporaryDirectory();
        final file =
            '${root.path}/request_audio_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}.wav';
        try {
          await _execute([
            '-y',
            '-i',
            source,
            '-vn',
            '-c:a',
            'pcm_s16le',
            '-ar',
            '16000',
            '-ac',
            '1',
            file
          ]);
          return await send(file);
        } finally {
          await _remove(file);
        }
      });

  Future<T> withRequestVideo<T>(String path, Future<T> Function(String) send) =>
      withMediaUse(() async {
        final source = await resolve(path);
        final info = await _probe(source);
        final streams = (info['streams'] as List? ?? []).cast<Map>();
        if (p.extension(source).toLowerCase() == '.mp4' &&
            streams.any((s) =>
                s['codec_type'] == 'video' && s['codec_name'] == 'h264') &&
            streams
                .where((s) => s['codec_type'] == 'audio')
                .every((s) => s['codec_name'] == 'aac')) return send(source);
        final root = await getTemporaryDirectory();
        final file =
            '${root.path}/request_video_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}.mp4';
        try {
          await _execute([
            '-y',
            '-i',
            source,
            ...videoStorageArguments(_frameRate(streams
                .where((s) => s['codec_type'] == 'video')
                .firstOrNull?['avg_frame_rate'])),
            file
          ]);
          return await send(file);
        } finally {
          await _remove(file);
        }
      });
}
