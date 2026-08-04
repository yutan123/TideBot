import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'db.dart';

class AIManager {
  static final AIManager _instance = AIManager._internal();
  factory AIManager() => _instance;
  AIManager._internal();

  // 1. 发送消息逻辑
  Future<Map<String, dynamic>> sendMessage({required String botId, required String text, String? imagePath, String? activeGame}) async {
    final db = DBManager();
    final bots = await db.getAllBots();
    final bot = bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
    if (bot.isEmpty) return {'error': '档案不存在'};

    final providerId = bot['chat_model'];
    if (providerId == null || providerId.isEmpty) return {'error': '未配置聊天模型，请在右上角设置中配置'};
    final provider = await db.getProviderById(providerId);
    if (provider == null) return {'error': '选中的模型提供商已被删除，请重新配置'};

    List<Map<String, dynamic>> messages = [];
    messages.add({'role': 'system', 'content': _buildSystemPrompt(bot, activeGame)});

    final history = await db.getChatHistory(botId);
    for (var msg in history.take(30)) {
      if (msg['type'] == 'text') messages.add({'role': msg['role'], 'content': msg['content']});
    }

    if (imagePath != null && imagePath.isNotEmpty) {
      try {
        final bytes = await File(imagePath).readAsBytes();
        final b64 = base64Encode(bytes);
        messages.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': text.isEmpty ? "请看图片" : text},
            {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$b64'}}
          ]
        });
      } catch (e) {
        messages.add({'role': 'user', 'content': text});
      }
    } else {
      messages.add({'role': 'user', 'content': text});
    }

    try {
      final response = await http.post(
        Uri.parse("${provider['base_url']}/chat/completions"),
        headers: {"Content-Type": "application/json", "Authorization": "Bearer ${provider['api_key']}"},
        body: jsonEncode({
          "model": provider['name'].toString().split(' / ').last, 
          "messages": messages, 
          "max_tokens": bot['max_tokens'] ?? 10000
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        String replyText = json['choices'][0]['message']['content'] ?? '';
        String mood = _extractMood(replyText);
        replyText = replyText.replaceAll(RegExp(r'\[心情:.*?\]'), '').trim();

        // 真实处理 TTS (如果配置了)
        String? audioPath;
        if (bot['tts_model'] != null && bot['tts_model'].toString().isNotEmpty) {
          audioPath = await _generateTTS(replyText, bot['tts_model']);
        }

        final ts = DateTime.now().millisecondsSinceEpoch;
        await db.insertChatMessage({'id': 'msg_${ts+1}', 'bot_id': botId, 'role': 'assistant', 'type': audioPath != null ? 'audio' : 'text', 'content': replyText, 'file_path': audioPath, 'mood': mood, 'timestamp': ts + 1});
        
        return {'success': true};
      } else {
        return {'error': 'API响应错误: ${response.statusCode}'};
      }
    } catch (e) {
      return {'error': '网络超时或跨域错误'};
    }
  }

  // 2. TTS 生成逻辑 (包含阿里云格式适配)
  Future<String?> _generateTTS(String text, String providerId) async {
    final provider = await DBManager().getProviderById(providerId);
    if (provider == null) return null;
    
    try {
      http.Response res;
      final modelName = provider['name'].toString().split(' / ').last;
      if (provider['base_url'].toString().contains('dashscope')) {
        // 阿里云百炼 TTS 特殊格式
        res = await http.post(
          Uri.parse("https://dashscope.aliyuncs.com/api/v1/services/audio/tts/text-to-wav"),
          headers: {"Content-Type": "application/json", "Authorization": "Bearer ${provider['api_key']}"},
          body: jsonEncode({"model": modelName, "input": {"text": text}, "parameters": {"format": "wav"}}),
        ).timeout(const Duration(seconds: 15));
      } else {
        // 标准 OpenAI TTS 格式
        res = await http.post(
          Uri.parse("${provider['base_url']}/audio/speech"),
          headers: {"Content-Type": "application/json", "Authorization": "Bearer ${provider['api_key']}"},
          body: jsonEncode({"model": modelName, "input": text, "voice": "alloy"}),
        ).timeout(const Duration(seconds: 15));
      }
      
      if (res.statusCode == 200) {
        final path = "/tmp/tide_tts_${DateTime.now().millisecondsSinceEpoch}.wav";
        await File(path).writeAsBytes(res.bodyBytes);
        return path;
      }
    } catch (e) {
      print("TTS Error: $e");
    }
    return null;
  }

  // 3. 今日一言自动生成器
  Future<String> getDailyQuote(String botId) async {
    final db = DBManager();
    final todayStr = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    final lastDate = await db.getKV('quote_date_$botId');
    final lastQuote = await db.getKV('quote_text_$botId');

    if (lastDate == todayStr && lastQuote != null) return lastQuote;

    final bots = await db.getAllBots();
    final bot = bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
    if (bot.isEmpty || bot['chat_model'] == null) return "今天也要开心度过哦。";

    final res = await sendMessage(botId: botId, text: "请结合你的人设，生成一句今天的早安问候或感悟，字数严格在10到15字，不要废话，不要包含[心情]标签。");
    if (res['success'] == true) {
      final history = await db.getChatHistory(botId);
      final lastMsg = history.last['content'].toString();
      await db.deleteMessage(history.last['id']); // 生成完删掉避免污染聊天记录
      await db.deleteMessage(history[history.length-2]['id']);
      
      await db.setKV('quote_date_$botId', todayStr);
      await db.setKV('quote_text_$botId', lastMsg);
      return lastMsg;
    }
    return "今天也要开心度过哦。";
  }

  // 4. 真实测速
  Future<Map<String, dynamic>> testConnection(String baseUrl, String apiKey, String modelName) async {
    final start = DateTime.now();
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/chat/completions"),
        headers: {"Content-Type": "application/json", "Authorization": "Bearer $apiKey"},
        body: jsonEncode({"model": modelName, "messages": [{"role": "user", "content": "1"}], "max_tokens": 5}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return {'success': true, 'delay': DateTime.now().difference(start).inMilliseconds};
      return {'success': false, 'error': '错误码: ${res.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': '连接超时或无效配置'};
    }
  }

  String _buildSystemPrompt(Map<String, dynamic> bot, String? activeGame) {
    String p = "你的名字是${bot['name']}。\n身世:${bot['desc']}\n说话方式:${bot['prompt']}\n当前时间:${DateTime.now()}。\n要求:你必须在回复的最开头输出当前心情标签，格式为[心情:开心]、[心情:伤心]、[心情:生气]、[心情:平静]之一。";
    if (activeGame == 'poker') p += "\n【系统强制规则】：你正在和用户玩两人扑克。牌组仅3~10共32张无大小王。每人16张。正常算力对战。绝对不可向用户透露你的底牌！要在闲聊中推进游戏。";
    if (activeGame == '20q') p += "\n【系统强制规则】：你正在玩20问猜物。只能回答是或否。";
    if (activeGame == 'gomoku') p += "\n【系统强制规则】：五子棋对战，使用棋盘坐标交互。";
    if (activeGame == 'tictactoe') p += "\n【系统强制规则】：井字棋对战，3x3坐标交互。";
    return p;
  }

  String _extractMood(String text) {
    if (text.contains('[心情:开心]')) return '开心';
    if (text.contains('[心情:伤心]')) return '伤心';
    if (text.contains('[心情:生气]')) return '生气';
    return '平静';
  }
}