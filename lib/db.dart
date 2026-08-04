import 'dart:convert';
import 'dart:io';
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
    final path = join(directory.path, 'tidebot_brain.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bots(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            desc TEXT,
            prompt TEXT,
            avatar_path TEXT,
            birthday TEXT,
            default_model TEXT,
            image_model TEXT,
            stt_model TEXT,
            tts_model TEXT,
            max_tokens INTEGER,
            is_system INTEGER DEFAULT 0,
            created_at INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE chat_history(
            id TEXT PRIMARY KEY,
            bot_id TEXT,
            role TEXT,
            content TEXT,
            image_path TEXT,
            audio_path TEXT,
            mood TEXT,
            timestamp INTEGER,
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE memories(
            id TEXT PRIMARY KEY,
            bot_id TEXT,
            memory_type TEXT, 
            content TEXT,
            created_at INTEGER,
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE schedule_tasks(
            id TEXT PRIMARY KEY,
            bot_id TEXT,
            task_type TEXT, 
            execute_hour INTEGER,
            execute_minute INTEGER,
            execute_date TEXT,
            description TEXT,
            is_active INTEGER DEFAULT 1,
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE posts(
            id TEXT PRIMARY KEY,
            author_id TEXT,
            author_name TEXT,
            content TEXT,
            image_path TEXT,
            likes_data TEXT,
            comments_data TEXT,
            timestamp INTEGER
          )
        ''');
        
        await db.execute('''
          CREATE TABLE kv_store(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute("ALTER TABLE chat_history ADD COLUMN mood TEXT");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE posts ADD COLUMN comments_data TEXT");
          } catch (_) {}
        }
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> insertBot(Map<String, dynamic> botData) async {
    final db = await database;
    await db.insert('bots', botData, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAllBots() async {
    final db = await database;
    return await db.query('bots', orderBy: 'created_at DESC');
  }

  Future<void> deleteBot(String botId) async {
    final db = await database;
    await db.delete('bots', where: 'id = ?', whereArgs: [botId]);
  }

  Future<void> insertChatMessage(Map<String, dynamic> msg) async {
    final db = await database;
    await db.insert('chat_history', msg, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getChatHistory(String botId, {int limit = 50, int offset = 0}) async {
    final db = await database;
    return await db.query(
      'chat_history',
      where: 'bot_id = ?',
      whereArgs: [botId],
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> clearChatHistory(String botId) async {
    final db = await database;
    await db.delete('chat_history', where: 'bot_id = ?', whereArgs: [botId]);
  }

  Future<void> insertMemory(String botId, String type, String content) async {
    final db = await database;
    await db.insert('memories', {
      'id': 'mem_${DateTime.now().millisecondsSinceEpoch}',
      'bot_id': botId,
      'memory_type': type,
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getMemoryByType(String botId, String type) async {
    final db = await database;
    return await db.query(
      'memories',
      where: 'bot_id = ? AND memory_type = ?',
      whereArgs: [botId, type],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> deleteMemoryContent(String memoryId) async {
    final db = await database;
    await db.delete('memories', where: 'id = ?', whereArgs: [memoryId]);
  }

  Future<void> insertPost(Map<String, dynamic> post) async {
    final db = await database;
    await db.insert('posts', post, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPosts({int limit = 20, int offset = 0}) async {
    final db = await database;
    return await db.query('posts', orderBy: 'timestamp DESC', limit: limit, offset: offset);
  }

  Future<void> deletePost(String postId) async {
    final db = await database;
    await db.delete('posts', where: 'id = ?', whereArgs: [postId]);
  }

  Future<void> setKV(String key, String value) async {
    final db = await database;
    await db.insert('kv_store', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getKV(String key) async {
    final db = await database;
    final results = await db.query('kv_store', where: 'key = ?', whereArgs: [key]);
    if (results.isNotEmpty) return results.first['value'] as String?;
    return null;
  }
}