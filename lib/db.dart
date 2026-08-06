import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
      version: 5,
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
            content TEXT, file_path TEXT, mood TEXT, duration INTEGER, timestamp INTEGER,
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

  Future<void> clearChatHistory(String botId) async {
    final db = await database;
    await db.delete('chat_history', where: 'bot_id = ?', whereArgs: [botId]);
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

  // 导出数据为 Markdown
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
