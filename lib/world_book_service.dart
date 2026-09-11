import 'dart:convert';

import 'db.dart';

/// 世界书条目模型
class WorldBookEntry {
  final String id;
  final String bookId;
  final String? botId;
  final String title;
  final String content;
  final String comment;
  final List<String> keys;
  final List<String> secondaryKeys;
  final String keyMode; // 'any' | 'all'
  final bool caseSensitive;
  final bool matchWholeWords;
  final bool useRegex;
  final String
      position; // 'before_char' | 'after_char' | 'depth_N' | 'author_note'
  final int insertionOrder;
  final int priority;
  final bool enabled;
  final int activationCount;
  final int? lastActivatedAt;
  final int createdAt;
  final int updatedAt;

  WorldBookEntry({
    required this.id,
    required this.bookId,
    this.botId,
    required this.title,
    required this.content,
    this.comment = '',
    required this.keys,
    this.secondaryKeys = const [],
    this.keyMode = 'any',
    this.caseSensitive = false,
    this.matchWholeWords = false,
    this.useRegex = false,
    this.position = 'after_char',
    this.insertionOrder = 100,
    this.priority = 50,
    this.enabled = true,
    this.activationCount = 0,
    this.lastActivatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorldBookEntry.fromMap(Map<String, dynamic> map) {
    return WorldBookEntry(
      id: map['id'] as String,
      bookId: map['book_id'] as String,
      botId: map['bot_id'] as String?,
      title: map['title'] as String,
      content: map['content'] as String,
      comment: map['comment'] as String? ?? '',
      keys: (jsonDecode(map['keys'] as String) as List).cast<String>(),
      secondaryKeys:
          (jsonDecode(map['secondary_keys'] as String? ?? '[]') as List)
              .cast<String>(),
      keyMode: map['key_mode'] as String? ?? 'any',
      caseSensitive: (map['case_sensitive'] as int? ?? 0) == 1,
      matchWholeWords: (map['match_whole_words'] as int? ?? 0) == 1,
      useRegex: (map['use_regex'] as int? ?? 0) == 1,
      position: map['position'] as String? ?? 'after_char',
      insertionOrder: map['insertion_order'] as int? ?? 100,
      priority: map['priority'] as int? ?? 50,
      enabled: (map['enabled'] as int? ?? 1) == 1,
      activationCount: map['activation_count'] as int? ?? 0,
      lastActivatedAt: map['last_activated_at'] as int?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'bot_id': botId,
      'title': title,
      'content': content,
      'comment': comment,
      'keys': jsonEncode(keys),
      'secondary_keys': jsonEncode(secondaryKeys),
      'key_mode': keyMode,
      'case_sensitive': caseSensitive ? 1 : 0,
      'match_whole_words': matchWholeWords ? 1 : 0,
      'use_regex': useRegex ? 1 : 0,
      'position': position,
      'insertion_order': insertionOrder,
      'priority': priority,
      'enabled': enabled ? 1 : 0,
      'activation_count': activationCount,
      'last_activated_at': lastActivatedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

/// 世界书服务
class WorldBookService {
  static WorldBookService? _instance;
  static WorldBookService get instance => _instance ??= WorldBookService._();

  WorldBookService._();

  final DBManager db = DBManager();

  /// 激活世界书条目（根据对话内容匹配）
  Future<List<WorldBookEntry>> activateEntries({
    required String botId,
    required String conversationText,
    int scanDepth = 10,
  }) async {
    final database = await db.database;

    // 1. 获取该机器人的所有启用条目（包括全局条目）
    final rows = await database.query(
      'world_book_entries',
      where: '(bot_id = ? OR bot_id IS NULL) AND enabled = 1',
      whereArgs: [botId],
      orderBy: 'priority DESC, insertion_order ASC',
    );

    if (rows.isEmpty) return [];

    final entries = rows.map((r) => WorldBookEntry.fromMap(r)).toList();
    final activated = <WorldBookEntry>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    // 2. 对每个条目进行匹配测试
    for (final entry in entries) {
      if (_matchEntry(entry, conversationText)) {
        activated.add(entry);

        // 3. 更新激活统计
        await database.update(
          'world_book_entries',
          {
            'activation_count': entry.activationCount + 1,
            'last_activated_at': now,
          },
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      }
    }

    return activated;
  }

  /// 匹配单个条目
  static bool _matchEntry(WorldBookEntry entry, String text) {
    // 主键匹配
    final primaryMatched = _matchKeys(
      entry.keys,
      text,
      entry.caseSensitive,
      entry.matchWholeWords,
      entry.useRegex,
      entry.keyMode,
    );

    if (!primaryMatched) return false;

    // 次要键匹配（如果存在）
    if (entry.secondaryKeys.isNotEmpty) {
      return _matchKeys(
        entry.secondaryKeys,
        text,
        entry.caseSensitive,
        entry.matchWholeWords,
        entry.useRegex,
        'any', // 次要键总是any模式
      );
    }

    return true;
  }

  /// 匹配关键词列表
  static bool _matchKeys(
    List<String> keys,
    String text,
    bool caseSensitive,
    bool matchWholeWords,
    bool useRegex,
    String mode,
  ) {
    if (keys.isEmpty) return false;

    final testText = caseSensitive ? text : text.toLowerCase();

    int matchedCount = 0;
    for (final key in keys) {
      final testKey = caseSensitive ? key : key.toLowerCase();

      bool matched = false;
      if (useRegex) {
        try {
          final regex = RegExp(testKey, caseSensitive: caseSensitive);
          matched = regex.hasMatch(text);
        } catch (_) {
          matched = testText.contains(testKey);
        }
      } else if (matchWholeWords) {
        final pattern = RegExp(r'\b' + RegExp.escape(testKey) + r'\b',
            caseSensitive: caseSensitive);
        matched = pattern.hasMatch(text);
      } else {
        matched = testText.contains(testKey);
      }

      if (matched) {
        matchedCount++;
        if (mode == 'any') return true; // any模式：任意匹配即返回
      }
    }

    return mode == 'all' && matchedCount == keys.length; // all模式：全部匹配
  }

  /// 格式化激活的条目为提示词注入文本
  static String formatActivatedEntries(List<WorldBookEntry> entries) {
    if (entries.isEmpty) return '';

    final grouped = <String, List<WorldBookEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.position, () => []).add(entry);
    }

    // 按position分组排序并拼接
    final buffer = StringBuffer();
    for (final position in ['before_char', 'after_char', 'author_note']) {
      final list = grouped[position];
      if (list != null && list.isNotEmpty) {
        // 按insertion_order排序
        list.sort((a, b) => a.insertionOrder.compareTo(b.insertionOrder));
        for (final entry in list) {
          buffer.writeln(entry.content.trim());
          buffer.writeln();
        }
      }
    }

    return buffer.toString().trim();
  }

  /// 创建条目
  Future<String> createEntry({
    required String bookId,
    String? botId,
    required String title,
    required String content,
    String comment = '',
    required List<String> keys,
    List<String> secondaryKeys = const [],
    String keyMode = 'any',
    bool caseSensitive = false,
    bool matchWholeWords = false,
    bool useRegex = false,
    String position = 'after_char',
    int insertionOrder = 100,
    int priority = 50,
  }) async {
    final database = await db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'wb_${now}_${content.hashCode.abs()}';

    final entry = WorldBookEntry(
      id: id,
      bookId: bookId,
      botId: botId,
      title: title,
      content: content,
      comment: comment,
      keys: keys,
      secondaryKeys: secondaryKeys,
      keyMode: keyMode,
      caseSensitive: caseSensitive,
      matchWholeWords: matchWholeWords,
      useRegex: useRegex,
      position: position,
      insertionOrder: insertionOrder,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );

    await database.insert('world_book_entries', entry.toMap());
    return id;
  }

  /// 更新条目
  Future<void> updateEntry(String entryId, Map<String, dynamic> updates) async {
    final database = await db.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final data = Map<String, dynamic>.from(updates);
    data['updated_at'] = now;

    // 处理List类型字段
    if (data.containsKey('keys') && data['keys'] is List) {
      data['keys'] = jsonEncode(data['keys']);
    }
    if (data.containsKey('secondaryKeys') && data['secondaryKeys'] is List) {
      data['secondary_keys'] = jsonEncode(data['secondaryKeys']);
      data.remove('secondaryKeys');
    }

    // 处理bool类型字段
    for (final field in [
      'caseSensitive',
      'matchWholeWords',
      'useRegex',
      'enabled'
    ]) {
      if (data.containsKey(field) && data[field] is bool) {
        final snakeCase = field.replaceAllMapped(
          RegExp(r'[A-Z]'),
          (m) => '_${m.group(0)!.toLowerCase()}',
        );
        data[snakeCase] = data[field] ? 1 : 0;
        data.remove(field);
      }
    }

    await database.update('world_book_entries', data,
        where: 'id = ?', whereArgs: [entryId]);
  }

  /// 删除条目
  Future<void> deleteEntry(String entryId) async {
    final database = await db.database;
    await database
        .delete('world_book_entries', where: 'id = ?', whereArgs: [entryId]);
  }

  /// 获取条目列表
  Future<List<WorldBookEntry>> getEntries(
      {String? bookId, String? botId}) async {
    final database = await db.database;

    String? where;
    List<dynamic>? whereArgs;

    if (bookId != null && botId != null) {
      where = 'book_id = ? AND (bot_id = ? OR bot_id IS NULL)';
      whereArgs = [bookId, botId];
    } else if (bookId != null) {
      where = 'book_id = ?';
      whereArgs = [bookId];
    } else if (botId != null) {
      where = 'bot_id = ? OR bot_id IS NULL';
      whereArgs = [botId];
    }

    final rows = await database.query(
      'world_book_entries',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'priority DESC, insertion_order ASC',
    );

    return rows.map((r) => WorldBookEntry.fromMap(r)).toList();
  }

  /// 创建世界书
  Future<String> createBook({
    required String name,
    String description = '',
    String? botId,
    bool isGlobal = false,
  }) async {
    final database = await db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'book_${now}_${name.hashCode.abs()}';

    await database.insert('world_books', {
      'id': id,
      'name': name,
      'description': description,
      'bot_id': botId,
      'is_global': isGlobal ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    });

    return id;
  }

  /// 获取世界书列表
  Future<List<Map<String, dynamic>>> getBooks({String? botId}) async {
    final database = await db.database;

    String? where;
    List<dynamic>? whereArgs;

    if (botId != null) {
      where = 'bot_id = ? OR is_global = 1';
      whereArgs = [botId];
    }

    return await database.query(
      'world_books',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'updated_at DESC',
    );
  }

  /// 删除世界书（级联删除所有条目）
  Future<void> deleteBook(String bookId) async {
    final database = await db.database;
    await database.delete('world_books', where: 'id = ?', whereArgs: [bookId]);
  }
}
