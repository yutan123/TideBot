import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

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
      version: 12,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bots (
            id TEXT PRIMARY KEY, name TEXT, desc TEXT, prompt TEXT,
            avatar TEXT, chat_model TEXT, stt_model TEXT, tts_model TEXT,
            max_tokens INTEGER, created_at INTEGER, daily_quote TEXT,
            last_msg_time INTEGER, is_pinned INTEGER DEFAULT 0
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
            id TEXT PRIMARY KEY, bot_id TEXT, title TEXT DEFAULT '', type TEXT, content TEXT, timestamp INTEGER,
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE schedule_tasks (
            id TEXT PRIMARY KEY, bot_id TEXT, title TEXT, note TEXT, time INTEGER, is_done INTEGER,
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
            content TEXT NOT NULL, timestamp INTEGER,
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
              content TEXT NOT NULL, timestamp INTEGER,
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
      },
    );
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
    await db.insert('chat_history', msg,
        conflictAlgorithm: ConflictAlgorithm.replace);
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
  Future<String> exportBotChat(String botId) async {
    final bot = await getBotById(botId);
    if (bot == null) throw StateError('机器人不存在');
    final messages = await queryMessages(botId);
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/TideBot/exports');
    await downloadDir.create(recursive: true);
    final safeName = (bot['name']?.toString() ?? 'bot')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\u4e00-\u9fff]'), '_');
    final file = File(
        '${downloadDir.path}/tidebot_chat_${safeName}_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonEncode({
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
    }));
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
    var count = 0;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final oldId = item['id']?.toString() ?? '';
      final timestamp = (item['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch + i;
      final oldReplyId = item['reply_to_id']?.toString() ?? '';
      await insertChatMessage({
        'id': idMap[oldId] ?? 'import_${base}_$i',
        'bot_id': botId,
        'role': item['role']?.toString() ?? 'user',
        'type': item['type']?.toString() ?? 'text',
        'content': item['content']?.toString() ?? '',
        'file_path': item['file_path']?.toString(),
        'mood': item['mood']?.toString(),
        'duration': item['duration'],
        // Preserve quotes whose source is part of this same imported archive.
        'reply_to_id': idMap[oldReplyId],
        'sources_json': item['sources_json']?.toString(),
        'timestamp': timestamp + i,
      });
      count++;
    }
    return count;
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

  // 别名：新代码用 queryMessages，支持可选 limit
  Future<List<Map<String, dynamic>>> queryMessages(String botId,
      {int? limit}) async {
    final db = await database;
    return await db.query('chat_history',
        where: 'bot_id = ?',
        whereArgs: [botId],
        orderBy: 'timestamp ASC',
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

  // 查询记忆 (memories 表)
  Future<List<Map<String, dynamic>>> queryMemories(String botId,
      {String? type, int? limit}) async {
    final db = await database;
    String? whereStr;
    List<dynamic>? whereArgs;
    if (type != null) {
      whereStr = 'bot_id = ? AND type = ?';
      whereArgs = [botId, type];
    } else {
      whereStr = 'bot_id = ?';
      whereArgs = [botId];
    }
    return await db.query('memories',
        where: whereStr,
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC',
        limit: limit);
  }

  Future<void> insertMemory(Map<String, dynamic> memory) async {
    final db = await database;
    await db.insert('memories', memory,
        conflictAlgorithm: ConflictAlgorithm.replace);
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
    // 清空旧 chat 类型 provider，只保留一条
    existing.clear();
    existing.add({
      'id': 'provider_chat_0',
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
          'id': 'p_${m['name']}',
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
          'id': 'ts_${m['name']}',
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
