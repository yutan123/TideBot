import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// 标准化的 token 估算（当 API 未返回 usage 时的近似值，而非真实记账）。
///
/// 采用与 cl100k 接近的中英文分层规则：
/// - CJK（中文/日文/韩文等）约占 0.6 token/字符（cl100k 中中文约 1.7 字符/token）；
/// - 其余（英文、数字、常用符号）约占 0.25 token/字符（约 4 字符/token）。
/// 空串返回 0，永远返回 >= 0 的整数。仅供估算，不做精确记账。
int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  var cjk = 0;
  var rest = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x4E00 && rune <= 0x9FFF) || // CJK 统一表意文字
        (rune >= 0x3400 && rune <= 0x4DBF) || // 扩展 A
        (rune >= 0x3040 && rune <= 0x30FF) || // 日文假名
        (rune >= 0xAC00 && rune <= 0xD7AF) || // 韩文音节
        (rune >= 0xF900 && rune <= 0xFAFF) || // CJK 兼容表意文字
        (rune >= 0x20000 && rune <= 0x2FA1F)) {
      // 扩展 B-F
      cjk++;
    } else {
      rest++;
    }
  }
  final cjkTokens = cjk / 1.7;
  final restTokens = rest / 4.0;
  return (cjkTokens + restTokens).ceil();
}

class DBManager {
  static final DBManager _instance = DBManager._internal();
  factory DBManager() => _instance;
  DBManager._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  // 严格落实 6 大核心表与外键级联约束
  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'tidebot.db');
    return await openDatabase(
      path,
      version: 18,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bots (
            id TEXT PRIMARY KEY, name TEXT, desc TEXT, prompt TEXT,
            avatar TEXT, chat_model TEXT, stt_model TEXT, tts_model TEXT,
            max_tokens INTEGER, created_at INTEGER, daily_quote TEXT,
            last_msg_time INTEGER, is_pinned INTEGER DEFAULT 0,
            last_read_at INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_history (
            id TEXT PRIMARY KEY, bot_id TEXT, role TEXT, type TEXT,
            content TEXT, file_path TEXT, mood TEXT, duration INTEGER,
            error_log TEXT, error_code TEXT, error_message TEXT, reply_to_id TEXT, sources_json TEXT, timestamp INTEGER,

            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE memories (
            id TEXT PRIMARY KEY, bot_id TEXT, title TEXT DEFAULT '', type TEXT,
            content TEXT, category TEXT DEFAULT 'fact', importance INTEGER DEFAULT 3,
            expires_at INTEGER, timestamp INTEGER, updated_at INTEGER,
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE schedule_tasks (
            id TEXT PRIMARY KEY, bot_id TEXT, title TEXT, note TEXT, time INTEGER, is_done INTEGER, frequency TEXT DEFAULT 'once', prompt TEXT DEFAULT '', run_at INTEGER, status TEXT DEFAULT 'pending',
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE bot_life_schedules (
            id TEXT PRIMARY KEY, bot_id TEXT NOT NULL, date_key TEXT NOT NULL,
            theme TEXT DEFAULT '', mood TEXT DEFAULT '', outfit_style TEXT DEFAULT '',
            outfit TEXT DEFAULT '', timeline_json TEXT DEFAULT '[]',
            generated_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
            UNIQUE(bot_id, date_key),
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE posts (
            id TEXT PRIMARY KEY, author_id TEXT, content TEXT, image_path TEXT,
            likes INTEGER DEFAULT 0, comments INTEGER DEFAULT 0,
            user_liked INTEGER DEFAULT 0, user_collected INTEGER DEFAULT 0,
            timestamp INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE post_comments (
            id TEXT PRIMARY KEY, post_id TEXT NOT NULL, author_id TEXT,
            content TEXT NOT NULL, parent_id TEXT, timestamp INTEGER,
            FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE kv_store (
            key TEXT PRIMARY KEY, value TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE stickers (
            id TEXT PRIMARY KEY, emotion TEXT NOT NULL, file_path TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE feed_events (
            id TEXT PRIMARY KEY, post_id TEXT NOT NULL, actor_id TEXT NOT NULL,
            event_type TEXT NOT NULL, timestamp INTEGER NOT NULL,
            UNIQUE(post_id, actor_id, event_type),
            FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE ai_usage_events (
            id TEXT PRIMARY KEY, bot_id TEXT, event_type TEXT NOT NULL,
            prompt_tokens INTEGER NOT NULL DEFAULT 0,
            completion_tokens INTEGER NOT NULL DEFAULT 0,
            total_tokens INTEGER NOT NULL DEFAULT 0,
            reply_count INTEGER NOT NULL DEFAULT 0, timestamp INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE bots ADD COLUMN avatar TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE bots ADD COLUMN daily_quote TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE schedule_tasks ADD COLUMN note TEXT');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE posts ADD COLUMN likes INTEGER DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE posts ADD COLUMN comments INTEGER DEFAULT 0');
          } catch (_) {}
          try {
            await db
                .execute('ALTER TABLE bots ADD COLUMN last_msg_time INTEGER');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE bots ADD COLUMN is_pinned INTEGER DEFAULT 0');
          } catch (_) {}
        }
        if (oldVersion < 4) {
          try {
            await db.execute(
                'ALTER TABLE chat_history ADD COLUMN duration INTEGER');
          } catch (_) {}
        }
        if (oldVersion < 5) {
          try {
            await db.execute(
                'ALTER TABLE posts ADD COLUMN user_liked INTEGER DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE posts ADD COLUMN user_collected INTEGER DEFAULT 0');
          } catch (_) {}
          await db.execute('''
            CREATE TABLE IF NOT EXISTS post_comments (
              id TEXT PRIMARY KEY, post_id TEXT NOT NULL, author_id TEXT,
              content TEXT NOT NULL, parent_id TEXT, timestamp INTEGER,
              FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 6) {
          try {
            await db
                .execute('ALTER TABLE chat_history ADD COLUMN error_log TEXT');
          } catch (_) {}
          try {
            await db
                .execute('ALTER TABLE chat_history ADD COLUMN error_code TEXT');
          } catch (_) {}
        }
        if (oldVersion < 7) {
          try {
            await db.execute(
                'ALTER TABLE chat_history ADD COLUMN error_message TEXT');
          } catch (_) {}
        }
        if (oldVersion < 8) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS feed_events (
              id TEXT PRIMARY KEY, post_id TEXT NOT NULL, actor_id TEXT NOT NULL,
              event_type TEXT NOT NULL, timestamp INTEGER NOT NULL,
              UNIQUE(post_id, actor_id, event_type),
              FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 9) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS ai_usage_events (
              id TEXT PRIMARY KEY, bot_id TEXT, event_type TEXT NOT NULL,
              prompt_tokens INTEGER NOT NULL DEFAULT 0,
              completion_tokens INTEGER NOT NULL DEFAULT 0,
              total_tokens INTEGER NOT NULL DEFAULT 0,
              reply_count INTEGER NOT NULL DEFAULT 0, timestamp INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 10) {
          try {
            await db.execute(
                'ALTER TABLE chat_history ADD COLUMN reply_to_id TEXT');
          } catch (_) {}
        }
        if (oldVersion < 11) {
          try {
            await db.execute(
                'ALTER TABLE chat_history ADD COLUMN sources_json TEXT');
          } catch (_) {}
          await db.execute('''
            CREATE TABLE IF NOT EXISTS stickers (
              id TEXT PRIMARY KEY, emotion TEXT NOT NULL, file_path TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 12) {
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_stickers_emotion ON stickers(emotion)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_chat_history_bot_timestamp ON chat_history(bot_id, timestamp)');
        }
        if (oldVersion < 13) {
          try {
            await db.execute(
                "ALTER TABLE memories ADD COLUMN category TEXT DEFAULT 'fact'");
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE memories ADD COLUMN importance INTEGER DEFAULT 3');
          } catch (_) {}
          try {
            await db
                .execute('ALTER TABLE memories ADD COLUMN expires_at INTEGER');
          } catch (_) {}
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_memories_bot_type_timestamp ON memories(bot_id, type, timestamp)');
        }
        if (oldVersion < 16) {
          try {
            await db
                .execute('ALTER TABLE memories ADD COLUMN updated_at INTEGER');
          } catch (_) {}
          await db.execute(
              'UPDATE memories SET updated_at = timestamp WHERE updated_at IS NULL');
        }
        if (oldVersion < 17) {
          try {
            await db
                .execute('ALTER TABLE post_comments ADD COLUMN parent_id TEXT');
          } catch (_) {}
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_post_comments_parent ON post_comments(post_id, parent_id, timestamp)');
        }
        if (oldVersion < 18) {
          try {
            await db.execute(
                'ALTER TABLE bots ADD COLUMN last_read_at INTEGER DEFAULT 0');
          } catch (_) {}
        }
        if (oldVersion < 15) {
          for (final column in [
            "frequency TEXT DEFAULT 'once'",
            "prompt TEXT DEFAULT ''",
            'run_at INTEGER',
            "status TEXT DEFAULT 'pending'"
          ]) {
            try {
              await db.execute('ALTER TABLE schedule_tasks ADD COLUMN $column');
            } catch (_) {}
          }
          try {
            await db.update('memories', {'type': 'long'},
                where: 'type = ?', whereArgs: ['medium']);
          } catch (_) {}
        }
        if (oldVersion < 14) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS bot_life_schedules (
              id TEXT PRIMARY KEY, bot_id TEXT NOT NULL, date_key TEXT NOT NULL,
              theme TEXT DEFAULT '', mood TEXT DEFAULT '', outfit_style TEXT DEFAULT '',
              outfit TEXT DEFAULT '', timeline_json TEXT DEFAULT '[]',
              generated_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
              UNIQUE(bot_id, date_key),
              FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
            )
          ''');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_life_schedule_bot_date ON bot_life_schedules(bot_id, date_key)');
        }
      },
    );
  }

  // ================= 拟人化日程 =================
  Future<Map<String, dynamic>?> getLifeSchedule(
      String botId, String dateKey) async {
    final db = await database;
    final rows = await db.query('bot_life_schedules',
        where: 'bot_id = ? AND date_key = ?',
        whereArgs: [botId, dateKey],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertLifeSchedule(Map<String, dynamic> schedule) async {
    final db = await database;
    await db.insert('bot_life_schedules', schedule,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ================= Bots CRUD =================
  Future<List<Map<String, dynamic>>> getAllBots() async {
    final db = await database;
    return await db.query('bots', orderBy: 'created_at DESC');
  }

  Future<void> insertBot(Map<String, dynamic> bot) async {
    final db = await database;
    await db.insert('bots', bot, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns a single bot for notification deep links, or null if it was deleted.
  Future<Map<String, dynamic>?> getBotById(String id) async {
    final db = await database;
    final rows =
        await db.query('bots', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateBot(String id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update('bots', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBot(String id) async {
    final db = await database;
    // 级联删除会同步清空该 bot 的聊天和记忆
    await db.delete('bots', where: 'id = ?', whereArgs: [id]);
  }

  // ================= 消息流管理 =================
  Future<void> updateMessageContent(String id, String content) async {
    final db = await database;
    await db.update(
      'chat_history',
      {'content': content},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateMessageSources(
      String id, List<Map<String, String>> sources) async {
    final db = await database;
    await db.update(
      'chat_history',
      {'sources_json': jsonEncode(sources)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateMessageError(
    String id, {
    required String errorLog,
    String? errorCode,
    String? errorMessage,
  }) async {
    final db = await database;
    await db.update(
      'chat_history',
      {
        'error_log': errorLog,
        'error_code': errorCode,
        'error_message': errorMessage,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getChatHistory(String botId) async {
    final db = await database;
    return await db.query('chat_history',
        where: 'bot_id = ?', whereArgs: [botId], orderBy: 'timestamp ASC');
  }

  Future<void> insertChatMessage(Map<String, dynamic> msg) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('chat_history', msg,
          conflictAlgorithm: ConflictAlgorithm.replace);
      final timestamp = (msg['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      await txn.update('bots', {'last_msg_time': timestamp},
          where: 'id = ?', whereArgs: [msg['bot_id']]);
    });
  }

  Future<int> unreadBotCount() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS count FROM bots b
      WHERE COALESCE((SELECT MAX(timestamp) FROM chat_history h
        WHERE h.bot_id = b.id AND h.role = 'assistant'), 0)
        > COALESCE(b.last_read_at, 0)
    ''');
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  /// Byte usage of each bot's persisted chat rows. SQLite stores every bot in
  /// one database file, so allocate the file proportionally by row payload.
  Future<Map<String, int>> chatStorageByBot() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT bot_id, SUM(
        length(COALESCE(content, '')) + length(COALESCE(file_path, '')) +
        length(COALESCE(error_log, '')) + length(COALESCE(sources_json, '')) + 96
      ) AS bytes FROM chat_history GROUP BY bot_id
    ''');
    return {
      for (final row in rows)
        row['bot_id']?.toString() ?? '': (row['bytes'] as num?)?.toInt() ?? 0
    };
  }

  Future<void> deleteMessage(String msgId) async {
    final db = await database;
    await db.delete('chat_history', where: 'id = ?', whereArgs: [msgId]);
  }

  Future<Map<String, dynamic>?> getMessageById(String msgId) async {
    final db = await database;
    final rows = await db.query(
      'chat_history',
      where: 'id = ?',
      whereArgs: [msgId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> clearChatHistory(String botId) async {
    final db = await database;
    await db.delete('chat_history', where: 'bot_id = ?', whereArgs: [botId]);
  }

  // ================= 表情包素材池 =================
  Future<List<Map<String, dynamic>>> queryStickers({String? emotion}) async {
    final db = await database;
    return db.query(
      'stickers',
      where: emotion == null ? null : 'emotion = ?',
      whereArgs: emotion == null ? null : [emotion],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> insertSticker(Map<String, dynamic> sticker) async {
    final db = await database;
    await db.insert('stickers', sticker,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSticker(String id) async {
    final db = await database;
    await db.delete('stickers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> stickerEmotions() async {
    final db = await database;
    final rows = await db.query('stickers',
        columns: ['emotion'],
        distinct: true,
        orderBy: 'emotion COLLATE NOCASE');
    return rows
        .map((row) => row['emotion']?.toString().trim() ?? '')
        .where((emotion) => emotion.isNotEmpty)
        .toList();
  }

  // ================= 潜意识记忆 =================
  Future<void> clearMemories(String botId) async {
    final db = await database;
    await db.delete('memories', where: 'bot_id = ?', whereArgs: [botId]);
  }

  // ================= KV 与 API 配置 =================
  Future<void> setKV(String key, String value) async {
    final db = await database;
    await db.insert('kv_store', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getKV(String key) async {
    final db = await database;
    final res = await db.query('kv_store', where: 'key = ?', whereArgs: [key]);
    if (res.isNotEmpty) return res.first['value'] as String;
    return null;
  }

  Future<List<Map<String, dynamic>>> exportableBots() async => queryBots();

  /// 导出单个机器人的可移植 TideBot JSON，避免混入 API Key、设置与其他机器人数据。
  ///
  /// 返回「建议文件名 + 完整 JSON 导出内容」。真正的落盘由调用方决定，
  /// 例如通过系统的保存对话框写入公共 Download 目录（兼容 scoped storage）。
  Future<({String fileName, String content})> buildChatExport(
      String botId) async {
    final bot = await getBotById(botId);
    if (bot == null) throw StateError('机器人不存在');
    final messages = await queryMessages(botId);
    final safeName = (bot['name']?.toString() ?? 'bot')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\u4e00-\u9fff]'), '_');
    final fileName =
        'tidebot_chat_${safeName}_${DateTime.now().millisecondsSinceEpoch}.json';
    final content = jsonEncode({
      'format': 'tidebot.chat',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'bot': {'id': botId, 'name': bot['name']?.toString() ?? ''},
      'messages': messages
          .map((m) => {
                'id': m['id'],
                'role': m['role'],
                'type': m['type'],
                'content': m['content'],
                'file_path': m['file_path'],
                'mood': m['mood'],
                'duration': m['duration'],
                'reply_to_id': m['reply_to_id'],
                'sources_json': m['sources_json'],
                'timestamp': m['timestamp'],
              })
          .toList(),
    });
    return (fileName: fileName, content: content);
  }

  /// 兼容旧调用：写入导出的 JSON 到应用内部目录并返回其绝对路径（兜底用）。
  Future<String> exportBotChat(String botId) async {
    final export = await buildChatExport(botId);
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/TideBot/exports');
    await downloadDir.create(recursive: true);
    final file = File('${downloadDir.path}/${export.fileName}');
    await file.writeAsString(export.content);
    return file.path;
  }

  Future<int> importBotChat(String botId, String sourcePath) async {
    final source = File(sourcePath);
    final raw = jsonDecode(await source.readAsString());
    if (raw is! Map || raw['format'] != 'tidebot.chat' || raw['version'] != 1) {
      throw const FormatException('仅支持 TideBot 导出的聊天记录文件');
    }
    final list = raw['messages'];
    if (list is! List) throw const FormatException('聊天记录内容无效');
    final items = list.whereType<Map>().toList();
    final base = DateTime.now().microsecondsSinceEpoch;
    final idMap = <String, String>{};
    for (var i = 0; i < items.length; i++) {
      final oldId = items[i]['id']?.toString() ?? '';
      if (oldId.isNotEmpty) idMap[oldId] = 'import_${base}_$i';
    }
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('chat_history', where: 'bot_id = ?', whereArgs: [botId]);
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final oldId = item['id']?.toString() ?? '';
        final timestamp = (item['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch + i;
        final oldReplyId = item['reply_to_id']?.toString() ?? '';
        await txn.insert('chat_history', {
          'id': idMap[oldId] ?? 'import_${base}_$i',
          'bot_id': botId,
          'role': item['role']?.toString() ?? 'user',
          'type': item['type']?.toString() ?? 'text',
          'content': item['content']?.toString() ?? '',
          'file_path': item['file_path']?.toString(),
          'mood': item['mood']?.toString(),
          'duration': item['duration'],
          'reply_to_id': idMap[oldReplyId],
          'sources_json': item['sources_json']?.toString(),
          'timestamp': timestamp + i,
        });
      }
      final latest = items.fold<int>(0, (value, item) {
        final timestamp = (item['timestamp'] as num?)?.toInt() ?? 0;
        return timestamp > value ? timestamp : value;
      });
      await txn.update('bots', {'last_msg_time': latest},
          where: 'id = ?', whereArgs: [botId]);
    });
    return items.length;
  }

  Future<({String fileName, String content})> buildMemoryExport(
      String botId) async {
    final bot = await getBotById(botId);
    if (bot == null) throw StateError('机器人不存在');
    final db = await database;
    final memories = await db.query('memories',
        where: 'bot_id = ?', whereArgs: [botId], orderBy: 'timestamp ASC');
    final kv = await db.query('kv_store',
        where: 'key LIKE ? OR key LIKE ?',
        whereArgs: ['%_$botId', '%_${botId}_%']);
    final safeName = (bot['name']?.toString() ?? 'bot')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\u4e00-\u9fff]'), '_');
    return (
      fileName:
          'tidebot_memory_${safeName}_${DateTime.now().millisecondsSinceEpoch}.json',
      content: jsonEncode({
        'format': 'tidebot.memory',
        'version': 1,
        'bot': {
          'id': botId,
          'name': bot['name'],
          'created_at': bot['created_at'],
          'daily_quote': bot['daily_quote'],
        },
        'memories': memories,
        'kv': kv,
      })
    );
  }

  Future<int> importBotMemory(String botId, String sourcePath) async {
    final raw = jsonDecode(await File(sourcePath).readAsString());
    if (raw is! Map ||
        raw['format'] != 'tidebot.memory' ||
        raw['version'] != 1) {
      throw const FormatException('仅支持 TideBot 导出的底层记忆文件');
    }
    final memories = raw['memories'];
    final kvRows = raw['kv'];
    if (memories is! List || kvRows is! List) {
      throw const FormatException('底层记忆内容无效');
    }
    final sourceBotId =
        (raw['bot'] is Map ? raw['bot']['id'] : '')?.toString() ?? '';
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('memories', where: 'bot_id = ?', whereArgs: [botId]);
      await txn.delete('kv_store',
          where: 'key LIKE ? OR key LIKE ?',
          whereArgs: ['%_$botId', '%_${botId}_%']);
      for (var i = 0; i < memories.length; i++) {
        final item = memories[i];
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        row['bot_id'] = botId;
        row['id'] = 'import_mem_${DateTime.now().microsecondsSinceEpoch}_$i';
        await txn.insert('memories', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final item in kvRows) {
        if (item is! Map || item['key'] == null) continue;
        var key = item['key'].toString();
        if (sourceBotId.isNotEmpty) key = key.replaceAll(sourceBotId, botId);
        await txn.insert(
            'kv_store', {'key': key, 'value': item['value']?.toString()},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final botInfo = raw['bot'];
      if (botInfo is Map) {
        await txn.update(
            'bots',
            {
              'created_at': botInfo['created_at'],
              'daily_quote': botInfo['daily_quote'],
            },
            where: 'id = ?',
            whereArgs: [botId]);
      }
    });
    return memories.whereType<Map>().length;
  }

  Future<void> markBotRead(String botId) async {
    if (botId.isEmpty) return;
    final db = await database;
    await db.update(
        'bots', {'last_read_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [botId]);
  }

  // 旧版全量 Markdown 导出保留兼容，不再作为数据管理入口。
  Future<void> exportToMarkdown() async {
    final db = await database;
    final bots = await db.query('bots');
    final buf = StringBuffer();
    buf.writeln('# TideBot 数据导出');
    buf.writeln('导出时间: ${DateTime.now()}');
    buf.writeln();
    for (var bot in bots) {
      final botId = bot['id'] as String;
      buf.writeln('## ${bot['name']}');
      buf.writeln('> ${bot['desc']}');
      buf.writeln();
      final msgs = await db.query('chat_history',
          where: 'bot_id = ?', whereArgs: [botId], orderBy: 'timestamp ASC');
      for (var m in msgs) {
        final role = m['role'] == 'user' ? '用户' : bot['name'];
        buf.writeln('**$role**: ${m['content']}');
        buf.writeln();
      }
    }
    final dir = await getDatabasesPath();
    final file = File('$dir/tidebot_export.md');
    await file.writeAsString(buf.toString());
  }

  // 添加 path 依赖的导入需要确认已存在; File 来自 dart:io
  // 需要在文件顶部已 import 'dart:io';

  // 别名：新代码统一用 queryBots
  Future<List<Map<String, dynamic>>> queryBots() async => getAllBots();

  // 别名：新代码用 insertMessage
  Future<void> insertMessage(Map<String, dynamic> msg) async =>
      insertChatMessage(msg);

  // 别名：新代码用 queryMessages，支持可选 limit 与倒序
  Future<List<Map<String, dynamic>>> queryMessages(String botId,
      {int? limit, bool descending = false}) async {
    final db = await database;
    return await db.query('chat_history',
        where: 'bot_id = ?',
        whereArgs: [botId],
        orderBy: descending ? 'timestamp DESC' : 'timestamp ASC',
        limit: limit);
  }

  // 别名：新代码用 deleteMessages (清空聊天)
  Future<void> deleteMessages(String botId) async => clearChatHistory(botId);

  // 查询日程 (schedule_tasks 表)
  Future<List<Map<String, dynamic>>> querySchedules(String botId,
      {int? limit}) async {
    final db = await database;
    return await db.query('schedule_tasks',
        where: 'bot_id = ?',
        whereArgs: [botId],
        orderBy: 'time ASC',
        limit: limit);
  }

  Future<void> insertFutureTask(Map<String, dynamic> task) async {
    final db = await database;
    await db.insert('schedule_tasks', task,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteFutureTask(String id) async {
    final db = await database;
    await db.delete('schedule_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateFutureTask(String id, Map<String, dynamic> values) async {
    final db = await database;
    await db.update('schedule_tasks', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> dueFutureTasks(int now) async {
    final db = await database;
    return db.query('schedule_tasks',
        where: 'run_at <= ? AND status = ?',
        whereArgs: [now, 'pending'],
        orderBy: 'run_at ASC');
  }

  // 查询记忆 (memories 表)
  Future<List<Map<String, dynamic>>> queryMemories(String botId,
      {String? type, int? limit, bool includeExpired = false}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final whereParts = <String>['bot_id = ?'];
    final whereArgs = <dynamic>[botId];
    if (type != null) {
      whereParts.add('type = ?');
      whereArgs.add(type);
    }
    if (!includeExpired) {
      whereParts
          .add('(expires_at IS NULL OR expires_at <= 0 OR expires_at > ?)');
      whereArgs.add(now);
    }
    return await db.query('memories',
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC',
        limit: limit);
  }

  Future<void> insertMemory(Map<String, dynamic> memory) async {
    final db = await database;
    await db.insert('memories', memory,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 新记忆按条写入前做轻量去重：同一机器人、同一层级内的相同内容不重复占用。
  /// 相近内容保留最新一条，避免短期记忆越积越多。
  Future<void> upsertMemoryItem({
    required String botId,
    required String type,
    required String content,
    String? id,
    String title = '',
    String category = 'fact',
    int importance = 3,
    int? expiresAt,
    int? timestamp,
  }) async {
    final normalized = content.replaceAll(RegExp(r'\s+'), '').trim();
    if (normalized.isEmpty) return;
    final now = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await queryMemories(botId, type: type, limit: 80);
    Map<String, dynamic>? duplicate;
    for (final item in existing) {
      final old = (item['content']?.toString() ?? '')
          .replaceAll(RegExp(r'\s+'), '')
          .trim();
      if (old == normalized ||
          (old.length >= 12 &&
              normalized.length >= 12 &&
              (old.contains(normalized) || normalized.contains(old)))) {
        duplicate = item;
        break;
      }
    }
    final targetId = (id ?? '').trim();
    if (targetId.isNotEmpty) {
      await insertMemory({
        'id': targetId,
        'bot_id': botId,
        'title': title,
        'type': type,
        'content': content.trim(),
        'category': category,
        'importance': importance.clamp(1, 5),
        'expires_at': expiresAt,
        'timestamp': now,
        'updated_at': now,
      });
    } else if (duplicate != null) {
      // Exact duplicates are a no-op. In particular, do not refresh updated_at:
      // a repeated model memory tag is not a meaningful memory modification.
      final previous = duplicate['content']?.toString().trim() ?? '';
      if (previous != content.trim()) {
        await updateMemory(duplicate['id'].toString(), {
          'title': title.isEmpty ? duplicate['title'] : title,
          'content': content.trim(),
          'category': category,
          'importance': importance.clamp(1, 5),
          'expires_at': expiresAt,
          'timestamp': now,
          'updated_at': now,
        });
      }
    } else {
      await insertMemory({
        'id': 'mem_${botId}_${now}_${normalized.hashCode.abs()}',
        'bot_id': botId,
        'title': title,
        'type': type,
        'content': content.trim(),
        'category': category,
        'importance': importance.clamp(1, 5),
        'expires_at': expiresAt,
        'timestamp': now,
        'updated_at': now,
      });
    }
    const caps = {'long': 60, 'short': 100};
    final cap = caps[type] ?? 80;
    final rows = await queryMemories(botId, type: type);
    if (rows.length > cap) {
      for (final item in rows.skip(cap)) {
        await deleteMemory(item['id'].toString());
      }
    }
  }

  Future<void> updateMemory(String id, Map<String, dynamic> values) async {
    final db = await database;
    await db.update('memories', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMemory(String id) async {
    final db = await database;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  // 删除指定机器人的记忆
  Future<void> deleteMemories(String botId) async => clearMemories(botId);

  // 别名：新代码用 insertKV
  Future<void> insertKV(String key, String value) async => setKV(key, value);

  // ================= Provider 管理 (兼容新旧接口) =================

  // 新接口：insertProvider(name, url, key)
  Future<void> insertProviderNew(String name, String url, String apiKey) async {
    final existing = await getProvidersByType('chat');
    // 新配置追加保存，不覆盖已有同名 provider
    existing.add({
      'id': 'provider_chat_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'chat',
      'name': name,
      'base_url': url,
      'api_key': apiKey,
    });
    await setKV('providers_chat', jsonEncode(existing));
  }

  // 旧接口兼容
  Future<void> insertProvider(Map<String, dynamic> provider) async {
    final existing = await getProvidersByType(provider['type'] ?? 'chat');
    existing.add(provider);
    await setKV('providers_${provider['type']}', jsonEncode(existing));
  }

  // 查询所有 chat 类型的 provider
  Future<List<Map<String, dynamic>>> queryProviders() async {
    return await getProvidersByType('chat');
  }

  // 清空所有 provider (chat 类型)
  Future<void> deleteProviders() async {
    await setKV('providers_chat', '[]');
  }

  Future<List<Map<String, dynamic>>> getProvidersByType(String type) async {
    final data = await getKV('providers_$type');
    if (data == null) return [];
    List<dynamic> list = jsonDecode(data);
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>?> getProviderById(String id) async {
    final chatProviders = await getProvidersByType('chat');
    try {
      return chatProviders.firstWhere((p) => p['id'] == id);
    } catch (e) {
      return null;
    }
  }

  // ============ 统一聊天链路 provider 读取 ============
  // API设置页把模型提供商存在 'provider_list'（字段: name/url/key/model），
  // 而聊天/ai.dart 需要 {id,type,name,base_url,api_key,model} 结构。
  // 这里做转换适配，保证「API设置里配的模型」能被聊天真正用上。
  Future<List<Map<String, dynamic>>> queryChatProviders() async {
    final data = await getKV('provider_list');
    if (data == null || data.isEmpty) return [];
    List<Map<String, dynamic>> result = [];
    try {
      final decoded = jsonDecode(data) as List;
      for (var e in decoded) {
        final m = e as Map<String, dynamic>;
        result.add({
          'id': m['id']?.toString().isNotEmpty == true
              ? m['id'].toString()
              : 'legacy_p_${m['name']}_${m['url']}_${m['model']}',
          'type': 'chat',
          'name': m['name'] ?? '',
          'base_url': m['url'] ?? '',
          'api_key': m['key'] ?? '',
          'model': m['model'] ?? '',
        });
      }
    } catch (_) {}
    return result;
  }

  Future<Map<String, dynamic>?> getChatProviderById(String id) async {
    final list = await queryChatProviders();
    try {
      return list.firstWhere((p) => p['id'] == id);
    } catch (e) {
      return null;
    }
  }

  // STT is deliberately independent from chat providers. A chat endpoint is
  // often OpenAI-compatible for completions but has no transcription route.
  Future<List<Map<String, dynamic>>> querySttProviders() async {
    final data = await getKV('stt_provider_list');
    if (data == null || data.isEmpty) return [];
    try {
      final decoded = jsonDecode(data) as List;
      return decoded.whereType<Map>().map((raw) {
        final m = Map<String, dynamic>.from(raw);
        return {
          'id': m['id']?.toString().isNotEmpty == true
              ? m['id'].toString()
              : 'stt_${m['name'] ?? m['url']}',
          'type': 'stt',
          'name': m['name'] ?? '',
          'base_url': m['url'] ?? m['base_url'] ?? '',
          'api_key': m['key'] ?? m['api_key'] ?? '',
          'model': m['model'] ?? '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getSttProviderById(String id) async {
    final list = await querySttProviders();
    try {
      return list.firstWhere((p) => p['id'] == id);
    } catch (_) {
      return null;
    }
  }

  // ============ 统一 TTS 链路 provider 读取 ============
  // API 设置页把 TTS 提供商也存在 'tts_provider_list'（字段: name/url/key/model/voice）
  Future<List<Map<String, dynamic>>> queryTtsProviders() async {
    final data = await getKV('tts_provider_list');
    if (data == null || data.isEmpty) return [];
    List<Map<String, dynamic>> result = [];
    try {
      final decoded = jsonDecode(data) as List;
      for (var e in decoded) {
        final m = e as Map<String, dynamic>;
        result.add({
          'id': m['id']?.toString().isNotEmpty == true
              ? m['id'].toString()
              : 'ts_${m['name']}',
          'type': 'tts',
          'name': m['name'] ?? '',
          'base_url': m['url'] ?? '',
          'api_key': m['key'] ?? '',
          'model': m['model'] ?? '',
          'voice': m['voice'] ?? '',
        });
      }
    } catch (_) {}
    return result;
  }

  // ================= Posts 查询（广场分页） =================
  Future<List<Map<String, dynamic>>> queryPosts(
      {int offset = 0, int limit = 10}) async {
    final db = await database;
    return await db.query('posts',
        orderBy: 'timestamp DESC', limit: limit, offset: offset);
  }

  Future<void> insertPost(Map<String, dynamic> post) async {
    final db = await database;
    await db.insert('posts', post,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePostLikes(String postId, int likes) async {
    final db = await database;
    await db.update('posts', {'likes': likes},
        where: 'id = ?', whereArgs: [postId]);
  }

  Future<void> updatePostComments(String postId, int comments) async {
    final db = await database;
    await db.update('posts', {'comments': comments},
        where: 'id = ?', whereArgs: [postId]);
  }

  Future<void> updatePostUserState(String postId,
      {required bool liked, required bool collected}) async {
    final db = await database;
    await db.update(
      'posts',
      {'user_liked': liked ? 1 : 0, 'user_collected': collected ? 1 : 0},
      where: 'id = ?',
      whereArgs: [postId],
    );
  }

  Future<List<Map<String, dynamic>>> queryPostComments(String postId) async {
    final db = await database;
    return db.query(
      'post_comments',
      where: 'post_id = ?',
      whereArgs: [postId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<void> insertPostComment(Map<String, dynamic> comment) async {
    final db = await database;
    await db.insert('post_comments', comment);
  }

  Future<void> deletePostComment(String commentId) async {
    final db = await database;
    await db.delete('post_comments', where: 'id = ?', whereArgs: [commentId]);
  }

  Future<void> deletePost(String postId) async {
    final db = await database;
    await db.delete('posts', where: 'id = ?', whereArgs: [postId]);
  }

  /// Records a feed action only once for the same actor and post.
  Future<bool> recordFeedEvent({
    required String postId,
    required String actorId,
    required String eventType,
  }) async {
    final db = await database;
    try {
      await db.insert(
          'feed_events',
          {
            'id': 'fe_${postId}_${actorId}_$eventType',
            'post_id': postId,
            'actor_id': actorId,
            'event_type': eventType,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);
      return true;
    } on DatabaseException {
      return false;
    }
  }

  Future<bool> hasFeedEvent({
    required String postId,
    required String actorId,
    required String eventType,
  }) async {
    final db = await database;
    final rows = await db.query('feed_events',
        where: 'post_id = ? AND actor_id = ? AND event_type = ?',
        whereArgs: [postId, actorId, eventType],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// 删除一条互动事件（用于取消点赞 / 取消收藏）。
  Future<void> deleteFeedEvent({
    required String postId,
    required String actorId,
    required String eventType,
  }) async {
    final db = await database;
    await db.delete('feed_events',
        where: 'post_id = ? AND actor_id = ? AND event_type = ?',
        whereArgs: [postId, actorId, eventType]);
  }

  /// 用户的点赞 / 收藏是切换行为：已存在则取消（删除事件），不存在则新增。
  /// 返回切换后是否处于“已点赞 / 已收藏”状态。
  Future<bool> toggleFeedEvent({
    required String postId,
    required String actorId,
    required String eventType,
  }) async {
    final existed = await hasFeedEvent(
        postId: postId, actorId: actorId, eventType: eventType);
    if (existed) {
      await deleteFeedEvent(
          postId: postId, actorId: actorId, eventType: eventType);
      return false;
    }
    await recordFeedEvent(
        postId: postId, actorId: actorId, eventType: eventType);
    return true;
  }

  /// 统计某条动态的真实点赞数（来自 feed_events 中的 like / collect 互动的去重计数）。
  Future<int> countPostLikes(String postId) async {
    final db = await database;
    final likeRows = await db.query('feed_events',
        where: 'post_id = ? AND event_type = ?', whereArgs: [postId, 'like']);
    return likeRows.length;
  }

  /// 统计某条动态的真实评论数（来自 post_comments）。
  Future<int> countPostComments(String postId) async {
    final db = await database;
    final rows = await db
        .query('post_comments', where: 'post_id = ?', whereArgs: [postId]);
    return rows.length;
  }

  /// 记录一条真实评论（由机器人生成），并去重插入 feed_events 的 comment 事件。
  Future<void> insertRealPostComment({
    required String postId,
    required String authorId,
    required String content,
    String? parentId,
    int? timestamp,
  }) async {
    final db = await database;
    final now = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final id = 'rc_${postId}_${authorId}_$now';
    await db.insert('post_comments', {
      'id': id,
      'post_id': postId,
      'author_id': authorId,
      'content': content,
      'parent_id': parentId,
      'timestamp': now,
    });
    try {
      await db.insert(
          'feed_events',
          {
            'id': 'fe_${postId}_${authorId}_comment',
            'post_id': postId,
            'actor_id': authorId,
            'event_type': 'comment',
            'timestamp': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);
    } on DatabaseException {
      // 同一机器人对同一条动态只计一次互动事件。
    }
  }

  Future<void> recordAiUsage({
    required String botId,
    required String eventType,
    required int promptTokens,
    required int completionTokens,
    required int totalTokens,
    int replyCount = 1,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('ai_usage_events', {
      'id': 'usage_${now}_${botId}_$eventType',
      'bot_id': botId,
      'event_type': eventType,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': totalTokens,
      'reply_count': replyCount,
      'timestamp': now,
    });
  }

  // 更新 bots.last_msg_time
  Future<void> updateBotLastMsgTime(String botId, int time) async {
    final db = await database;
    await db.update('bots', {'last_msg_time': time},
        where: 'id = ?', whereArgs: [botId]);
  }

  // 置顶/取消置顶
  Future<void> toggleBotPin(String botId, int isPinned) async {
    final db = await database;
    await db.update('bots', {'is_pinned': isPinned},
        where: 'id = ?', whereArgs: [botId]);
  }
}
