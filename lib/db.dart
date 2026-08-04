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
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        // 1. 生命体档案表
        await db.execute('''
          CREATE TABLE bots (
            id TEXT PRIMARY KEY, name TEXT, desc TEXT, prompt TEXT,
            chat_model TEXT, stt_model TEXT, tts_model TEXT,
            max_tokens INTEGER, created_at INTEGER
          )
        ''');
        // 2. 聊天历史表
        await db.execute('''
          CREATE TABLE chat_history (
            id TEXT PRIMARY KEY, bot_id TEXT, role TEXT, type TEXT,
            content TEXT, file_path TEXT, mood TEXT, timestamp INTEGER,
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');
         // 3. 记忆表 (长/中/短)
         await db.execute('''
           CREATE TABLE memories (
             id TEXT PRIMARY KEY, bot_id TEXT, title TEXT DEFAULT '', type TEXT, content TEXT, timestamp INTEGER,
             FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
           )
         ''');
        // 4. 日程规划表
        await db.execute('''
          CREATE TABLE schedule_tasks (
            id TEXT PRIMARY KEY, bot_id TEXT, title TEXT, time INTEGER, is_done INTEGER,
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');
        // 5. 动态广场表
        await db.execute('''
          CREATE TABLE posts (
            id TEXT PRIMARY KEY, author_id TEXT, content TEXT, image_path TEXT, timestamp INTEGER
          )
        ''');
        // 6. KV 设置表 (用于存 API 提供商配置和背景图等)
        await db.execute('''
          CREATE TABLE kv_store (
            key TEXT PRIMARY KEY, value TEXT
          )
        ''');
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
  Future<List<Map<String, dynamic>>> getChatHistory(String botId) async {
    final db = await database;
    return await db.query('chat_history', where: 'bot_id = ?', whereArgs: [botId], orderBy: 'timestamp ASC');
  }

  Future<void> insertChatMessage(Map<String, dynamic> msg) async {
    final db = await database;
    await db.insert('chat_history', msg, conflictAlgorithm: ConflictAlgorithm.replace);
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
    await db.insert('kv_store', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
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
      final msgs = await db.query('chat_history', where: 'bot_id = ?', whereArgs: [botId], orderBy: 'timestamp ASC');
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
  Future<void> insertMessage(Map<String, dynamic> msg) async => insertChatMessage(msg);

  // 别名：新代码用 queryMessages，支持可选 limit
  Future<List<Map<String, dynamic>>> queryMessages(String botId, {int? limit}) async {
    final db = await database;
    return await db.query('chat_history',
        where: 'bot_id = ?', whereArgs: [botId],
        orderBy: 'timestamp ASC',
        limit: limit);
  }

  // 别名：新代码用 deleteMessages (清空聊天)
  Future<void> deleteMessages(String botId) async => clearChatHistory(botId);

  // 查询日程 (schedule_tasks 表)
  Future<List<Map<String, dynamic>>> querySchedules(String botId, {int? limit}) async {
    final db = await database;
    return await db.query('schedule_tasks',
        where: 'bot_id = ?', whereArgs: [botId],
        orderBy: 'time ASC',
        limit: limit);
  }

  // 查询记忆 (memories 表)
  Future<List<Map<String, dynamic>>> queryMemories(String botId, {String? type, int? limit}) async {
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
        where: whereStr, whereArgs: whereArgs,
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
}