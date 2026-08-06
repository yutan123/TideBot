import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'db.dart';

class AIManager {
  static final AIManager _instance = AIManager._internal();
  factory AIManager() => _instance;
  AIManager._internal();

  // 新 UI 调用的 chat 包装（直接以 botId 为核心，读取该 bot 配置的模型）
  Future<String> chat({
    required String botId,
    required List<Map<String, dynamic>> messages,
    String imageBase64 = '',
  }) async {
    // 用最后一条 user 消息作为文本
    final lastUser = messages.lastWhere((m) => m['role'] == 'user', orElse: () => {'content': ''});
    final text = lastUser['content'] as String? ?? '';

    // 如果有 Base64 图片，先写入临时文件再传给 sendMessage
    String? imgPath;
    if (imageBase64.isNotEmpty) {
      try {
        final tmpFile = File('/tmp/tide_img_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tmpFile.writeAsBytes(base64Decode(imageBase64));
        imgPath = tmpFile.path;
      } catch (_) {}
    }
    final res = await sendMessage(botId: botId, text: text, imagePath: imgPath);
    if (res['success'] == true) {
      // 直接返回本次 HTTP 响应，不能重新读取数据库“最后一条”消息；
      // 后者可能因写入时序返回旧消息或空消息。
      return res['reply']?.toString() ?? '';
    }
    return res['error']?.toString() ?? '';

  }
  Future<Map<String, dynamic>> sendMessage({
    required String botId, 
    required String text, 
    String? imagePath, 
    String? activeGame // 支持动态注入游戏规则
  }) async {
    final db = DBManager();
    final bots = await db.getAllBots();
    final bot = bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
    if (bot.isEmpty) return {'error': '系统异常：生命体档案丢失'};

    // 提取该 bot 配置的 provider id（存在 bots.chat_model 字段，由聊天室设置弹窗写入）
    final providerId = bot['chat_model'];
    if (providerId == null || providerId.toString().isEmpty) return {'error': '未配置引擎中枢，请先在聊天页设置模型'};
    // 优先用统一的聊天链路读取，兼容 API 设置页的 provider_list
    final provider = await db.getChatProviderById(providerId.toString());
    if (provider == null) return {'error': '映射的模型已被删除，请重新配置'};
    // 模型名：优先用 provider['model']（多个逗号分隔取第一个），否则退回 name 最后一段
    String modelName = (provider['model'] as String? ?? '').trim();
    if (modelName.isEmpty) {
      modelName = provider['name'].toString().trim();
    }
    if (modelName.contains(',')) modelName = modelName.split(',').first.trim();

    List<Map<String, dynamic>> messages = [];
    
    // 注入底层角色设定与游戏规则
    messages.add({'role': 'system', 'content': _buildSystemPrompt(bot, activeGame)});

    // 截取最近 20 条对话作为短记忆上下文
    final history = await db.getChatHistory(botId);
    var lastIsCurrentUser = false;
    for (var msg in history.take(20)) {
      if (msg['type'] == 'text') {
        messages.add({'role': msg['role'], 'content': msg['content']});
      }
    }
    // 若最末一条上下文恰好就是本次发送的 user 文本（内存补写导致），
    // 标记以免下方再次追加造成重复喂给模型
    if (history.isNotEmpty) {
      final lastMsg = history.last;
      if ((lastMsg['role'] == 'user') && (lastMsg['content']?.toString() == text) && history.length < 20) {
        lastIsCurrentUser = true;
      }
    }

    // 视觉模态处理 (图片 Base64 注入)
    if (imagePath != null && imagePath.isNotEmpty) {
      try {
        final bytes = await File(imagePath).readAsBytes();
        final b64 = base64Encode(bytes);
        messages.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': text == "[语音/图片]" ? "请看这张图片。" : text},
            {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$b64'}}
          ]
        });
      } catch (e) {
        if (!lastIsCurrentUser) messages.add({'role': 'user', 'content': text});
      }
    } else if (!lastIsCurrentUser) {
      messages.add({'role': 'user', 'content': text});
    }
    try {
      final baseUrl = provider['base_url']?.toString().trim().replaceFirst(RegExp(r'/+$'), '') ?? '';
      if (baseUrl.isEmpty) return {'error': '模型提供商缺少 Base URL，请在 API 设置中补充'};
      print('[ai] request bot=$botId provider=$providerId model=$modelName url=$baseUrl/chat/completions');
      final response = await http.post(
        Uri.parse("$baseUrl/chat/completions"),

        headers: {
          "Content-Type": "application/json", 
          "Authorization": "Bearer ${provider['api_key']}"
        },
        body: jsonEncode({
          "model": modelName, 
          "messages": messages, 
          "max_tokens": bot['max_tokens'] ?? 10000
        }),
      ).timeout(const Duration(seconds: 40));
      print('[ai] response status=${response.statusCode}');
      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));

        String replyText = json['choices'][0]['message']['content'] ?? '';
        
        // 情绪提取器：解析并剔除底层情绪标签
        String mood = _extractMood(replyText);
        replyText = replyText.replaceAll(RegExp(r'\[心情:.*?\]'), '').trim();

        // 语音模态处理：TTS 生成改为后台执行，绝不阻塞文本回复，
        // 否则 TTS 请求最长 20 秒会卡死整个发送链路，导致"发送没反应/无气泡"。
        final ts = DateTime.now().millisecondsSinceEpoch;
        final msgId = 'msg_a_${ts+1}';
        await db.insertChatMessage({
          'id': msgId,
          'bot_id': botId,
          'role': 'assistant',
          'type': 'text',
          'content': replyText,
          'file_path': null,
          'mood': mood,
          'timestamp': ts + 1
        });
        final ttsModel = bot['tts_model'];
        if (ttsModel != null && ttsModel.toString().isNotEmpty) {
          // fire-and-forget：后台生成语音，成功后单独把该气泡升级为 audio 类型（replace 覆盖同 id）
          unawaited(() async {
            final audioPath = await _generateTTS(replyText, ttsModel.toString());
            if (audioPath != null && audioPath.isNotEmpty) {
              try {
                await db.insertChatMessage({
                  'id': msgId,
                  'bot_id': botId,
                  'role': 'assistant',
                  'type': 'audio',
                  'content': replyText,
                  'file_path': audioPath,
                  'mood': mood,
                  'timestamp': ts + 1,
                });
              } catch (_) {}
            }
          }());
        }
        return {'success': true, 'reply': replyText};
      } else {
        final body = utf8.decode(response.bodyBytes);
        final detail = body.replaceAll(RegExp(r'\s+'), ' ').trim();
        print('[ai] response error=${detail.length > 300 ? detail.substring(0, 300) : detail}');
        return {'error': '大模型节点拥堵或拒绝访问: ${response.statusCode}'};
      }
    } catch (e) {
      print('[ai] request failed: $e');
      return {'error': '本地网络异常或网关超时'};

    }
  }

  // 特异化 TTS 处理 (兼容标准协议与阿里云百炼特异 Payload)
  Future<String?> _generateTTS(String text, String providerId) async {
    // TTS provider 独立存放于 tts_provider_list，用 id 前缀 ts_ 标识，含 voice 音色字段
    final list = await DBManager().queryTtsProviders();
    Map<String, dynamic>? provider;
    try { provider = list.firstWhere((p) => p['id'] == providerId); } catch (_) {}
    if (provider == null) return null;
    
    final String voice = (provider['voice'] as String? ?? '').trim().isEmpty
        ? 'alloy'
        : (provider['voice'] as String?).toString();
    try {
      http.Response res;
      final modelName = (provider['model'] as String? ?? '').trim();
      final modelForUrl = modelName.isEmpty ? provider['name'].toString() : modelName;
      
      if (provider['base_url'].toString().contains('dashscope')) {
        res = await http.post(
          Uri.parse("https://dashscope.aliyuncs.com/api/v1/services/audio/tts/text-to-wav"),
          headers: {"Content-Type": "application/json", "Authorization": "Bearer ${provider['api_key']}"},
          body: jsonEncode({"model": modelForUrl, "input": {"text": text}, "parameters": {"format": "wav"}}),
        ).timeout(const Duration(seconds: 20));
      } else {
        res = await http.post(
          Uri.parse("${provider['base_url']}/audio/speech"),
          headers: {"Content-Type": "application/json", "Authorization": "Bearer ${provider['api_key']}"},
          body: jsonEncode({"model": modelName, "input": text, "voice": voice}),
        ).timeout(const Duration(seconds: 20));
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

  // 空间广场：今日一言生成逻辑
  Future<String> getDailyQuote(String botId) async {
    final db = DBManager();
    final todayStr = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    final lastDate = await db.getKV('quote_date_$botId');
    final lastQuote = await db.getKV('quote_text_$botId');

    if (lastDate == todayStr && lastQuote != null) return lastQuote;

    final bots = await db.getAllBots();
    final bot = bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
    if (bot.isEmpty || bot['chat_model'] == null) return "今天也要开心度过哦。";

    // 暗中调用 AI 引擎生成，但不暴露在聊天历史中
    final res = await sendMessage(botId: botId, text: "请结合你的人设，生成一句今天的早安问候或感悟，字数严格在10到15字，不要废话，不要包含[心情]标签。");
    if (res['success'] == true) {
      final history = await db.getChatHistory(botId);
      final lastMsg = history.last['content'].toString();
      // 阅后即焚，防止污染日常对话
      await db.deleteMessage(history.last['id']); 
      await db.deleteMessage(history[history.length-2]['id']);
      
      await db.setKV('quote_date_$botId', todayStr);
      await db.setKV('quote_text_$botId', lastMsg);
      return lastMsg;
    }
    return "今天也要开心度过哦。";
  }

  // API 测速（返回 Map，兼容旧代码）
  Future<Map<String, dynamic>> testConnectionMap(String baseUrl, String apiKey, String modelName) async {
    final start = DateTime.now();
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/chat/completions"),
        headers: {"Content-Type": "application/json", "Authorization": "Bearer $apiKey"},
        body: jsonEncode({"model": modelName, "messages": [{"role": "user", "content": "1"}], "max_tokens": 5}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return {'success': true, 'delay': DateTime.now().difference(start).inMilliseconds};
      return {'success': false, 'error': '服务端返回 HTTP ${res.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': '无法连接，请检查 URL 格式或网络'};
    }
  }

  // API 测速（返回 int 毫秒，供新 UI 使用；失败抛异常）
  Future<int> testConnection(String baseUrl, String apiKey, String modelName) async {
    final result = await testConnectionMap(baseUrl, apiKey, modelName);
    if (result['success'] == true) {
      return result['delay'] as int;
    }
    throw Exception(result['error'] ?? '连接失败');
  }

  // 构建核心防御护栏与游戏机制注入
  String _buildSystemPrompt(Map<String, dynamic> bot, String? activeGame) {
    String p = "你的名字是${bot['name']}。\n身世与设定:${bot['desc']}\n说话方式指令:${bot['prompt']}\n"
               "当前现实时间:${DateTime.now()}。\n"
               "【底层强制核心规则】: 你必须在每次回复的最开头，输出当前的心情标签，格式只能是[心情:开心]、[心情:伤心]、[心情:生气]、[心情:平静]四个中的一个。";
    
    if (activeGame == 'poker') {
      p += "\n【系统级游戏劫持】：你当前正在和用户玩双人扑克牌。规则极度严格：牌组仅限 3~10，共32张，没有大小王。每人随机发16张牌。正常的算力对战（单张、对子、三带一、顺子、炸弹）。绝对不可向用户透露你手中的底牌！你需要在每次闲聊中推进游戏局势并描述你出的牌。";
    } else if (activeGame == '20q') {
      p += "\n【系统级游戏劫持】：你当前正在玩 20 问猜物游戏。如果用户是出题人，你只能问 20 个问题，且必须根据用户的“是”或“否”推断出答案；如果你是出题人，你只能回答“是”或“否”。在 20 问内未能猜出则判定输。";
    } else if (activeGame == 'gomoku') {
      p += "\n【系统级游戏劫持】：你正在进行五子棋心算对战，请使用标准的棋盘坐标系与用户交互落子点。";
    }
    return p;
  }

  String _extractMood(String text) {
    if (text.contains('[心情:开心]')) return '开心';
    if (text.contains('[心情:伤心]')) return '伤心';
    if (text.contains('[心情:生气]')) return '生气';
    return '平静';
  }
}