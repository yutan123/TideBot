import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DBManager {
  static final DBManager _instance = DBManager._internal();
  factory DBManager() => _instance;
  DBManager._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'tidebot_core_v4.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bots(
            id TEXT PRIMARY KEY, name TEXT NOT NULL, desc TEXT, prompt TEXT, avatar_path TEXT,
            chat_model TEXT, backup_model TEXT, vision_model TEXT, stt_model TEXT, tts_model TEXT,
            max_tokens INTEGER DEFAULT 10000, created_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_history(
            id TEXT PRIMARY KEY, bot_id TEXT, role TEXT, type TEXT, content TEXT, 
            file_path TEXT, mood TEXT, timestamp INTEGER,
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE api_providers(
            id TEXT PRIMARY KEY, type TEXT, name TEXT, base_url TEXT, api_key TEXT, created_at INTEGER
          )
        ''');
        await db.execute('CREATE TABLE memories(id TEXT PRIMARY KEY, bot_id TEXT, memory_type TEXT, content TEXT, created_at INTEGER, FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE)');
        await db.execute('CREATE TABLE posts(id TEXT PRIMARY KEY, author_id TEXT, content TEXT, image_path TEXT, timestamp INTEGER)');
        await db.execute('CREATE TABLE kv_store(key TEXT PRIMARY KEY, value TEXT)');
      },
      onConfigure: (db) async { await db.execute('PRAGMA foreign_keys = ON'); },
    );
  }

  // ==== 机器人档案 ====
  Future<void> insertBot(Map<String, dynamic> botData) async => await (await database).insert('bots', botData, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> updateBot(String id, Map<String, dynamic> data) async => await (await database).update('bots', data, where: 'id = ?', whereArgs: [id]);
  Future<List<Map<String, dynamic>>> getAllBots() async => await (await database).query('bots', orderBy: 'created_at DESC');
  Future<void> deleteBot(String botId) async => await (await database).delete('bots', where: 'id = ?', whereArgs: [botId]);

  // ==== 聊天记录 ====
  Future<void> insertChatMessage(Map<String, dynamic> msg) async => await (await database).insert('chat_history', msg, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<List<Map<String, dynamic>>> getChatHistory(String botId) async => await (await database).query('chat_history', where: 'bot_id = ?', whereArgs: [botId], orderBy: 'timestamp ASC');
  Future<void> clearChatHistory(String botId) async => await (await database).delete('chat_history', where: 'bot_id = ?', whereArgs: [botId]);
  Future<void> deleteMessage(String msgId) async => await (await database).delete('chat_history', where: 'id = ?', whereArgs: [msgId]);

  // ==== API 提供商 (真实的动态配置) ====
  Future<void> insertProvider(Map<String, dynamic> provider) async => await (await database).insert('api_providers', provider, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<List<Map<String, dynamic>>> getProvidersByType(String type) async => await (await database).query('api_providers', where: 'type = ?', whereArgs: [type], orderBy: 'created_at DESC');
  Future<Map<String, dynamic>?> getProviderById(String id) async {
    final res = await (await database).query('api_providers', where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? res.first : null;
  }
  Future<void> deleteProvider(String id) async => await (await database).delete('api_providers', where: 'id = ?', whereArgs: [id]);

  // ==== 记忆与 KV 存储 ====
  Future<void> clearMemories(String botId) async => await (await database).delete('memories', where: 'bot_id = ?', whereArgs: [botId]);
  Future<void> setKV(String key, String value) async => await (await database).insert('kv_store', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<String?> getKV(String key) async {
    final res = await (await database).query('kv_store', where: 'key = ?', whereArgs: [key]);
    return res.isNotEmpty ? res.first['value'] as String? : null;
  }
}