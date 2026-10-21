import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'db.dart';
import 'ai.dart';
import 'memory_prompt_policy.dart';

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

  // 对话结束计时器管理（key: botId, value: Timer）
  final Map<String, Timer> _conversationTimers = {};
  final Map<String, bool> _pendingJudgments = {}; // 防止重复触发

  /// 重置对话结束计时器（5分钟无互动后触发AI记忆判断）
  void resetConversationTimer(String botId) {
    // 取消现有计时器
    _conversationTimers[botId]?.cancel();

    // 启动新计时器：5分钟后触发
    _conversationTimers[botId] = Timer(const Duration(minutes: 5), () {
      triggerMemoryJudgment(botId);
    });
  }

  /// 取消对话结束计时器
  void cancelConversationTimer(String botId) {
    _conversationTimers[botId]?.cancel();
    _conversationTimers.remove(botId);
  }

  /// 触发AI记忆判断（对话结束时调用）
  Future<void> triggerMemoryJudgment(String botId) async {
    // 防止重复触发
    if (_pendingJudgments[botId] == true) return;
    _pendingJudgments[botId] = true;

    try {
      // 取消计时器
      cancelConversationTimer(botId);

      // SQL must select the newest records before limiting, then restore order.
      final messages = recentTaskMessages(
          await db.queryMessages(botId, limit: 160, descending: true),
          limit: 40);
      if (messages.length < 2) return;
      final cursorKey = 'memory_review_cursor_$botId';
      final lastId = await db.getKV(cursorKey);
      final previous = messages.indexWhere((m) => m['id'] == lastId);
      final fresh =
          previous >= 0 ? messages.skip(previous + 1).toList() : messages;
      if (fresh.isEmpty) return;
      final recentWorldBook = await db.queryMemories(botId, limit: 200);
      final existing =
          recentWorldBook.where((m) => m['category'] == '记忆').toList();
      final prompt = '请判断以下新增真实对话是否有值得保留的信息；寒暄、重复事实和琐碎细节不记。'
          '$memoryCategoryPolicy'
          '本任务只维护“记忆”事件条目，不得修改、删除或覆盖人物画像、自我认知和关系。'
          '先阅读最近世界书条目与已有记忆，再逐项比较人物、事件、核心事实；同一件事换标题、措辞、叙述角度或情绪描写都不算新事实。'
          '已经记录且没有新进展的内容不创建、不更新；补充已有记忆的信息，或同一事件有明确的新进展、更正时，直接用 update 和原 id 修改即可，无需 create 新条目；合并完整内容并保留仍有效事实。'
          '同一批 actions 也必须互相去重，不得将同一件事拆成多条近义记忆。'
          '不得为了整理旧条目删除无关内容；没有新增事实时返回 {"needUpdate":false,"actions":[]}。'
          '区分用户和角色，禁止把内部任务提示、引用记录、分析或工具协议写成记忆。'
          '未来约定以计划状态记录。输出 JSON：'
          '{"needUpdate":false,"actions":[]}；需要变更时 actions 中每项为 '
          '{"type":"create|update|delete","id":"更新或删除时的已有id",'
          '"title":"标题","content":"事实正文","keys":["关键词"],"priority":50}。'
          '\n当前本地时间：${DateTime.now().toIso8601String()}'
          '\n新增对话：${taskTranscript(fresh)}'
          '\n${recentMemoryReference(recentWorldBook)}'
          '\n已有记忆（只用于去重和更正）：${jsonEncode(existing)}';
      final result = await AIManager().sendMessage(
          botId: botId,
          task: AIRequestTask.memoryReview,
          text: prompt,
          priority: false,
          persistResponse: false);
      if (result['success'] != true) return;
      final judgment = jsonDecode(result['reply'] as String);
      final actions = validateMemoryReview(judgment, existing);
      final database = await db.database;
      await database.transaction((txn) async {
        for (var i = 0; i < actions.length; i++) {
          final action = actions[i];
          final type = action['type'];
          final now = DateTime.now().millisecondsSinceEpoch;
          if (type == 'delete') {
            await txn.delete('memories',
                where: 'bot_id = ? AND id = ? AND category = ?',
                whereArgs: [botId, action['id'], '记忆']);
            continue;
          }
          final values = memoryReviewValues(action, now);
          if (type == 'create') {
            if (existing.any((m) => m['content'] == action['content']))
              continue;
            await txn.insert('memories', {
              ...values,
              'id': 'mem_${now}_$i',
              'bot_id': botId,
              'category': '记忆',
              'type': 'short',
              'timestamp': now,
            });
          } else {
            await txn.update('memories', values,
                where: 'bot_id = ? AND id = ? AND category = ?',
                whereArgs: [botId, action['id'], '记忆']);
          }
        }
      });
      await db.setKV(cursorKey, fresh.last['id'].toString());
      debugPrint('[WorldBook] 记忆判断完成，执行了 ${actions.length} 个操作');
    } catch (e, st) {
      debugPrint('[WorldBook] 记忆判断异常: $e');
      debugPrint(st.toString());
    } finally {
      _pendingJudgments.remove(botId);
    }
  }

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
          buffer.writeln(
              '[记录时间：${DateTime.fromMillisecondsSinceEpoch(entry.createdAt).toIso8601String()}] ${entry.content.trim()}');
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

  // ========== N-gram 语义匹配（零成本方案）==========

  /// 生成 n-gram 集合
  static Set<String> _ngrams(String text, int n) {
    final grams = <String>{};
    final cleaned = text.replaceAll(RegExp(r'\s+'), '');
    for (int i = 0; i <= cleaned.length - n; i++) {
      grams.add(cleaned.substring(i, i + n));
    }
    return grams;
  }

  /// 计算 Jaccard 相似度
  static double _jaccardSimilarity(String a, String b, int n) {
    final gramsA = _ngrams(a, n);
    final gramsB = _ngrams(b, n);
    if (gramsA.isEmpty && gramsB.isEmpty) return 1.0;
    if (gramsA.isEmpty || gramsB.isEmpty) return 0.0;
    final intersection = gramsA.intersection(gramsB).length;
    final union = gramsA.union(gramsB).length;
    return union > 0 ? intersection / union : 0.0;
  }

  /// 混合相似度（2-gram + 3-gram）
  static double hybridSimilarity(String a, String b) {
    return _jaccardSimilarity(a, b, 2) * 0.6 +
        _jaccardSimilarity(a, b, 3) * 0.4;
  }

  /// N-gram 语义激活（用于关键词匹配失败时的补充）
  Future<List<WorldBookEntry>> activateEntriesNGram({
    required String botId,
    required String query,
    double threshold = 0.2,
    int limit = 5,
  }) async {
    final database = await db.database;

    // 获取所有启用条目
    final rows = await database.query(
      'world_book_entries',
      where: '(bot_id = ? OR bot_id IS NULL) AND enabled = 1',
      whereArgs: [botId],
    );

    if (rows.isEmpty) return [];

    final entries = rows.map((r) => WorldBookEntry.fromMap(r)).toList();
    final scored = <Map<String, dynamic>>[];

    for (final entry in entries) {
      // 计算标题和内容的综合相似度
      final titleSim = hybridSimilarity(query, entry.title);
      final contentSim = hybridSimilarity(query, entry.content);
      final score = max(titleSim * 1.2, contentSim); // 标题权重更高

      if (score > threshold) {
        scored.add({'entry': entry, 'score': score});
      }
    }

    // 按相似度排序
    scored
        .sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    // 更新激活统计
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in scored.take(limit)) {
      final entry = item['entry'] as WorldBookEntry;
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

    return scored.take(limit).map((s) => s['entry'] as WorldBookEntry).toList();
  }

  // ========== 记忆评分系统 ==========

  /// 计算记忆激活评分（综合时间衰减、激活强度、情绪匹配）
  static double calculateActivationScore({
    required WorldBookEntry entry,
    required String query,
    double currentEmotionValence = 0.0, // -1到+1，当前用户/机器人情绪
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. 时间新近度得分（Recency）
    final daysSinceActivation = entry.lastActivatedAt != null
        ? (now - entry.lastActivatedAt!) / 86400000
        : 9999.0;
    final recencyScore = 1.0 / (1.0 + daysSinceActivation * 0.05); // 20天后衰减到0.5

    // 2. 历史激活强度（Signal）
    final signalScore = min(entry.activationCount * 0.1, 1.0);

    // 3. 关键词匹配强度（Cue）
    final keyMatchCount = entry.keys
        .where((key) => query.toLowerCase().contains(key.toLowerCase()))
        .length;
    final cueScore = min(keyMatchCount / max(entry.keys.length, 1), 1.0);

    // 4. 优先级权重
    final priorityWeight = entry.priority / 100.0;

    // 综合评分（可根据实际情况调整权重）
    final rawScore = signalScore * 0.2 +
        cueScore * 2.0 +
        recencyScore * 1.0 +
        priorityWeight * 0.5;

    // Sigmoid 归一化到 0-1
    return 1.0 / (1.0 + exp(-rawScore));
  }

  /// 智能激活（关键词 + N-gram + 评分排序）
  Future<List<WorldBookEntry>> activateEntriesIntelligent({
    required String botId,
    required String conversationText,
    int maxResults = 10,
    double ngramThreshold = 0.2,
  }) async {
    // 第一层：关键词精确匹配
    final keywordMatches = await activateEntries(
      botId: botId,
      conversationText: conversationText,
    );

    // 如果关键词匹配足够，直接返回
    if (keywordMatches.length >= 5) {
      return keywordMatches.take(maxResults).toList();
    }

    // 第二层：N-gram 语义匹配（补充）
    final ngramMatches = await activateEntriesNGram(
      botId: botId,
      query: conversationText,
      threshold: ngramThreshold,
      limit: maxResults - keywordMatches.length,
    );

    // 合并去重
    final allMatches = <String, WorldBookEntry>{};
    for (final entry in keywordMatches) {
      allMatches[entry.id] = entry;
    }
    for (final entry in ngramMatches) {
      allMatches[entry.id] = entry;
    }

    // 按评分排序
    final entries = allMatches.values.toList();
    entries.sort((a, b) {
      final scoreA =
          calculateActivationScore(entry: a, query: conversationText);
      final scoreB =
          calculateActivationScore(entry: b, query: conversationText);
      return scoreB.compareTo(scoreA);
    });

    return entries.take(maxResults).toList();
  }

  // ========== 工具调用：记忆库搜索 ==========

  /// 供机器人主动搜索记忆库（tool 调用）
  Future<Map<String, dynamic>> searchMemoryForTool({
    required String botId,
    required String query,
    int limit = 5,
  }) async {
    try {
      debugPrint('[WorldBook] 机器人主动搜索记忆：$query');

      // Include the same memories table save_memory writes to, with writable IDs.
      final saved = await db.queryMemoriesRelevant(botId, query, limit: limit);
      if (saved.isNotEmpty) {
        return {
          'success': true,
          'found': true,
          'count': saved.length,
          'results': saved
              .map((row) => {
                    'id': row['id'],
                    'category': row['category'],
                    'title': row['title'],
                    'content': row['content'],
                    'type': row['type'],
                  })
              .toList(),
        };
      }
      // 使用智能激活（关键词 + N-gram）
      final results = await activateEntriesIntelligent(
        botId: botId,
        conversationText: query,
        maxResults: limit,
      );

      if (results.isEmpty) {
        return {
          'success': true,
          'found': false,
          'message': '没有找到相关记忆',
          'results': [],
        };
      }

      // 格式化返回结果
      final formattedResults = results.map((entry) {
        return {
          'recorded_at': DateTime.fromMillisecondsSinceEpoch(entry.createdAt)
              .toIso8601String(),
          'title': entry.title,
          'content': entry.content,
          'comment': entry.comment,
          'activation_count': entry.activationCount,
          'last_activated': entry.lastActivatedAt != null
              ? DateTime.fromMillisecondsSinceEpoch(entry.lastActivatedAt!)
                  .toString()
                  .substring(0, 19)
              : null,
        };
      }).toList();

      return {
        'success': true,
        'found': true,
        'count': results.length,
        'results': formattedResults,
        'message': '找到 ${results.length} 条相关记忆',
      };
    } catch (e) {
      debugPrint('[WorldBook] 搜索记忆异常: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
