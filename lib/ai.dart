import 'dart:convert';
import 'dart:io'; // 修复了报错，加入了必要的文件处理导入
import 'package:http/http.dart' as http;
import 'db.dart';
import 'ops.dart';

class AIManager {
  static final AIManager _instance = AIManager._internal();
  factory AIManager() => _instance;
  AIManager._internal();

  final List<String> _riskKeywords = ['自杀', '杀人', '毒品', '色情', '搞黄', '暴动'];

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

    final modelName = bot['default_model'] ?? 'deepseek-chat';
    final providerJson = await db.getKV('provider_$modelName');
    
    String baseUrl = "https://api.deepseek.com";
    String apiKey = "";
    String actualModel = modelName;

    if (providerJson != null) {
      final provider = jsonDecode(providerJson);
      baseUrl = provider['url'] ?? baseUrl;
      apiKey = provider['key'] ?? '';
    }

    final history = await db.getChatHistory(botId, limit: 30);
    List<Map<String, dynamic>> messages = [];
    
    messages.add({'role': 'system', 'content': _buildSystemPrompt(bot, activeGame)});

    for (var msg in history) {
      messages.add({'role': msg['role'], 'content': msg['content']});
    }

    String safeText = text;
    bool hasRisk = _riskKeywords.any((kw) => text.contains(kw));
    if (hasRisk) {
      safeText = "[系统警告：用户当前言辞可能涉及违规或极度负面情绪。请严格保持你的人设，用高情商、巧妙且转移注意力的方式化解，绝对不可输出任何违法违规内容！]\n用户说：" + text;
    }

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

    try {
      final response = await _callOpenAIFormatAPI(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: actualModel,
        messages: messages,
      );

      final replyText = response['content'] ?? '';
      final mood = _detectMood(replyText);
      
      String? ttsAudioPath;
      final ttsEnabled = await db.getKV('tts_enabled') == 'true';
      if (ttsEnabled && bot['tts_model'] != null) {
        ttsAudioPath = await generateTTS(replyText, bot['tts_model']);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await db.insertChatMessage({
        'id': 'msg_u_$timestamp',
        'bot_id': botId,
        'role': 'user',
        'content': text,
        'mood': 'normal',
        'timestamp': timestamp,
      });
      await db.insertChatMessage({
        'id': 'msg_b_${timestamp + 100}',
        'bot_id': botId,
        'role': 'assistant',
        'content': replyText,
        'mood': mood,
        'timestamp': timestamp + 100,
      });

      return {
        'success': true,
        'reply': replyText,
        'mood': mood,
        'audio': ttsAudioPath,
      };

    } catch (e) {
      return {'error': '引擎连接崩塌: ${e.toString()}'};
    }
  }

  String _detectMood(String text) {
    if (text.contains('开心') || text.contains('哈哈') || text.contains('😊') || text.contains('太好了')) return '开心';
    if (text.contains('难过') || text.contains('呜') || text.contains('抱抱')) return '伤心';
    if (text.contains('生气') || text.contains('哼') || text.contains('气死')) return '生气';
    return '开心';
  }

  String _buildSystemPrompt(Map<String, dynamic> bot, String? activeGame) {
    String basePrompt = bot['prompt'] ?? '你是一个温柔的AI伴侣。';
    String desc = bot['desc'] ?? '';
    String identity = "你的名字是 ${bot['name']}。\n身世设定：$desc\n说话方式：$basePrompt\n";
    
    identity += "当前系统时间：${DateTime.now().toString()}。\n";

    if (activeGame != null) {
      identity += "\n【系统强制规则：小游戏模式开启】\n";
      switch (activeGame) {
        case 'poker':
          identity += "你当前正在和用户玩两人对战扑克牌。规则：1. 牌组只有 3～10，一共 32 张牌，没有大小王和J、Q、K、A。2. 每个人发 16 张牌。正常扑克牌大小规则（对子、三带一、炸弹、顺子、单张等）。3. 你作为发牌员，在心里记住双方的牌，在对话中推进游戏。4. 绝对不能把你的牌直接告诉用户！5. 可以正常闲聊，不中断游戏。";
          break;
        case '20q':
          identity += "你当前正在和用户玩 20 问猜物游戏。规则：互猜谜底，最多问 20 个只能回答“是”或“否”的问题。";
          break;
        case 'gobang':
          identity += "你正在和用户玩五子棋（文字版坐标）。请遵守标准五子棋规则。";
          break;
        case 'tictactoe':
          identity += "你正在和用户玩井字棋（Tic-Tac-Toe）。使用 3x3 棋盘坐标。";
          break;
      }
    }
    return identity;
  }

  Future<Map<String, dynamic>> _callOpenAIFormatAPI({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
  }) async {
    final Map<String, dynamic> body = {
      "model": model.contains('/') ? model.split('/').last : model,
      "messages": messages,
    };

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
      };
    } else {
      throw Exception("API_ERROR: ${response.statusCode} - ${response.body}");
    }
  }

  Future<String?> generateTTS(String text, String ttsProviderId) async {
    try {
      final path = "/tmp/tide_tts_${DateTime.now().millisecondsSinceEpoch}.audio";
      final file = File(path); // 由于刚才没有引入 dart:io，这里导致了报错，现已修复
      await file.writeAsBytes([]);
      return path;
    } catch (e) {
      return null;
    }
  }

  Future<void> syncToWeChat(String contactId, String message) async {
    try {
      await http.post(
        Uri.parse('http://127.0.0.1:8080/openclaw/send'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "target": contactId,
          "message": message,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {}
  }
}