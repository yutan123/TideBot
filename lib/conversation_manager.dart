import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';
import 'ai.dart';
import 'app_log_service.dart';

/// 对话管理器：负责判定对话结束并触发AI记忆判断
class ConversationManager {
  static final ConversationManager _instance = ConversationManager._();
  static ConversationManager get instance => _instance;
  ConversationManager._();

  // 每个机器人的对话计时器
  final Map<String, Timer?> _timers = {};
  // 每个机器人的最后用户消息时间
  final Map<String, DateTime> _lastUserMessageTime = ;
  // 每个机器人的待处理消息列表（用于对话结束时一起处理）
  final Map<String, List<String>> _pendingMessages = {};
  // 正在处理中的机器人（避免重复触发）
  final Set<String> _processing = {};

  // 对话超时时间（分钟）
  static const int _timeoutMinutes = 5;

  /// 用户发送消息时调用（重置计时器）
  void onUserMessage(String botId, String message) {
    // 记录时间
    _lastUserMessageTime[botId] = DateTime.now();
    
    // 记录消息（用于后续判断）
    _pendingMessages.putIfAbsent(botId, () => []).add(message);
    
    // 取消旧计时器
    _timers[botId]?.cancel();
    
    // 启动新计时器
    _timers[botId] = Timer(
      const Duration(minutes: _timeoutMinutes),
      () => _onConversationEnd(botId),
    );
    
    AppLogService.log('对话管理', '用户发送消息，重置计时器: $botId');
  }

  /// 检测到告别词时调用（立即触发）
  void onFarewellDetected(String botId, String message) {
    AppLogService.log('对话管理', '检测到告别词: $botId');
    _timers[botId]?.cancel();
    _onConversationEnd(botId);
  }

  /// 对话结束处理
  Future<void> _onConversationEnd(String botId) async {
    if (_processing.contains(botId)) {
      AppLogService.log('对话管理', '跳过重复处理: $botId');
      return;
    }

    _processing.add(botId);
    _timers[botId]?.cancel();
    _timers.remove(botId);

    try {
      AppLogService.log('对话管理', '对话结束，开始AI记忆判断: $botId');
      
      // 获取本次对话的消息
      final messages = _pendingMessages[botId] ?? [];
      if (messages.isEmpty) {
        AppLogService.log('对话管理', '无待处理消息，跳过: $botId');
        return;
      }

      // 调用AI判断是否需要操作记忆
      await _triggerMemoryJudgment(botId, messages);
      
      // 清空待处理消息
      _pendingMessages[botId]?.clear();
      _lastUserMessageTime.remove(botId);
      
    } catch (e) {
      AppLogService.log('对话管理', '处理对话结束失败: $e');
    } finally {
      _processing.remove(botId);
    }
  }

  /// 触发AI记忆判断
  Future<void> _triggerMemoryJudgment(String botId, List<String> messages) async {
    try {
      final db = DBManager();
      
      // 获取机器人信息
      final bot = await db.getBot(botId);
      if (bot == null) return;
      
      final botName = bot['name']?.toString() ?? '机器人';
      
      // 获取最近的对话历史（最多10条）
      final recentHistory = await db.queryMessages(
        botId,
        limit: 10,
        offset: 0,
      );
      
      // 构建提示词
      final prompt = _buildMemoryJudgmentPrompt(botName, messages, recentHistory);
      
      AppLogService.log('对话管理', 'AI记忆判断提示词:\n$prompt');
      
      // 调用AI
      final result = await AI().sendMessage(
        botId: botId,
        text: prompt,
        persistResponse: false, // 不保存这次判断对话
        includeChatHistory: false, // 不包含历史
        enableAutoSummary: false,
        allowTools: false,
        forceSingleReply: true,
      );
      
      if (result['success'] == true) {
        final reply = result['reply']?.toString() ?? '';
        await _parseAndExecuteMemoryOperations(botId, reply);
      } else {
        AppLogService.log('对话管理', 'AI记忆判断失败: ${result['error']}');
      }
      
    } catch (e) {
      AppLogService.log('对话管理', 'AI记忆判断异常: $e');
    }
  }

  /// 构建记忆判断提示词
  String _buildMemoryJudgmentPrompt(
    String botName,
    List<String> messages,
    List<Map<String, dynamic>> recentHistory,
  ) {
    final historyText = recentHistory
        .map((m) => '${m['sender_type'] == 'user' ? '用户' : botName}: ${m['content']}')
        .join('\n');
    
    final messagesText = messages.map((m) => '- $m').join('\n');
    
    return '''你是 $botName，现在对话暂时结束了。请回顾刚才的对话内容，判断是否有需要记录到世界书的重要信息。

【最近对话历史】
$historyText

【本次对话要点】
$messagesText

【世界书说明】
世界书是你的长期记忆系统，用于记录：
- 关于你自己的信息（性格、喜好、经历、观点）
- 关于用户的信息（姓名、喜好、重要事件、关系进展）
- 重要的约定、承诺、计划
- 需要长期记住的事实和知识

不应记录：
- 普通寒暄和日常问候
- 已有且未改变的信息
- 过于琐碎的细节

【操作格式】
如果需要操作世界书，请按以下JSON格式回复（可以有多个操作）：

```json
{
  "operations": [
    {
      "action": "add",
      "content": "记忆内容",
      "keys": ["关键词1", "关键词2"],
      "priority": 50,
      "type": "long"
    },
    {
      "action": "update",
      "old_content": "旧的记忆内容（用于匹配）",
      "new_content": "更新后的内容",
      "keys": ["关键词1"],
      "priority": 60
    },
    {
      "action": "delete",
      "content": "要删除的记忆内容（用于匹配）"
    }
  ]
}
```

action 可选：add（新增）、update（更新）、delete（删除）
type 可选：long（长期记忆）、short（短期记忆，默认long）
priority：优先级 0-100，默认50，重要的用更高数值

如果不需要操作世界书，直接回复：{"operations": []}

请现在判断并给出操作指令：''';
  }

  /// 解析AI回复并执行记忆操作
  Future<void> _parseAndExecuteMemoryOperations(String botId, String reply) async {
    try {
      // 提取JSON
      final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(reply);
      String jsonStr = jsonMatch?.group(1) ?? reply;
      
      // 清理非JSON内容
      jsonStr = jsonStr.trim();
      if (!jsonStr.startsWith('{')) {
        final start = jsonStr.indexOf('{');
        if (start != -1) jsonStr = jsonStr.substring(start);
      }
      if (!jsonStr.endsWith('}')) {
        final end = jsonStr.lastIndexOf('}');
        if (end != -1) jsonStr = jsonStr.substring(0, end + 1);
      }
      
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final operations = data['operations'] as List<dynamic>? ?? [];
      
      if (operations.isEmpty) {
        AppLogService.log('对话管理', '无需操作世界书');
        return;
      }
      
      final db = DBManager();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      for (final op in operations) {
        final opMap = op as Map<String, dynamic>;
        final action = opMap['action']?.toString() ?? '';
        
        try {
          switch (action) {
            case 'add':
              final content = opMap['content']?.toString() ?? '';
              final keys = (opMap['keys'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ?? [];
              final priority = (opMap['priority'] as num?)?.toInt() ?? 50;
              final type = opMap['type']?.toString() ?? 'long';
              
              if (content.isNotEmpty && keys.isNotEmpty) {
                await db.insertMemory({
                  'id': 'mem_$now',
                  'bot_id': botId,
                  'content': content,
                  'type': type,
                  'keys': keys.join('|'),
                  'priority': priority,
                  'timestamp': now,
                });
                AppLogService.log('对话管理', '新增世界书: $content');
              }
              break;
              
            case 'update':
              final oldContent = opMap['old_content']?.toString() ?? '';
              final newContent = opMap['new_content']?.toString() ?? '';
              final keys = (opMap['keys'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList();
              final priority = opMap['priority'] as num?;
              
              if (oldContent.isNotEmpty && newContent.isNotEmpty) {
                // 查找匹配的记忆
                final memories = await db.queryMemories(botId);
                final target = memories.firstWhere(
                  (m) => m['content']?.toString().contains(oldContent) == true,
                  orElse: () => <String, dynamic>{},
                );
                
                if (target.isNotEmpty) {
                  final updates = <String, dynamic>{
                    'content': newContent,
                    'timestamp': now,
                  };
                  if (keys != null) updates['keys'] = keys.join('|');
                  if (priority != null) updates['priority'] = priority.toInt();
                  
                  await db.updateMemory(target['id'].toString(), updates);
                  AppLogService.log('对话管理', '更新世界书: $oldContent -> $newContent');
                }
              }
              break;
              
            case 'delete':
              final content = opMap['content']?.toString() ?? '';
              
              if (content.isNotEmpty) {
                final memories = await db.queryMemories(botId);
                final target = memories.firstWhere(
                  (m) => m['content']?.toString().contains(content) == true,
                  orElse: () => <String, dynamic>{},
                );
                
                if (target.isNotEmpty) {
                  await db.deleteMemory(target['id'].toString());
                  AppLogService.log('对话管理', '删除世界书: $content');
                }
              }
              break;
          }
        } catch (e) {
          AppLogService.log('对话管理', '执行操作失败: $action, $e');
        }
      }
      
      AppLogService.log('对话管理', '完成 ${operations.length} 个世界书操作');
      
    } catch (e) {
      AppLogService.log('对话管理', '解析AI回复失败: $e\n原始回复: $reply');
    }
  }

  /// 检查是否为告别词
  static bool isFarewellMessage(String text) {
    final farewells = [
      '再见', '拜拜', '晚安', '回见', '下次见', '明天见',
      'bye', 'goodbye', 'good night', 'see you',
      '88', '886', '拜了', '溜了', '睡了', '先走了'
    ];
    
    final lowerText = text.toLowerCase().trim();
    return farewells.any((word) => lowerText.contains(word));
  }

  /// 清理指定机器人的计时器
  void cleanup(String botId) {
    _timers[botId]?.cancel();
    _timers.remove(botId);
    _pendingMessages.remove(botId);
    _lastUserMessageTime.remove(botId);
  }

  /// 清理所有计时器
  void cleanupAll() {
    for (final timer in _timers.values) {
      timer?.cancel();
    }
    _timers.clear();
    _pendingMessages.clear();
    _lastUserMessageTime.clear();
    _processing.clear();
  }
}
