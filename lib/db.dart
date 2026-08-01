import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// 本地持久化底座 (db.dart)
/// 全权接管数字生命的所有记忆、档案、对话日志及广场动态
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
      version: 1,
      onCreate: (db, version) async {
        // 1. 机器人基础档案表
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

        // 2. 聊天记录明细表 (含多模态数据结构)
        await db.execute('''
          CREATE TABLE chat_history(
            id TEXT PRIMARY KEY,
            bot_id TEXT,
            role TEXT,
            content TEXT,
            image_path TEXT,
            audio_path TEXT,
            timestamp INTEGER,
            FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
          )
        ''');

        // 3. 多级记忆海马体表 (分级存储: long, mid, short, task)
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

        // 4. 定时任务日程表 (用于唤醒提醒)
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

        // 5. 广场动态发帖生态表 (完全本地化)
        await db.execute('''
          CREATE TABLE posts(
            id TEXT PRIMARY KEY,
            author_id TEXT,
            content TEXT,
            image_path TEXT,
            likes_data TEXT, 
            timestamp INTEGER
          )
        ''');
        
        // 6. 全局配置与模型提供商键值对
        await db.execute('''
          CREATE TABLE kv_store(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
      onConfigure: (db) async {
        // 开启 SQLite 的外键约束支持
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // ==========================================
  // 数字生命档案 (Bots) CRUD
  // ==========================================

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
    // 开启了外键级联删除，删除机器人会自动清空其聊天记录、记忆和日程
    await db.delete('bots', where: 'id = ?', whereArgs: [botId]);
  }

  // ==========================================
  // 聊天上下文 (Chat) 与多级记忆 (Memory)
  // ==========================================

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
      'memory_type': type, // 'long', 'mid', 'short'
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

  // ==========================================
  // 广场动态生态 (Posts)
  // ==========================================

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

  // ==========================================
  // 备份与导出体系 (防封锁机制)
  // ==========================================

  /// 将机器人的一切对话记录和心智记忆导出为 Markdown 文件到外部目录
  Future<String?> exportBotDataToMarkdown(String botId) async {
    try {
      final bots = await database.then((db) => db.query('bots', where: 'id = ?', whereArgs: [botId]));
      if (bots.isEmpty) return null;
      
      final botName = bots.first['name'];
      final history = await getChatHistory(botId, limit: 10000); // 导出全部
      
      StringBuffer mdContent = StringBuffer();
      mdContent.writeln('# $botName 的数字生命档案与纪元纪事\n');
      mdContent.writeln('**导出时间**: ${DateTime.now().toString()}\n');
      mdContent.writeln('---\n');
      
      for (var msg in history) {
        final role = msg['role'] == 'user' ? '我' : botName;
        mdContent.writeln('### $role [${DateTime.fromMillisecondsSinceEpoch(msg['timestamp'])}]');
        if (msg['content'] != null) {
          mdContent.writeln('${msg['content']}\n');
        }
        if (msg['image_path'] != null) {
          mdContent.writeln('*(包含图片文件: ${msg['image_path']})*\n');
        }
      }

      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        final file = File('${directory.path}/TideBot_Export_${botName}_${DateTime.now().millisecondsSinceEpoch}.md');
        await file.writeAsString(mdContent.toString());
        return file.path;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ==========================================
  // 全局键值存储 (KeyValue Store)
  // ==========================================

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