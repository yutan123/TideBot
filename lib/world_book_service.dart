import 'dart:async';
import 'dart:convert';
import 'db.dart';
import 'app_log_service.dart';

/// 世界书服务：机器人的自主记忆管理系统
///
/// 功能：
/// 1. 对话结束后AI自动判断是否需要记录/更新/删除记忆
/// 2. 发送消息前自动激活相关记忆注入提示词
/// 3. 支持关键词匹配、优先级排序、Token预算控制
class WorldBookService {
  WorldBookService._();
  static final WorldBookService instance = WorldBookService._();

  /// 对话计时器：用于检测5分钟无互动后触发AI记忆判断
  final Map<String, Timer> _conversationTimers = {};
  final Map<String, int> _lastUserMessageTime = {};

  /// 世界书Token预算配置（默认2000，用户可调）
  Future<int> getWorldBookTokenBudget() async {
    final db = DBManager();
    final value = await db.getKV('world_book_token_budget');
    return int.tryParse(value ?? '') ?? 2000;
  }

  Future<void> setWorldBookTokenBudget(int budget) async {
    final db = DBManager();
    await db.setKV('world_book_token_budget', budget.toString());
  }

  /// 对话结束判定时间（默认5分钟，可调）
  Future<int> getConversationEndMinutes() async {
    final db = DBManager();
    final value = await db.getKV('conversation_end_minutes');
    return int.tryParse(value ?? '') ?? 5;
  }

  Future<void> setConversationEndMinutes(int minutes) async {
    final db = DBManager();
    await db.setKV('conversation_end_minutes', minutes.toString());
  }

  /// 用户发送消息时调用：重置对话计时器
  void onUserMessage(String botId) {
    _lastUserMessageTime[botId] = DateTime.now().millisecondsSinceEpoch;
    _resetConversationTimer(botId);
  }

  /// 重置对话计时器
  void _resetConversationTimer(String botId) {
    _conversationTimers[botId]?.cancel();
    getConversationEndMinutes().then((minutes) {
      _conversationTimers[botId] = Timer(
        Duration(minutes: minutes),
        () => _onConversationEnd(botId),
      );
    });
  }

  /// 对话结束回调：触发AI记忆判断
  Future<void> _onConversationEnd(String botId) async {
    _conversationTimers.remove(botId);
    await triggerMemoryJudgment(botId);
  }

  /// 触发AI记忆判断（供外部调用，如检测到告别词时）
  Future<void> triggerMemoryJudgment(String botId) async {
    try {
      AppLogService.instance.add('WORLDBOOK', '开始对话记忆判断：$botId');
      // TODO: 调用AI判断是否需要新增/更新/删除记忆
      // 这里需要在ai.dart中实现AI记忆判断逻辑
      // 暂时先记录日志，后续实现完整逻辑
    } catch (e) {
      AppLogService.instance.add('WORLDBOOK', '记忆判断失败：$e');
    }
  }

  /// 激活世界书：根据用户消息匹配关键词，返回应注入的记忆列表
  Future<List<Map<String, dynamic>>> activateWorldBook({
    required String botId,
    required String userMessage,
    int scanDepth = 4,
  }) async {
    try {
      final db = DBManager();

      // 1. 收集最近N条消息
      final recentMessages = await db.queryMessages(
        botId,
        limit: scanDepth * 2,
        descending: true,
      );

      // 2. 提取关键词（简单分词）
      final keywords = _extractKeywords([
        userMessage,
        ...recentMessages
            .take(scanDepth)
            .map((m) => m['content']?.toString() ?? ''),
      ]);

      if (keywords.isEmpty) return [];

      // 3. 查询所有未删除的记忆
      final allMemories = await db.queryMemories(
        botId,
        includeExpired: false,
      );

      // 4. 匹配关键词并打分
      final matched = <Map<String, dynamic>>[];
      for (final memory in allMemories) {
        if ((memory['is_deleted'] as int?) == 1) continue;

        final keysJson = memory['keys_json']?.toString() ?? '[]';
        List<String> memoryKeys = [];
        try {
          memoryKeys = (jsonDecode(keysJson) as List).cast<String>();
        } catch (_) {}

        if (memoryKeys.isEmpty) continue;

        // 简单关键词匹配
        var hitCount = 0;
        for (final keyword in keywords) {
          for (final memKey in memoryKeys) {
            if (keyword.toLowerCase().contains(memKey.toLowerCase()) ||
                memKey.toLowerCase().contains(keyword.toLowerCase())) {
              hitCount++;
              break;
            }
          }
        }

        if (hitCount > 0) {
          final importance = (memory['importance'] as int?) ?? 3;
          final score = hitCount * 100 + importance * 10;
          matched.add({
            ...memory,
            '_score': score,
          });
        }
      }

      // 5. 按分数排序
      matched
          .sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));

      // 6. 按Token预算裁剪
      final budget = await getWorldBookTokenBudget();
      final result = <Map<String, dynamic>>[];
      var usedTokens = 0;

      for (final memory in matched) {
        final content = memory['content']?.toString() ?? '';
        final tokens = estimateTokens(content);

        if (usedTokens + tokens > budget) break;

        result.add(memory);
        usedTokens += tokens;

        // 更新激活统计
        final now = DateTime.now().millisecondsSinceEpoch;
        final memoryId = memory['id']?.toString() ?? '';
        if (memoryId.isNotEmpty) {
          await db.updateMemory(memoryId, {
            'trigger_count': ((memory['trigger_count'] as int?) ?? 0) + 1,
            'last_triggered_at': now,
          });
        }
      }

      AppLogService.instance.add(
        'WORLDBOOK',
        '激活${ result.length}条记忆，占用${usedTokens}tokens（预算$budget）',
      );

      return result;
    } catch (e) {
      AppLogService.instance.add('WORLDBOOK', '激活世界书失败：$e');
      return [];
    }
  }

  /// 提取关键词（简单中英文分词）
  Set<String> _extractKeywords(List<String> texts) {
    final keywords = <String>{};

    for (final text in texts) {
      // 分词
      final words = text.split(RegExp(r'[,，。.!！?？;；、\s]+'));
      for (final word in words) {
        final trimmed = word.trim();
        if (trimmed.length >= 2) {
          keywords.add(trimmed);
        }
      }

      // 中文二元组
      for (var i = 0; i < text.length - 1; i++) {
        final pair = text.substring(i, i + 2);
        if (pair.runes.every((r) => r >= 0x4E00 && r <= 0x9FFF)) {
          keywords.add(pair);
        }
      }
    }

    return keywords;
  }

  /// 查询世界书记忆（按最新更新时间排序，用于空间界面显示）
  Future<List<Map<String, dynamic>>> queryWorldBookMemories(
    String botId, {
    String? typeFilter,
    int? limit,
  }) async {
    final db = DBManager();
    final allMemories = await db.queryMemories(botId, type: typeFilter);

    // 过滤未删除的
    final valid =
        allMemories.where((m) => (m['is_deleted'] as int?) != 1).toList();

    // 按updated_at降序排序
    valid.sort((a, b) {
      final aTime = (a['updated_at'] as int?) ?? (a['timestamp'] as int?) ?? 0;
      final bTime = (b['updated_at'] as int?) ?? (b['timestamp'] as int?) ?? 0;
      return bTime.compareTo(aTime);
    });

    return limit != null ? valid.take(limit).toList() : valid;
  }

  /// 清理资源
  void dispose() {
    for (final timer in _conversationTimers.values) {
      timer.cancel();
    }
    _conversationTimers.clear();
    _lastUserMessageTime.clear();
  }
}
