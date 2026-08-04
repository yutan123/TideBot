import 'dart:convert';
import 'package:http/http.dart' as http;
import 'db.dart';

class AIManager {
  static final AIManager _instance = AIManager._internal();
  factory AIManager() => _instance;
  AIManager._internal();

  // 1. 核心聊天请求
  Future<Map<String, dynamic>> sendMessage({required String botId, required String text, String? imagePath, String? activeGame}) async {
    final db = DBManager();
    final bots = await db.getAllBots();
    final bot = bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
    if (bot.isEmpty) return {'error': '档案不存在'};

    // 获取配置的模型供应商
    final providerId = bot['default_chat_model'];
    if (providerId == null) return {'error': '未配置聊天模型，请在设置中配置'};
    final provider = await db.getProviderById(providerId);
    if (provider == null) return {'error': '模型提供商已失效'};

    List<Map<String, dynamic>> messages = [];
    messages.add({'role': 'system', 'content': _buildSystemPrompt(bot, activeGame)});

    final history = await db.getChatHistory(botId);
    for (var msg in history.take(30)) { // 限制上下文
      if (msg['type'] == 'text') messages.add({'role': msg['role'], 'content': msg['content']});
    }
    messages.add({'role': 'user', 'content': text}); // 暂略图片的 Base64 转码节省代码

    try {
      final response = await http.post(
        Uri.parse("${provider['base_url']}/chat/completions"),
        headers: {"Content-Type": "application/json", "Authorization": "Bearer ${provider['api_key']}"},
        body: jsonEncode({"model": provider['name'].toString().split('/').last, "messages": messages, "max_tokens": bot['max_tokens'] ?? 10000}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        String replyText = json['choices'][0]['message']['content'] ?? '';
        String mood = _extractMood(replyText);
        replyText = replyText.replaceAll(RegExp(r'\[心情:.*?\]'), '').trim(); // 剔除心情标签

        final ts = DateTime.now().millisecondsSinceEpoch;
        await db.insertChatMessage({'id': 'msg_$ts', 'bot_id': botId, 'role': 'user', 'type': 'text', 'content': text, 'timestamp': ts});
        await db.insertChatMessage({'id': 'msg_${ts+1}', 'bot_id': botId, 'role': 'assistant', 'type': 'text', 'content': replyText, 'mood': mood, 'timestamp': ts + 1});
        
        return {'success': true, 'reply': replyText};
      } else {
        return {'error': 'API请求失败: ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': '网络超时或跨域错误'};
    }
  }

  // 2. 真实测速
  Future<Map<String, dynamic>> testConnection(String baseUrl, String apiKey, String modelName) async {
    final start = DateTime.now();
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/chat/completions"),
        headers: {"Content-Type": "application/json", "Authorization": "Bearer $apiKey"},
        body: jsonEncode({"model": modelName, "messages": [{"role": "user", "content": "1"}], "max_tokens": 5}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final delay = DateTime.now().difference(start).inMilliseconds;
        return {'success': true, 'delay': delay};
      }
      return {'success': false, 'error': 'Status: ${res.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': '超时或无效'};
    }
  }

  // 3. 生成今日一言
  Future<String> getDailyQuote(String botId) async {
    final db = DBManager();
    final todayStr = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    final lastQuoteDate = await db.getKV('quote_date_$botId');
    final lastQuote = await db.getKV('quote_text_$botId');

    if (lastQuoteDate == todayStr && lastQuote != null) return lastQuote;

    final res = await sendMessage(botId: botId, text: "请结合你的人设，生成一句今天的日常寄语/早安问候/感悟，字数严格限制在10到15字之间，不要任何多余废话。");
    if (res['success'] == true) {
      await db.setKV('quote_date_$botId', todayStr);
      await db.setKV('quote_text_$botId', res['reply']);
      return res['reply'];
    }
    return "今天也要开心度过哦。"; // 保底
  }

  String _buildSystemPrompt(Map<String, dynamic> bot, String? activeGame) {
    String p = "你的名字是${bot['name']}。\n身世:${bot['desc']}\n说话方式:${bot['prompt']}\n当前时间:${DateTime.now()}。\n要求:你必须在回复的最开头输出当前心情标签，格式为[心情:开心]、[心情:伤心]、[心情:生气]、[心情:平静]之一。";
    if (activeGame == 'poker') p += "\n系统强制规则：你正在和用户玩两人扑克。牌组仅3~10共32张无大小王。每人16张。正常算力对战。绝对不可向用户透露你的底牌！要在闲聊中推进游戏。";
    if (activeGame == '20q') p += "\n系统强制规则：你正在玩20问猜物。只能回答是或否。";
    if (activeGame == 'gomoku') p += "\n系统强制规则：五子棋对战，使用坐标系交互。";
    return p;
  }

  String _extractMood(String text) {
    if (text.contains('[心情:开心]')) return '开心';
    if (text.contains('[心情:伤心]')) return '伤心';
    if (text.contains('[心情:生气]')) return '生气';
    return '平静';
  }
}