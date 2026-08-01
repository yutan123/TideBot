import 'dart:convert';
import 'package:http/http.dart' as http;
import 'db.dart';
import 'ops.dart';

/// 核心大脑与大模型通信层 (ai.dart)
/// 负责所有 API 请求、Function Calling 路由、动态上下文注入及小游戏规则设定
class AIManager {
  static final AIManager _instance = AIManager._internal();
  factory AIManager() => _instance;
  AIManager._internal();

  // 基础高危词库（用于动态护栏检测）
  final List<String> _riskKeywords = ['自杀', '杀人', '毒品', '色情', '搞黄', '暴动'];

  // ==========================================
  // 核心对话流 (Chat Completion)
  // ==========================================

  /// 发送消息并获取回复
  /// [botId] 机器人ID, [text] 文本, [imageB64] 图片, [audioB64] 音频转文本后的补充, [activeGame] 当前开启的小游戏
  Future<Map<String, dynamic>> sendMessage({
    required String botId,
    required String text,
    String? imageB64,
    String? audioB64,
    String? activeGame,
  }) async {
    final db = DBManager();
    final bots = await db.getAllBots();
    final bot = bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
    if (bot.isEmpty) return {'error': '数字生命档案不存在'};

    // 1. 获取模型配置
    final modelName = bot['default_model'] ?? 'gpt-4o-mini';
    final providerJson = await db.getKV('provider_$modelName');
    if (providerJson == null) return {'error': '未找到对应的模型引擎配置'};
    final provider = jsonDecode(providerJson);

    // 2. 提取历史记录 (限制上下文)
    final maxTokens = bot['max_tokens'] ?? 10000;
    final history = await db.getChatHistory(botId, limit: 30); // 提取最近30条

    // 3. 构建消息体 (Messages)
    List<Map<String, dynamic>> messages = [];
    
    // 注入 System Prompt 与小游戏规则
    messages.add({'role': 'system', 'content': _buildSystemPrompt(bot, activeGame)});

    // 装载历史记录
    for (var msg in history) {
      messages.add({'role': msg['role'], 'content': msg['content']});
    }

    // 4. 动态上下文安全注入 (防违规护栏)
    String safeText = text;
    bool hasRisk = _riskKeywords.any((kw) => text.contains(kw));
    if (hasRisk) {
      safeText = "[系统警告：用户当前言辞可能涉及违规或极度负面情绪。请严格保持你的人设，用高情商、巧妙且转移注意力的方式化解，绝对不可输出任何违法违规内容！]\n用户说：" + text;
    }

    // 5. 多模态内容装载 (图片/文本)
    if (imageB64 != null && imageB64.isNotEmpty) {
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': safeText.isEmpty ? '请看这张图片' : safeText},
          {'type': 'image_url', 'image_url': {'url': imageB64}}
        ]
      });
    } else {
      messages.add({'role': 'user', 'content': safeText});
    }

    // 6. Function Calling 路由装载
    final tools = await _buildEnabledTools();

    // 7. 发起网络请求
    try {
      final response = await _callOpenAIFormatAPI(
        baseUrl: provider['baseUrl'],
        apiKey: provider['apiKey'],
        model: provider['model'],
        messages: messages,
        tools: tools,
      );

      // 8. 拦截与执行 Function Calling
      if (response['tool_calls'] != null) {
        return await _handleToolCalls(response['tool_calls'], botId, messages, provider);
      }

      final replyText = response['content'] ?? '';
      
      // 9. 异步生成 TTS (如果用户开启)
      String? ttsAudioPath;
      final ttsEnabled = await db.getKV('tts_enabled') == 'true';
      if (ttsEnabled && bot['tts_model'] != null) {
        ttsAudioPath = await generateTTS(replyText, bot['tts_model']);
      }

      // 10. 保存双向历史记录
      await db.insertChatMessage({
        'id': 'msg_u_${DateTime.now().millisecondsSinceEpoch}',
        'bot_id': botId,
        'role': 'user',
        'content': text,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      await db.insertChatMessage({
        'id': 'msg_b_${DateTime.now().millisecondsSinceEpoch}',
        'bot_id': botId,
        'role': 'assistant',
        'content': replyText,
        'timestamp': DateTime.now().millisecondsSinceEpoch + 100,
      });

      return {
        'success': true,
        'reply': replyText,
        'audio': ttsAudioPath,
      };

    } catch (e) {
      return {'error': '引擎连接崩塌: ${e.toString()}'};
    }
  }

  // ==========================================
  // System Prompt 与小游戏引擎聚合
  // ==========================================
  String _buildSystemPrompt(Map<String, dynamic> bot, String? activeGame) {
    String basePrompt = bot['prompt'] ?? '你是一个AI助手。';
    String desc = bot['desc'] ?? '';
    String identity = "你的名字是 ${bot['name']}。\n身世设定：$desc\n说话方式：$basePrompt\n";
    
    // 时间认知注入
    identity += "当前系统时间：${DateTime.now().toString()}。请具备正常的时间感知能力。\n";

    if (activeGame != null) {
      identity += "\n【系统强制规则：小游戏模式开启】\n";
      switch (activeGame) {
        case 'poker':
          identity += "你当前正在和用户玩两人对战扑克牌。规则如下：\n"
              "1. 牌组只有 3～10，一共 32 张牌，没有大小王和 J、Q、K、A。\n"
              "2. 每个人发 16 张牌。正常斗地主比大小规则（包含对子、三带一、炸弹、顺子、单张等）。\n"
              "3. 你作为发牌员，在心里记住双方的牌，并在对话中推进游戏。\n"
              "4. 绝对、绝对不能把你的牌直接告诉用户！\n"
              "5. 游戏过程中如果用户和你闲聊（如夸你厉害），你要符合人设正常回应，且不中断游戏进程。";
          break;
        case '20q':
          identity += "你当前正在和用户玩 20 问猜物游戏。规则：\n"
              "随机决定是你出题还是用户出题。猜的一方最多问 20 个只能回答“是”或“否”的问题。\n"
              "超过 20 问未猜出则出题方获胜。正常人设聊天不计入提问次数。";
          break;
        case 'gobang':
          identity += "你正在和用户玩五子棋（文字版坐标/简易展示）。请遵守标准五子棋规则，判断胜负。";
          break;
      }
    }
    return identity;
  }

  // ==========================================
  // Function Calling (Tools) 动态权限路由
  // ==========================================
  Future<List<Map<String, dynamic>>?> _buildEnabledTools() async {
    final db = DBManager();
    List<Map<String, dynamic>> tools = [];
    
    // 闹钟权限检查
    final alarmEnabled = await db.getKV('tool_alarm_enabled') == 'true';
    if (alarmEnabled) {
      tools.add({
        "type": "function",
        "function": {
          "name": "set_system_alarm",
          "description": "为用户设置手机系统闹钟或定时提醒",
          "parameters": {
            "type": "object",
            "properties": {
              "hour": {"type": "integer", "description": "小时(0-23)"},
              "minute": {"type": "integer", "description": "分钟(0-59)"},
              "message": {"type": "string", "description": "闹钟备注标签"}
            },
            "required": ["hour", "minute"]
          }
        }
      });
    }

    // 网页搜索检查 (Tavily/Bocha等中转工具，由底层发起)
    final searchEnabled = await db.getKV('set_web_search') == 'true';
    if (searchEnabled) {
      tools.add({
        "type": "function",
        "function": {
          "name": "search_web",
          "description": "当需要获取最新现实世界事实时调用",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {"type": "string", "description": "搜索关键词"}
            },
            "required": ["query"]
          }
        }
      });
    }
    return tools.isEmpty ? null : tools;
  }

  Future<Map<String, dynamic>> _handleToolCalls(List toolCalls, String botId, List<Map<String, dynamic>> messages, Map provider) async {
    final ops = OpsManager();
    
    for (var call in toolCalls) {
      final funcName = call['function']['name'];
      final args = jsonDecode(call['function']['arguments']);
      
      messages.add({
        'role': 'assistant',
        'content': null,
        'tool_calls': [call]
      });

      String toolResult = "";
      if (funcName == "set_system_alarm") {
        bool success = await ops.setSystemAlarm(args['hour'], args['minute'], args['message'] ?? '提醒');
        toolResult = success ? "闹钟设置成功" : "系统权限拒绝，设置失败";
      } else if (funcName == "search_web") {
        // TODO: 接入对应搜索引擎接口的逻辑
        toolResult = "搜索结果: 模拟返回实时数据...";
      }

      messages.add({
        'role': 'tool',
        'tool_call_id': call['id'],
        'name': funcName,
        'content': toolResult
      });
    }

    // 将执行结果返回给大模型进行最终总结
    final finalResponse = await _callOpenAIFormatAPI(
      baseUrl: provider['baseUrl'],
      apiKey: provider['apiKey'],
      model: provider['model'],
      messages: messages,
    );

    return {'success': true, 'reply': finalResponse['content']};
  }

  // ==========================================
  // 核心 HTTP 通信协议 (兼容绝大多数兼容 OpenAI 格式的厂商)
  // ==========================================
  Future<Map<String, dynamic>> _callOpenAIFormatAPI({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  }) async {
    final Map<String, dynamic> body = {
      "model": model,
      "messages": messages,
    };
    if (tools != null) body["tools"] = tools;

    final response = await http.post(
      Uri.parse("$baseUrl/chat/completions"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $apiKey"
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 40));

    if (response.statusCode == 200) {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final messageObj = json['choices'][0]['message'];
      return {
        'content': messageObj['content'],
        'tool_calls': messageObj['tool_calls']
      };
    } else {
      throw Exception("API_ERROR: ${response.statusCode} - ${response.body}");
    }
  }

  // ==========================================
  // TTS 引擎调度 (特殊处理阿里云百炼格式)
  // ==========================================
  Future<String?> generateTTS(String text, String ttsProviderId) async {
    final db = DBManager();
    final providerJson = await db.getKV('tts_$ttsProviderId');
    if (providerJson == null) return null;
    final provider = jsonDecode(providerJson);
    
    final baseUrl = provider['baseUrl'];
    final apiKey = provider['apiKey'];
    final model = provider['model']; // 例如 sambert-zhimiao-emo

    try {
      http.Response response;
      if (baseUrl.contains('dashscope')) {
        // 阿里云百炼专属协议
        response = await http.post(
          Uri.parse('https://dashscope.aliyuncs.com/api/v1/services/audio/tts/text-to-wav'),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $apiKey"
          },
          body: jsonEncode({
            "model": model,
            "input": {"text": text},
            "parameters": {"format": "wav"}
          }),
        );
      } else {
        // 兼容 OpenAI 格式的 TTS (如 Siliconflow)
        response = await http.post(
          Uri.parse("$baseUrl/audio/speech"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $apiKey"
          },
          body: jsonEncode({
            "model": model,
            "input": text,
            "voice": provider['voiceId'] ?? "alloy",
            "response_format": "mp3"
          }),
        );
      }

      if (response.statusCode == 200) {
        // 交由 OpsManager 写入本地沙盒
        // 此处简化，实际通过 getApplicationDocumentsDirectory 写入
        final path = "/tmp/tide_tts_${DateTime.now().millisecondsSinceEpoch}.audio";
        final file = File(path);
        await file.writeAsBytes(response.bodyBytes);
        return path;
      }
    } catch (e) {
      print("TTS Error: $e");
    }
    return null;
  }

  // ==========================================
  // OpenClaw 微信桥接同步机制
  // ==========================================
  
  /// 将消息同步到本地运行的 OpenClaw 服务，再转发到微信
  Future<void> syncToWeChat(String contactId, String message) async {
    // OpenClaw 通常默认在本地暴露一个 HTTP 端口进行 webhook 通信
    try {
      await http.post(
        Uri.parse('http://127.0.0.1:8080/openclaw/send'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "target": contactId,
          "message": message,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      // 桥接失败忽略，不阻塞主线程
    }
  }
}