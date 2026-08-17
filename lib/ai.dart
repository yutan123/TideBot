import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';
import 'life_schedule_service.dart';
import 'media_preprocessor.dart';

import 'ops.dart';
import 'app_state.dart';
import 'app_log_service.dart';
import 'emotion_state_service.dart';
import 'device_capability_service.dart';
import 'local_llama.dart';

const bool _localInferenceEnabled = false;

class AIManager {
  static final AIManager _instance = AIManager._internal();
  factory AIManager() => _instance;
  AIManager._internal();

  // 结构化聊天结果供聊天室展示完整错误日志；旧 chat 接口继续返回纯文本。
  Future<Map<String, dynamic>> chatResult({
    required String botId,
    required List<Map<String, dynamic>> messages,
    String imageBase64 = '',
    void Function(String delta)? onDelta,
    // 合并/防抖重发时，被拦截的过期请求应跳过落库，避免库里出现“旧回复”，
    // 再由合并后的新请求统一落库，保证聊天记录与界面顺序一致。
    bool persistResponse = true,
  }) async {
    final lastUser = messages.lastWhere((m) => m['role'] == 'user',
        orElse: () => {'content': ''});
    final text = lastUser['content'] as String? ?? '';

    String? imgPath;
    if (imageBase64.isNotEmpty) {
      try {
        final directory = await getTemporaryDirectory();
        final tmpFile = File(
            '${directory.path}/tide_img_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tmpFile.writeAsBytes(base64Decode(imageBase64));
        imgPath = tmpFile.path;
      } catch (_) {}
    }
    return sendMessage(
      botId: botId,
      text: text,
      imagePath: imgPath,
      onDelta: onDelta,
      persistResponse: persistResponse,
    );
  }

  Future<String> chat({
    required String botId,
    required List<Map<String, dynamic>> messages,
    String imageBase64 = '',
  }) async {
    final result = await chatResult(
      botId: botId,
      messages: messages,
      imageBase64: imageBase64,
    );
    return result['success'] == true
        ? result['reply']?.toString() ?? ''
        : result['error']?.toString() ?? '';
  }

  /// 主模型失败时自动尝试备用模型，并给予总计两次额外请求机会。
  /// 每次尝试均保持同一聊天上下文；失败信息只在最终结果中返回。
  Future<Map<String, dynamic>> sendMessage({
    required String botId,
    required String text,
    String? imagePath,
    List<String>? imagePaths,
    String? activeGame,
    bool persistResponse = true,
    bool includeChatHistory = true,
    bool enableAutoSummary = true,
    bool skipLifeState = false,
    bool allowTools = true,
    void Function(String delta)? onDelta,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final primaryLocal = _localInferenceEnabled
        ? (prefs.getString('local_chat_model_$botId') ?? '').trim()
        : '';
    final backupLocal = _localInferenceEnabled
        ? (prefs.getString('local_backup_model_$botId') ?? '').trim()
        : '';
    final backupRemote = (prefs.getString('backup_model_$botId') ?? '').trim();
    final matchingBots = (await DBManager().getAllBots())
        .where((bot) => bot['id']?.toString() == botId)
        .toList();
    final primaryRemote = matchingBots.isEmpty
        ? ''
        : (matchingBots.first['chat_model']?.toString().trim() ?? '');
    // 首次严格使用主模型；失败后优先使用备用模型，再给备用模型一次重试。
    // 过去主模型是远程时 provider 被错误置空，导致永远落到列表第一个服务商。
    final primary = {'local': primaryLocal, 'provider': primaryRemote};
    final backup = {'local': backupLocal, 'provider': backupRemote};
    bool configured(Map<String, String> candidate) =>
        candidate['local']!.isNotEmpty || candidate['provider']!.isNotEmpty;
    // Never attempt an empty primary. A configured backup must be usable even
    // when the bot has no primary model selected.
    final attempts = <Map<String, String>>[
      if (configured(primary)) primary,
      if (configured(backup)) backup,
      if (configured(primary) && !configured(backup)) primary,
      if (configured(backup)) backup,
      if (configured(primary) && !configured(backup)) primary,
    ];
    if (attempts.isEmpty) {
      return {'error': '未配置聊天模型，请先在机器人设置中选择聊天或备用模型'};
    }

    Map<String, dynamic>? lastFailure;
    for (var index = 0; index < attempts.length; index++) {
      final candidate = attempts[index];
      final selectedImagePaths = <String>[
        if (imagePath?.isNotEmpty == true) imagePath!,
        ...?imagePaths,
      ];
      final result = await _sendMessageOnce(
        botId: botId,
        text: text,
        imagePath: selectedImagePaths.isEmpty ? null : selectedImagePaths.first,
        imagePaths: selectedImagePaths,
        activeGame: activeGame,
        persistResponse: persistResponse,
        includeChatHistory: includeChatHistory,
        enableAutoSummary: enableAutoSummary,
        skipLifeState: skipLifeState,
        allowTools: allowTools,
        // 不要为了备用重试延迟主请求的 SSE：此前首两次被强制关闭流式，
        // 部分服务商在非流式模式下长期不返回，聊天室最终只看到超时。
        onDelta: onDelta,
        forcedLocalId: candidate['local']!,
        forcedProviderId: candidate['provider']!,
      );
      if (result['success'] == true) return result;
      lastFailure = result;
    }
    return {
      ...?lastFailure,
      'error':
          '主模型和备用模型均请求失败（已自动尝试 ${attempts.length} 次）。${lastFailure?['error'] ?? ''}',
    };
  }

  String _extractChatContent(dynamic payload) {
    if (payload is! Map) return '';
    String fromValue(dynamic value) {
      if (value is String) return value.trim();
      if (value is List) {
        return value
            .map((item) {
              if (item is String) return item;
              if (item is Map)
                return item['text']?.toString() ??
                    item['content']?.toString() ??
                    '';
              return '';
            })
            .where((text) => text.trim().isNotEmpty)
            .join();
      }
      return '';
    }

    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final choice = choices.first as Map;
      final message = choice['message'] ?? choice['delta'];
      if (message is Map) {
        final content = fromValue(message['content']);
        if (content.isNotEmpty) return content;
      }
      final text = fromValue(choice['text']);
      if (text.isNotEmpty) return text;
    }
    final output = payload['output'];
    if (output is Map) {
      final text = fromValue(output['text'] ?? output['output_text']);
      if (text.isNotEmpty) return text;
      final message = output['message'] ?? output['choices']?[0]?['message'];
      if (message is Map) {
        final content = fromValue(message['content']);
        if (content.isNotEmpty) return content;
      }
    }
    final data = payload['data'];
    if (data is Map) {
      final nested = _extractChatContent(data);
      if (nested.isNotEmpty) return nested;
    }
    final direct = fromValue(payload['text'] ?? payload['content']);
    if (direct.isNotEmpty) return direct;
    return fromValue(payload['output_text']);
  }

  Future<Map<String, dynamic>> _sendMessageOnce({
    required String botId,
    required String text,
    String? imagePath,
    List<String> imagePaths = const [],
    String? activeGame,
    bool persistResponse = true,
    bool includeChatHistory = true,
    bool enableAutoSummary = true,
    bool skipLifeState = false,
    bool allowTools = true,
    void Function(String delta)? onDelta,
    String forcedLocalId = '',
    String forcedProviderId = '',
  }) async {
    final db = DBManager();
    // 数据库初始化异常/卡住时必须尽快回到聊天室 finally，不能无限显示“正在输入中”。
    final bots = await db.getAllBots().timeout(const Duration(seconds: 8));

    final bot = bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
    if (bot.isEmpty) return {'error': '系统异常：生命体档案丢失'};

    // 已选择本地 GGUF 时，绕过远程 provider，执行真实 llama.cpp 推理。
    final prefs = await SharedPreferences.getInstance();
    final localId = _localInferenceEnabled
        ? (forcedLocalId.isNotEmpty
            ? forcedLocalId
            : (prefs.getString('local_chat_model_$botId') ?? '').trim())
        : '';
    if (localId.isNotEmpty) {
      try {
        final history = includeChatHistory
            ? await db.getChatHistory(botId).timeout(const Duration(seconds: 8))
            : <Map<String, dynamic>>[];
        final localMessages = <Map<String, dynamic>>[
          {
            'role': 'system',
            'content': _localSystemPrompt(bot),
          },
        ];
        final recentHistory = history
            .where((msg) =>
                msg['type'] == 'text' &&
                msg['error_log']?.toString().isNotEmpty != true &&
                msg['error_code']?.toString().isNotEmpty != true)
            .toList();
        const historyBudget = 350;
        final selectedReversed = <Map<String, dynamic>>[];
        var usedTokens = 0;
        for (final msg in recentHistory.reversed) {
          final content = msg['content']?.toString().trim() ?? '';
          if (content.isEmpty) continue;
          final tokens = estimateTokens(content);
          if (usedTokens + tokens > historyBudget) break;
          selectedReversed.add(msg);
          usedTokens += tokens;
        }
        final selected = selectedReversed.reversed.toList();
        AppLogService.instance.add(
          'CONTEXT',
          '本地模型上下文：历史 ${selected.length}/${recentHistory.length} 条，估算 $usedTokens/$historyBudget token${selected.length < recentHistory.length ? '，已截断较早历史' : ''}',
        );
        for (final msg in selected) {
          final role =
              msg['role']?.toString() == 'assistant' ? 'assistant' : 'user';
          final content = msg['content']?.toString().trim() ?? '';
          if (content.isNotEmpty)
            localMessages.add({'role': role, 'content': content});
        }
        // The current turn is authoritative; skip only an identical final user row.
        if (selected.isEmpty ||
            selected.last['role']?.toString() != 'user' ||
            selected.last['content']?.toString() != text) {
          localMessages.add({'role': 'user', 'content': text});
        }
        final path = await LocalLlama.instance.pathFor(localId);
        final rawReply = await LocalLlama.instance.generate(
          path: path,
          messages: localMessages,
        );
        final localMood = _extractMood(rawReply);
        final reply = _cleanVisibleReply(rawReply);
        final ts = DateTime.now().millisecondsSinceEpoch;
        final messageId = 'msg_a_${ts + 1}';
        if (persistResponse) {
          final segmented =
              await db.getKV('segmented_reply_enabled') != 'false';
          final parts = segmented ? _replySegments(reply) : <String>[reply];
          for (var index = 0; index < parts.length; index++) {
            await db.insertChatMessage({
              'id': index == 0 ? messageId : '${messageId}_segment_$index',
              'bot_id': botId,
              'role': 'assistant',
              'type': 'text',
              'content': parts[index],
              'file_path': null,
              'mood': localMood,
              'timestamp': ts + 1 + index,
            });
          }
        }
        return {
          'success': true,
          'reply': reply,
          'message_id': messageId,
          'local': true,
        };
      } catch (e, st) {
        return {
          'error': '本地模型推理失败：$e',
          'error_code': 'local_inference',
          'error_log': '$e\n$st',
        };
      }
    }

    // 提取该 bot 配置的 provider id（存在 bots.chat_model 字段，由聊天室设置弹窗写入）
    // A newly added provider is usable immediately. Only fill an empty model;
    // never overwrite a deliberate per-bot choice.
    var providerId = forcedProviderId.isNotEmpty
        ? forcedProviderId
        : (bot['chat_model']?.toString().trim() ?? '');
    print(
        '[ai] resolve bot=$botId configured_provider=$providerId local=$localId');
    AppLogService.instance
        .add('AI', '解析机器人 $botId，provider=$providerId，local=$localId');
    if (providerId.isEmpty) {
      final providers = await db.queryChatProviders();
      if (providers.isEmpty) return {'error': '未配置引擎中枢，请先在 API 设置中添加模型'};
      providerId = providers.first['id']?.toString() ?? '';
      if (providerId.isEmpty) return {'error': '模型配置无效，请检查 API 设置'};
      await db.updateBot(botId, {'chat_model': providerId});
    }
    // 优先用统一的聊天链路读取，兼容 API 设置页的 provider_list
    final provider = await db.getChatProviderById(providerId);
    if (provider == null) return {'error': '映射的模型已被删除，请重新配置'};
    print(
        '[ai] provider resolved id=$providerId name=${provider['name']} base=${provider['base_url']}');
    AppLogService.instance.add('AI', '已解析服务商 ${provider['name']}，模型配置将开始请求');
    // 模型名
    // 模型名：优先用 provider['model']（多个逗号分隔取第一个），否则退回 name 最后一段
    String modelName = (provider['model'] as String? ?? '').trim();
    if (modelName.isEmpty) {
      modelName = provider['name'].toString().trim();
    }
    if (modelName.contains(',')) modelName = modelName.split(',').first.trim();
    final maxContext =
        (prefs.getInt('max_token_$botId') ?? bot['max_tokens'] as int? ?? 10000)
            .clamp(1000, 128000);
    final timeAware = (await db.getKV('time_awareness')) != 'false';
    final history = includeChatHistory
        ? await db.getChatHistory(botId).timeout(const Duration(seconds: 8))
        : <Map<String, dynamic>>[];
    // A rollover is semantic, not deletion: once the cumulative transcript reaches
    // the configured context size, ask the configured model to retain only durable
    // events/facts and then keep the newest half as live conversation.
    if (includeChatHistory && enableAutoSummary && localId.isEmpty) {
      await _rolloverContextMemory(
        db: db,
        botId: botId,
        botName: bot['name']?.toString() ?? 'TideBot',
        history: history,
        maxContext: maxContext,
        provider: provider,
        modelName: modelName,
      );
    }

    // Keep stable instructions first for provider prefix caches. Dynamic time is
    // appended last, and history is packed newest-first within the user budget.
    // 稳定记忆放在系统提示的固定位置，动态的中短期记忆限制条数和体积，
    // 避免每轮请求无边界增长，同时尽可能保留服务商前缀缓存命中。
    final longMemoriesRaw = activeGame == null
        ? await db.queryMemories(botId, type: 'long', limit: 12)
        : <Map<String, dynamic>>[];
    final longMemories = longMemoriesRaw;
    final shortMemories = activeGame == null
        ? await db.queryMemories(botId, type: 'short', limit: 8)
        : <Map<String, dynamic>>[];
    String memoryLines(List<Map<String, dynamic>> items, int budget) {
      var used = 0;
      final lines = <String>[];
      for (final item in items) {
        final content = item['content']?.toString().trim() ?? '';
        if (content.isEmpty || used + content.length > budget) continue;
        lines.add('- $content');
        used += content.length;
      }
      return lines.join('\n');
    }

    final longMemoryContext = memoryLines(longMemories, 1200);
    const mediumMemoryContext = '';
    final shortMemoryContext = memoryLines(shortMemories, 600);
    final allowSticker = allowTools ? await _shouldOfferSticker(db) : false;
    final forcedStickerEmotion =
        allowSticker ? await _chooseStickerEmotion(db) : null;
    final toolContext = allowTools
        ? await _buildToolContext(db,
            allowSticker: allowSticker,
            forcedStickerEmotion: forcedStickerEmotion)
        : '';
    final lifeContext = skipLifeState ? '' : await _lifeStateContext(botId);
    final deviceContext =
        await DeviceCapabilityService.instance.contextFor(botId);
    final deviceContextPrompt = deviceContext.isEmpty
        ? ''
        : '\n【经用户逐项授权的设备上下文】${DeviceCapabilityService.instance.encodeContext(deviceContext)}。仅在当前问题直接相关时使用；不得主动逐项复述、推断未授权信息或声称持续监控。';
    final emotionContext =
        await EmotionStateService.instance.promptContext(botId);
    final systemPrompt = _buildSystemPrompt(bot, activeGame) +
        _safetyContext(text) +
        lifeContext +
        deviceContextPrompt +
        emotionContext +
        (longMemoryContext.isEmpty
            ? ''
            : '\n【长期记忆：用户画像与自我身份，仅在相关时参考】\n$longMemoryContext') +
        toolContext +
        (mediumMemoryContext.isEmpty
            ? ''
            : '\n【中期记忆：重要事件，仅在相关时参考】\n$mediumMemoryContext') +
        (shortMemoryContext.isEmpty
            ? ''
            : '\n【短期记忆：近期详细事件，仅在相关时参考】\n$shortMemoryContext');
    // 搜索结果仅由 web_search 工具调用产生，避免关键词猜测和重复请求。
    var searchSources = <Map<String, String>>[];
    Map<String, dynamic>? toolSticker;
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    final historyMessages = <Map<String, dynamic>>[];
    var usedTokens = 0;
    // 给系统提示、记忆、工具定义和本轮输出预留空间，历史不能无上限发送。
    // Keep only the recent half after every context rollover. Older facts
    // are represented by the memory store, avoiding repeated full transcripts.
    final historyBudget = (maxContext / 2).floor().clamp(600, 64000);
    for (final msg in history.reversed) {
      if (msg['type'] != 'text') continue;
      // Failed/unsent messages must never become model context. They may be
      // visible as an error bubble, but are not part of the conversation.
      if (msg['error_log']?.toString().isNotEmpty == true ||
          msg['error_code']?.toString().isNotEmpty == true) {
        continue;
      }
      final content = msg['content']?.toString() ?? '';
      if (content.isEmpty) continue;
      final tokens = estimateTokens(content);
      if (usedTokens + tokens > historyBudget) {
        if (historyMessages.isEmpty) {
          final keepChars =
              (historyBudget * 2.6).floor().clamp(200, content.length);
          historyMessages.add({
            'role':
                msg['role']?.toString() == 'assistant' ? 'assistant' : 'user',
            'content': content.substring(content.length - keepChars),
          });
        }
        break;
      }
      historyMessages.add({
        'role': msg['role']?.toString() == 'assistant' ? 'assistant' : 'user',
        'content': content,
      });
      usedTokens += tokens;
    }
    messages.addAll(historyMessages.reversed);
    final eligibleHistoryCount = history
        .where((msg) =>
            msg['type'] == 'text' &&
            msg['error_log']?.toString().isNotEmpty != true &&
            msg['error_code']?.toString().isNotEmpty != true &&
            (msg['content']?.toString().trim().isNotEmpty ?? false))
        .length;
    AppLogService.instance.add(
      'CONTEXT',
      '远程模型上下文：历史 ${historyMessages.length}/$eligibleHistoryCount 条，估算 $usedTokens/$historyBudget token${historyMessages.length < eligibleHistoryCount ? '，已截断较早历史' : ''}',
    );
    var lastIsCurrentUser = false;
    // 若最末一条上下文恰好就是本次发送的 user 文本（内存补写导致），
    // 标记以免下方再次追加造成重复喂给模型
    if (history.isNotEmpty) {
      final lastMsg = history.last;
      if ((lastMsg['role']?.toString() == 'user') &&
          (lastMsg['content']?.toString() == text)) {
        lastIsCurrentUser = true;
      }
    }
    // Images are described independently so every attachment reaches the model.
    final effectiveImagePaths = imagePaths.isNotEmpty
        ? imagePaths
        : (imagePath?.isNotEmpty == true ? [imagePath!] : const <String>[]);
    if (effectiveImagePaths.isNotEmpty) {
      final mediaDescriptions = <String>[];
      for (var index = 0; index < effectiveImagePaths.length; index++) {
        final path = effectiveImagePaths[index];
        try {
          final prefs = await SharedPreferences.getInstance();
          final visionId =
              (prefs.getString('vision_model_$botId') ?? '').trim();
          final visionProvider =
              visionId.isEmpty ? null : await db.getChatProviderById(visionId);
          final description = visionProvider == null
              ? await MediaPreprocessor().imageFallbackText(path)
              : await _describeImage(
                  provider: visionProvider,
                  imagePath: path,
                  userText: text,
                );
          mediaDescriptions.add('[图片 ${index + 1}] $description');
        } catch (e) {
          mediaDescriptions.add('[图片 ${index + 1} 预处理失败：$e]');
        }
      }
      final contentWithMedia = '$text\n\n${mediaDescriptions.join('\n\n')}';
      if (lastIsCurrentUser && messages.isNotEmpty) {
        // 当前用户消息已从数据库进入上下文时，替换其内容而非重复追加。
        messages[messages.length - 1] = {
          'role': 'user',
          'content': contentWithMedia,
        };
      } else {
        messages.add({
          'role': 'user',
          'content': contentWithMedia,
        });
      }
    } else if (!lastIsCurrentUser) {
      messages.add({'role': 'user', 'content': text});
    }
    if (timeAware) {
      final now = DateTime.now();
      DateTime? firstAt;
      DateTime? lastAt;
      for (final item in history) {
        final stamp = int.tryParse(item['timestamp']?.toString() ?? '');
        if (stamp == null) continue;
        firstAt ??= DateTime.fromMillisecondsSinceEpoch(stamp);
        lastAt = DateTime.fromMillisecondsSinceEpoch(stamp);
      }
      final span = firstAt == null || lastAt == null
          ? ''
          : '当前所附历史覆盖约 ${lastAt.difference(firstAt).inMinutes.abs()} 分钟；最后一条历史距现在约 ${now.difference(lastAt).inMinutes.abs()} 分钟。';
      messages.add({
        'role': 'system',
        'content':
            '时间上下文（内部元数据，不得引用、复述或模仿其格式）：当前本地时间 ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}。$span仅在确有时间相关性时据此理解时间流逝。',
      });
    }
    try {
      final baseUrl = provider['base_url']
              ?.toString()
              .trim()
              .replaceFirst(RegExp(r'/+$'), '') ??
          '';
      if (baseUrl.isEmpty) return {'error': '模型提供商缺少 Base URL，请在 API 设置中补充'};
      print(
          '[ai] request bot=$botId provider=$providerId model=$modelName url=$baseUrl/chat/completions');
      AppLogService.instance.add('AI',
          '请求 $modelName（tools=${allowTools ? 'on' : 'off'}，stream=${onDelta != null ? 'on' : 'off'}）');
      final tools = allowTools
          ? await _buildNativeTools(db, botId: botId, allowSticker: false)
          : const <Map<String, dynamic>>[];
      // Native tools remain enabled for every normal chat request. Provider
      // compatibility is handled by retrying the exact same turn without only
      // the unsupported tool fields after an explicit provider rejection.
      final toolCallingEnabled = allowTools && tools.isNotEmpty;
      final payload = <String, dynamic>{
        'model': modelName,
        'messages': messages,
        'max_tokens': maxContext,
        if (toolCallingEnabled && tools.isNotEmpty) 'tools': tools,
        if (toolCallingEnabled && tools.isNotEmpty) 'tool_choice': 'auto',
        // Replies are always collected in full before visible rendering. The chat
        // room owns the typewriter animation after filtering and persistence.
        // Keeping this transport non-streaming prevents raw protocol fragments
        // from entering a bubble before _cleanVisibleReply() has run.
      };
      AppLogService.instance.addJson('REQUEST', '发往模型提供商的完整请求（已脱敏）', {
        'url': '$baseUrl/chat/completions',
        'requested_at': DateTime.now().toIso8601String(),
        'payload': payload,
      });
      String replyText = '';
      String? generatedImagePath;
      var toolSilenced = false;
      Map<String, dynamic>? pendingDeviceAction;
      Map usage = const {};
      String errorBody = '';
      int statusCode;
      final response = await http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${provider['api_key']}',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 40));
      statusCode = response.statusCode;
      errorBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (statusCode == 200) {
        final json = jsonDecode(errorBody);
        final message = json['choices']?[0]?['message'];
        replyText = _extractChatContent(json);
        usage = json['usage'] is Map ? json['usage'] as Map : const {};
        AppLogService.instance.addJson('RESPONSE_DEBUG', 'HTTP 200 解析诊断', {
          'keys':
              json is Map ? json.keys.map((e) => e.toString()).toList() : [],
          'finish_reason': json['choices']?[0]?['finish_reason'],
          'message_keys': message is Map
              ? message.keys.map((e) => e.toString()).toList()
              : [],
          'has_reasoning_content': message is Map &&
              (message['reasoning_content'] ?? message['reasoning']) != null,
          'has_tool_calls': message is Map && message['tool_calls'] is List,
          'parsed_length': replyText.length,
        });
        if (message is Map && message['tool_calls'] is List) {
          final toolCalls = (message['tool_calls'] as List)
              .whereType<Map>()
              .map((call) => Map<String, dynamic>.from(call))
              .toList();
          if (toolCalls.isNotEmpty) {
            messages.add({
              'role': 'assistant',
              'content': replyText,
              'tool_calls': toolCalls,
            });
            await _runStreamedTools(
                db: db,
                botId: botId,
                calls: toolCalls,
                messages: messages,
                baseUrl: baseUrl,
                modelName: modelName,
                apiKey: provider['api_key']?.toString() ?? '',
                maxTokens: bot['max_tokens'] ?? 10000,
                onDelta: null,
                replyTextCallback: (t) => replyText = t,
                usageCallback: (u) => usage = u,
                searchSourcesSetter: (l) => searchSources = l,
                generatedImageSetter: (p) => generatedImagePath = p,
                stickerSetter: (p) => toolSticker = p,
                pendingDeviceActionSetter: (p) => pendingDeviceAction = p,
                silenceSetter: () => toolSilenced = true);
          }
        }
      }
      if (toolSilenced) replyText = '';
      print('[ai] response status=$statusCode');
      AppLogService.instance.add('AI', '服务商响应 HTTP $statusCode');
      AppLogService.instance.add('RESPONSE',
          '模型提供商响应（HTTP $statusCode）\n${errorBody.isEmpty ? replyText : errorBody}');
      if (statusCode == 200) {
        // 优先采用 API 返回的真实 usage；缺失时用标准化算法估算（不再用 字符数/3.2）。
        final promptText = messages.fold<String>(
            '', (sum, m) => sum + (m['content']?.toString() ?? ''));
        final promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ??
            estimateTokens(promptText);
        final completionTokens =
            (usage['completion_tokens'] as num?)?.toInt() ??
                estimateTokens(replyText);
        final totalTokens = (usage['total_tokens'] as num?)?.toInt() ??
            promptTokens + completionTokens;
        await db.recordAiUsage(
          botId: botId,
          eventType: 'chat',
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: totalTokens,
        );
        // 日记仅能由模型明确调用 write_diary 工具写入；不再后台猜测或自动归档聊天。

        // 适时沉默是模型主动调用的原生工具，不是文本标记过滤。
        // 成功静默不产生气泡、贴纸、语音或空 assistant 历史记录。
        if (toolSilenced) {
          AppLogService.instance.add('SILENCE', '机器人通过工具选择本轮不回复');
          return {'success': true, 'silent': true, 'reply': ''};
        }
        // 情绪、时间、工具与游戏标记均是内部协议，绝不能进入用户可见文本。
        String mood = _extractMood(replyText);
        // 先抽取模型主动要求记住的信息，再剥离可见文本，避免把它们留在气泡里。
        await _persistModelMemories(db, bot['name']?.toString() ?? 'TideBot',
            bot['id']?.toString() ?? botId, replyText);
        replyText = _cleanVisibleReply(replyText);
        if (replyText.isEmpty) {
          const detail = 'HTTP 200，但未解析到可见正文；请查看 RESPONSE_DEBUG 日志';
          AppLogService.instance.add('RESPONSE_DEBUG', detail);
          return {
            'error': detail,
            'error_log': 'HTTP 200\n$detail\n原始响应：$errorBody',
            'error_code': 'empty_response',
          };
        }

        // 工具调用可能已返回图片路径，先初始化供下方落库使用.
        // 语音模态处理：TTS 生成改为后台执行，绝不阻塞文本回复，
        // 否则 TTS 请求最长 20 秒会卡死整个发送链路，导致"发送没反应/无气泡"。
        final ts = DateTime.now().millisecondsSinceEpoch;
        final msgId = 'msg_a_${ts + 1}';
        // Sticker probability is decided by TideBot, not by a model tool. Once the
        // roll hits, one category is selected up front and one asset is sampled
        // from that category after the complete reply has been processed.
        Map<String, dynamic>? sticker = toolSticker;
        if (sticker == null && forcedStickerEmotion != null) {
          final candidates =
              await db.queryStickers(emotion: forcedStickerEmotion);
          if (candidates.isNotEmpty) {
            sticker = Map<String, dynamic>.from(
                candidates[Random.secure().nextInt(candidates.length)]);
          }
        }
        if (persistResponse) {
          // Streaming uses one persisted row as well as one foreground bubble.
          // Sentence splitting remains available for non-streaming replies.
          final segmented = onDelta == null &&
              await db.getKV('segmented_reply_enabled') != 'false';
          final segments =
              segmented ? _replySegments(replyText) : <String>[replyText];
          for (var index = 0; index < segments.length; index++) {
            await db.insertChatMessage({
              'id': index == 0 ? msgId : '${msgId}_segment_$index',
              'bot_id': botId,
              'role': 'assistant',
              'type': 'text',
              'content': segments[index],
              'file_path': null,
              'mood': mood,
              'sources_json':
                  searchSources.isEmpty ? null : jsonEncode(searchSources),
              'timestamp': ts + 1 + index,
            });
          }
          // 聊天请求可能在等待模型期间进入后台。仅在用户已开启通知且
          // 应用不在前台时提醒；前台聊天由 UI 气泡承载，不重复打扰。
          try {
            final notifyEnabled =
                (await db.getKV('unread_notifications')) != 'false';
            if (notifyEnabled && !AppState.isForeground.value) {
              final title = bot['name']?.toString().trim().isNotEmpty == true
                  ? bot['name'].toString()
                  : 'TideBot';
              await OpsManager().showSystemNotification(
                id: ts.remainder(1 << 31),
                title: title,
                body: replyText.isEmpty ? '收到一条新消息' : replyText,
                botId: botId,
              );
            }
          } catch (_) {
            // 通知权限或厂商系统限制不应影响已成功落库的聊天回复。
          }

          if (generatedImagePath != null) {
            await db.insertChatMessage({
              'id': 'msg_i_${ts + 2}',
              'bot_id': botId,
              'role': 'assistant',
              'type': 'image',
              'content': '',
              'file_path': generatedImagePath,
              'mood': mood,
              'timestamp': ts + 2,
            });
          }

          if (sticker != null) {
            await db.insertChatMessage({
              'id': 'msg_s_${ts + 2 + segments.length}',
              'bot_id': botId,
              'role': 'assistant',
              'type': 'sticker',
              // emotion 是素材匹配元数据，不保存为可见聊天正文。
              'content': '',
              'file_path': sticker['file_path']?.toString(),
              'mood': mood,
              'timestamp': ts + 2 + segments.length,
            });
          }

          final ttsModel = bot['tts_model'];
          final voiceEnabled = await db.getKV('voice_reply_enabled') == 'true';
          final voiceChance =
              (int.tryParse(await db.getKV('voice_reply_chance') ?? '') ?? 50)
                  .clamp(1, 100);
          final voiceRoll = Random().nextInt(100);
          if (!voiceEnabled) {
            AppLogService.instance.add('TTS', '本轮未请求：语音回复开关关闭');
          } else if (ttsModel == null || ttsModel.toString().isEmpty) {
            AppLogService.instance.add('TTS', '本轮未请求：机器人未绑定 TTS 模型');
          } else if (voiceRoll >= voiceChance) {
            AppLogService.instance.add(
                'TTS', '本轮未请求：语音概率未命中（${voiceRoll + 1}/100，设定 $voiceChance%）');
          }
          if (voiceEnabled &&
              ttsModel != null &&
              ttsModel.toString().isNotEmpty &&
              voiceRoll < voiceChance) {
            AppLogService.instance.add('TTS',
                '准备请求语音模型：${ttsModel.toString()}，文本 ${replyText.length} 字');
            // TTS failures intentionally keep the original text message unchanged.
            unawaited(() async {
              final audioPath =
                  await _generateTTS(replyText, ttsModel.toString());
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
                    'sources_json': searchSources.isEmpty
                        ? null
                        : jsonEncode(searchSources),
                    'timestamp': ts + 1,
                  });
                } catch (_) {}
              }
            }());
          }
        }
        return {
          'success': true,
          'reply': replyText,
          'message_id': msgId,
          if (searchSources.isNotEmpty) 'sources': searchSources,
          if (generatedImagePath != null) 'image_path': generatedImagePath,
          if (sticker != null) 'sticker': sticker,
          if (pendingDeviceAction != null)
            'pending_device_action': pendingDeviceAction,
        };
      } else {
        final detail = errorBody.replaceAll(RegExp(r'\s+'), ' ').trim();
        print(
            '[ai] response error=${detail.length > 300 ? detail.substring(0, 300) : detail}');
        return {
          'error': _friendlyHttpError(statusCode, detail),
          'error_log': 'HTTP $statusCode\n$detail',
          'error_code': statusCode,
        };
      }
    } catch (e) {
      print('[ai] request failed: $e');
      AppLogService.instance.add('ERROR', '模型请求异常：$e');
      return {
        'error': '网络连接失败：请检查网络、Base URL 和服务端状态',
        'error_log': e.toString(),
        'error_code': 'network',
      };
    }
  }

  List<String> _replySegments(String content) {
    final parts = RegExp(r'.*?[。？！~…]+|.+$', multiLine: true)
        .allMatches(content)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? <String>[content] : parts;
  }

  String _cleanVisibleReply(String raw) {
    // Some providers leak internal labels into normal text. Remove whole
    // protocol lines before rendering so content such as ":平静]" or
    // "记忆:..." never becomes a chat bubble.
    final withoutProtocolLines = raw
        .replaceAll(
            RegExp(
                r'^\s*\[心情\s*[:：]\s*(?:平静|开心|伤心|生气|害羞|兴奋)\s*\]\s*(?:\r?\n|$)',
                multiLine: true),
            '')
        .replaceAll(
            RegExp(r'^\s*\]?\s*(?:心情|mood)\s*[:：][^\n]*$',
                multiLine: true, caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'^\s*\]?\s*(?:记忆|memory)\s*[:：][^\n]*$',
                multiLine: true, caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'^\s*[:：]\s*(?:平静|开心|伤心|生气|害羞|兴奋)\s*\]?\s*$',
                multiLine: true),
            '');
    // 部分模型以 DSML/XML 文本模拟工具调用；这是内部协议，绝不能进入消息气泡。
    final withoutDsml = withoutProtocolLines
        .replaceAll(
            RegExp(
                r'<\|?\s*DSML\s*\|?\s*tool_calls\s*>[\s\S]*?<\s*/\|?\s*DSML\s*\|?\s*tool_calls\s*>',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'<\|?\s*DSML\s*\|?\s*invoke[\s\S]*?<\s*/\|?\s*DSML\s*\|?\s*invoke\s*>',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'<\|?\s*DSML\s*\|?[^>]*>[\s\S]*?<\s*/\|?\s*DSML\s*\|?[^>]*>',
                caseSensitive: false),
            '');
    final normalized = withoutDsml
        // Inline protocol suffixes can be emitted after otherwise valid text,
        // e.g. "晚安。:平静]记忆:...". Strip them before line-oriented rules.
        .replaceAll(
            RegExp(r'\s*[:：]\s*(?:平静|开心|伤心|生气|害羞|兴奋)\s*\]?',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\s*(?:\[?记忆\]?|memory)\s*[:：][\s\S]*$',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\[心情\s*[:：]\s*[^\]]*\]'), '')
        .replaceAll(RegExp(r'\[发送时间\s*：[^\]]*\]'), '')
        .replaceAll(RegExp(r'\[发送于\s+[^\]]*\]'), '')
        .replaceAll(RegExp(r'\[现实时间(?:附注)?\s*：[^\]]*\]'), '')
        .replaceAll(
            RegExp(
                r'\[(?:工具|贴纸|表情包|表情|记忆|类型|sticker_type|sticker-type)\s*[:：][^\]]*\]'),
            '')
        .replaceAll(RegExp(r'\[(?:心情|发送时间|现实时间附注)\s*[：:]\s*[^\]]*\]'), '')
        .replaceAll(RegExp(r'\[落子\s*[:：]\s*\d+\s*,\s*\d+\]'), '')
        // Never expose sticker / tool / protocol labels that the model may leak
        // as ordinary text lines (regardless of the value after the colon).
        .replaceAll(
            RegExp(
                r'^\s*(?:(?:type|类型|表情包类型|表情类型|贴纸类型|sticker(?:[_ -]?type)?|工具|贴纸|表情包|表情|心情|发送时间|现实时间|规则|系统)\s*[=:：]\s*).*$',
                multiLine: true,
                caseSensitive: false),
            '')
        // Also strip bare protocol tokens that appear on their own line.
        .replaceAll(
            RegExp(r'^\s*(?:sticker|emoji|表情包|静态表情|动图|贴纸)\s*$',
                multiLine: true, caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return normalized;
  }

  String _friendlyHttpError(int status, String detail) {
    final suffix = detail.isEmpty ? '' : '（服务端信息：$detail）';
    if (status == 402) {
      return '服务余额不足：请充值或更换有余额的 API Key。$suffix';
    }
    if (status == 401 || status == 403) {
      return '鉴权失败：请检查 API Key、权限和 Base URL。$suffix';
    }
    if (status == 404) {
      return '接口或模型不存在：请检查 Base URL 与模型名称。$suffix';
    }
    if (status == 408 || status == 429) {
      return '服务繁忙、超时或触发限流：请稍后重试。$suffix';
    }
    if (status >= 500) {
      return '模型服务端异常：请稍后重试或更换服务商。$suffix';
    }
    return '模型请求失败（HTTP $status）。$suffix';
  }

  Future<String> describeImagesForBot({
    required String botId,
    required List<String> imagePaths,
    String userText = '',
  }) async {
    if (imagePaths.isEmpty) return '[未提取到可用视频帧]';
    final prefs = await SharedPreferences.getInstance();
    final visionId = (prefs.getString('vision_model_$botId') ?? '').trim();
    final provider = visionId.isEmpty
        ? null
        : await DBManager().getChatProviderById(visionId);
    final descriptions = <String>[];
    for (var i = 0; i < imagePaths.length; i++) {
      final path = imagePaths[i];
      final detail = provider == null
          ? await MediaPreprocessor().imageFallbackText(path)
          : await _describeImage(
              provider: provider,
              imagePath: path,
              userText: '$userText（视频第 ${i + 1} 帧）',
            );
      descriptions.add('第 ${i + 1} 帧：$detail');
    }
    return '[视频画面分析]\\n${descriptions.join('\\n\\n')}';
  }

  Future<String> _describeImage({
    required Map<String, dynamic> provider,
    required String imagePath,
    required String userText,
  }) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final baseUrl = provider['base_url']
              ?.toString()
              .trim()
              .replaceFirst(RegExp(r'/+$'), '') ??
          '';
      var model = provider['model']?.toString().trim() ?? '';
      if (model.contains(',')) model = model.split(',').first.trim();
      if (baseUrl.isEmpty || model.isEmpty) {
        return await MediaPreprocessor().imageFallbackText(imagePath);
      }
      final response = await http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${provider['api_key']}',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      '你是严谨的视觉分析器。请详细、客观地转述图片：先概述整体场景，再按位置说明人物/物体、动作、颜色、布局、可读文字（逐字抄录时标注不确定处）、界面元素和可能与用户问题相关的细节。看不清或无法确认必须明确说明，绝不依据常识补全或编造。输出供聊天模型使用的完整中文描述。',
                },
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'text',
                      'text': userText.isEmpty ? '请转述这张图片。' : userText,
                    },
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/jpeg;base64,${base64Encode(bytes)}',
                      },
                    },
                  ],
                },
              ],
              'max_tokens': 1200,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final text =
            decoded['choices']?[0]?['message']?['content']?.toString().trim();
        if (text != null && text.isNotEmpty) {
          return '[视觉模型转述]\\n$text';
        }
      }
    } catch (e) {
      print('[vision] description failed: $e');
    }
    return await MediaPreprocessor().imageFallbackText(imagePath);
  }

  Future<void> _rolloverContextMemory({
    required DBManager db,
    required String botId,
    required String botName,
    required List<Map<String, dynamic>> history,
    required int maxContext,
    required Map<String, dynamic> provider,
    required String modelName,
  }) async {
    try {
      final boundary =
          int.tryParse(await db.getKV('context_rollover_at_$botId') ?? '') ?? 0;
      final pending = history
          .where((m) =>
              ((m['timestamp'] as num?)?.toInt() ?? 0) > boundary &&
              m['type'] == 'text')
          .toList();
      final tokens = pending.fold<int>(
          0, (n, m) => n + estimateTokens(m['content']?.toString() ?? ''));
      if (tokens < maxContext) return;
      final keepBudget = (maxContext / 2).floor();
      var used = 0;
      final recent = <Map<String, dynamic>>[];
      for (final message in pending.reversed) {
        final size = estimateTokens(message['content']?.toString() ?? '');
        if (used + size > keepBudget) break;
        used += size;
        recent.add(message);
      }
      final recentIds = recent.map((m) => m['id']?.toString()).toSet();
      final archived = pending
          .where((m) => !recentIds.contains(m['id']?.toString()))
          .toList();
      if (archived.isEmpty) return;
      final transcript = archived
          .map((m) =>
              '${m['role'] == 'assistant' ? '机器人' : '用户'}：${m['content']}')
          .join('\n');
      final url = (provider['base_url']?.toString() ?? '')
          .replaceFirst(RegExp(r'/+$'), '');
      final key = provider['api_key']?.toString() ?? '';
      if (url.isEmpty || key.isEmpty) return;
      final prompt =
          '''你是聊天记忆整理器。仅从以下已发生对话提炼未来有用的稳定事实或重要事件；不要猜测，不要复述普通闲聊。已有记忆可能会自动去重/修正。每项严格输出一行：[记忆:长期|事实] 或 [记忆:短期|事件]。没有值得记住的内容就输出 NONE。

$transcript''';
      final response = await http
          .post(Uri.parse('$url/chat/completions'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $key'
              },
              body: jsonEncode({
                'model': modelName,
                'messages': [
                  {'role': 'system', 'content': '准确、克制地整理记忆，不与用户对话。'},
                  {'role': 'user', 'content': prompt}
                ],
                'temperature': 0.1,
                'max_tokens': 1200
              }))
          .timeout(const Duration(seconds: 45));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final raw =
          _extractChatContent(jsonDecode(utf8.decode(response.bodyBytes)));
      if (raw.isNotEmpty && raw != 'NONE')
        await _persistModelMemories(db, botName, botId, raw);
      final newestArchived = archived.last['timestamp'] as num?;
      if (newestArchived != null)
        await db.setKV(
            'context_rollover_at_$botId', '${newestArchived.toInt()}');
      AppLogService.instance.add('MEMORY',
          '上下文达到 $maxContext token，已整理 ${archived.length} 条历史并保留最近约 $keepBudget token');
    } catch (e) {
      AppLogService.instance.add('MEMORY', '上下文记忆整理跳过：$e');
    }
  }

  /// Transcribe with the STT provider selected for this bot.
  ///
  /// MiMo audio models use the OpenAI-compatible chat-completions endpoint.
  /// The API requires exactly one `input_audio` content part; `audio_url` is an
  /// image-style field and is rejected by MiMo ASR.
  Future<String?> transcribeAudio({
    required String botId,
    required String audioPath,
  }) async {
    final db = DBManager();
    final prefs = await SharedPreferences.getInstance();
    final bot = await db.getBotById(botId);
    final providerId = (prefs.getString('stt_model_$botId') ??
            bot?['stt_model']?.toString() ??
            '')
        .trim();
    if (providerId.isEmpty) {
      AppLogService.instance.add('STT', '未为当前机器人选择 STT 服务');
      return null;
    }
    final provider = await db.getSttProviderById(providerId);
    if (provider == null) {
      AppLogService.instance.add('STT', '未找到 STT 服务配置：$providerId');
      return null;
    }
    return transcribeWithProvider(provider, audioPath);
  }

  Future<String?> transcribeWithProvider(
      Map<String, dynamic> provider, String audioPath) async {
    try {
      final audio = File(audioPath);
      if (!await audio.exists()) {
        AppLogService.instance.add('STT', '语音文件不存在');
        return null;
      }
      final baseUrl = (provider['base_url'] ?? provider['url'] ?? '')
          .toString()
          .trim()
          .replaceFirst(RegExp(r'/+$'), '');
      final model = provider['model']?.toString().split(',').first.trim() ?? '';
      final apiKey =
          (provider['api_key'] ?? provider['key'] ?? '').toString().trim();
      final protocol =
          (provider['protocol']?.toString() ?? 'openai').trim().toLowerCase();
      if (baseUrl.isEmpty || model.isEmpty || apiKey.isEmpty) {
        AppLogService.instance.add('STT', '语音转文字失败：缺少地址、Key 或模型');
        return null;
      }
      if (protocol == 'mimo') {
        return _transcribeMiMo(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          audio: audio,
          providerName: provider['name']?.toString() ?? 'MiMo STT',
        );
      }
      if (protocol != 'openai') {
        AppLogService.instance.add('STT', '不支持的 STT 协议：$protocol');
        return null;
      }
      final endpoint = _sttTranscriptionEndpoint(baseUrl);
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields['model'] = model
        ..fields['response_format'] = 'json'
        ..files.add(await http.MultipartFile.fromPath('file', audioPath));
      final response = await http.Response.fromStream(
          await request.send().timeout(const Duration(seconds: 45)));
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogService.instance.add('STT',
            '语音转文字失败：HTTP ${response.statusCode} ${body.substring(0, body.length.clamp(0, 500))}');
        return null;
      }
      final decoded = jsonDecode(body);
      final transcript =
          decoded is Map ? decoded['text']?.toString().trim() : '';
      return transcript?.isEmpty == true ? null : transcript;
    } catch (e) {
      AppLogService.instance.add('STT', '语音转文字异常：$e');
      return null;
    }
  }

  Future<String> createSttProbeAudio() async {
    // A tiny valid PCM WAV containing 120 ms of silence.  It keeps the test a
    // real STT request without prompting the user to pick or record a file.
    const sampleRate = 8000;
    const samples = 960;
    const dataBytes = samples * 2;
    final bytes = BytesBuilder()
      ..add('RIFF'.codeUnits)
      ..add(_le32(36 + dataBytes))
      ..add('WAVEfmt '.codeUnits)
      ..add(_le32(16))
      ..add(_le16(1))
      ..add(_le16(1))
      ..add(_le32(sampleRate))
      ..add(_le32(sampleRate * 2))
      ..add(_le16(2))
      ..add(_le16(16))
      ..add('data'.codeUnits)
      ..add(_le32(dataBytes))
      ..add(List<int>.filled(dataBytes, 0));
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/tidebot_stt_probe.wav');
    await file.writeAsBytes(bytes.toBytes(), flush: true);
    return file.path;
  }

  List<int> _le16(int value) => [value & 0xff, (value >> 8) & 0xff];
  List<int> _le32(int value) => [
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ];

  Future<String?> _transcribeMiMo({
    required String baseUrl,
    required String apiKey,
    required String model,
    required File audio,
    required String providerName,
  }) async {
    final endpoint = _chatCompletionsEndpoint(baseUrl);
    final bytes = await audio.readAsBytes();
    final extension = audio.path.split('.').last.toLowerCase();
    final payload = {
      'model': model,
      'stream': false,
      'messages': [
        {
          'role': 'system',
          'content': '你是语音转文字引擎。只输出音频中的原始文字，不要解释、标题、标点说明或心情标签。'
        },
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '请将这段音频准确转写为文字。'},
            {
              'type': 'input_audio',
              'input_audio': {
                'data': base64Encode(bytes),
                'format': extension == 'wave' ? 'wav' : extension,
              }
            },
          ]
        }
      ]
    };
    AppLogService.instance.add('STT',
        '请求 MiMo 语音转文字：provider=$providerName，model=$model，endpoint=$endpoint，${bytes.length} bytes');
    final response = await http
        .post(Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 60));
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AppLogService.instance.add('STT',
          'MiMo 语音转文字失败：HTTP ${response.statusCode} ${body.substring(0, body.length.clamp(0, 800))}');
      return null;
    }
    final decoded = jsonDecode(body);
    final transcript = _extractChatContent(decoded).trim();
    if (transcript.isEmpty) {
      AppLogService.instance.add('STT',
          'MiMo 语音转文字返回为空：${body.substring(0, body.length.clamp(0, 500))}');
      return null;
    }
    return transcript;
  }

  String _sttTranscriptionEndpoint(String configuredUrl) {
    final root = configuredUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (root.endsWith('/audio/transcriptions')) return root;
    if (root.endsWith('/v1')) return '$root/audio/transcriptions';
    return '$root/v1/audio/transcriptions';
  }

  String _chatCompletionsEndpoint(String configuredUrl) {
    final root = configuredUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (root.endsWith('/chat/completions')) return root;
    if (root.endsWith('/v1')) return '$root/chat/completions';
    return '$root/v1/chat/completions';
  }

  String _miniMaxTtsEndpoint(String configuredUrl) {
    final root = configuredUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (root.endsWith('/t2a_v2')) return root;
    if (root.endsWith('/v1')) return '$root/t2a_v2';
    return '$root/v1/t2a_v2';
  }

  // TTS supports both legacy base_url/api_key and settings-page url/key fields.
  Future<String?> _generateTTS(String text, String providerId) async {
    final list = await DBManager().queryTtsProviders();
    Map<String, dynamic>? provider;
    try {
      provider = list.firstWhere((p) => p['id'] == providerId);
    } catch (_) {}
    if (provider == null) return null;

    final baseUrl = (provider['base_url'] ?? provider['url'] ?? '')
        .toString()
        .trim()
        .replaceFirst(RegExp(r'/+$'), '');
    final apiKey =
        (provider['api_key'] ?? provider['key'] ?? '').toString().trim();
    final protocol =
        (provider['protocol']?.toString() ?? 'openai').trim().toLowerCase();
    final configuredVoice = (provider['voice']?.toString() ?? '').trim();
    final voice = configuredVoice.isEmpty || configuredVoice == 'default'
        ? (protocol == 'mimo' ? 'mimo_default' : 'alloy')
        : configuredVoice;
    final modelName = (provider['model']?.toString() ?? '').trim();
    final model = modelName.isEmpty
        ? (provider['name']?.toString() ?? 'tts-1')
        : modelName;
    if (protocol == 'unsupported') {
      AppLogService.instance.add('TTS', '该 TTS 服务暂未提供可验证的调用协议');
      return null;
    }
    if (baseUrl.isEmpty || apiKey.isEmpty || text.trim().isEmpty) {
      AppLogService.instance.add('TTS', '语音合成失败：缺少地址、Key 或文本');
      return null;
    }

    try {
      final endpoint = switch (protocol) {
        'minimax' => _miniMaxTtsEndpoint(baseUrl),
        'mimo' => _chatCompletionsEndpoint(baseUrl),
        _ => '$baseUrl/audio/speech',
      };
      final payload = switch (protocol) {
        'minimax' => {
            'model': model,
            'text': text,
            'stream': false,
            'voice_setting': {
              'voice_id': voice,
              'speed': 1.0,
              'vol': 1.0,
              'pitch': 0,
            },
            'audio_setting': {
              'sample_rate': 32000,
              'bitrate': 128000,
              'format': 'mp3',
              'channel': 1,
            },
          },
        'mimo' => {
            'model': model,
            'stream': false,
            'messages': [
              {'role': 'user', 'content': text}
            ],
            'modalities': ['text', 'audio'],
            'audio': {
              'voice': voice,
              'format': 'wav',
            },
          },
        _ => {'model': model, 'input': text, 'voice': voice},
      };
      AppLogService.instance.add('TTS',
          '请求语音：provider=${provider['name'] ?? providerId}，protocol=$protocol，model=$model，endpoint=$endpoint，文本 ${text.length} 字');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };
      final res = await http
          .post(
            Uri.parse(endpoint),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
      AppLogService.instance.add('TTS',
          '语音服务响应 HTTP ${res.statusCode}，content-type=${res.headers['content-type'] ?? 'unknown'}');
      if (res.statusCode < 200 ||
          res.statusCode >= 300 ||
          res.bodyBytes.isEmpty) {
        AppLogService.instance.add('TTS', '语音合成失败：HTTP ${res.statusCode}');
        return null;
      }

      var bytes = res.bodyBytes;
      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      if (contentType.contains('json') ||
          utf8.decode(bytes, allowMalformed: true).trimLeft().startsWith('{')) {
        AppLogService.instance.addJson('TTS', '语音服务 JSON 响应', {
          'status': res.statusCode,
          'body': utf8.decode(bytes, allowMalformed: true),
        });
        final raw = jsonDecode(utf8.decode(bytes));
        if (raw is Map &&
            (raw['base_resp'] is Map) &&
            ((raw['base_resp'] as Map)['status_code'] as num?) != 0) {
          AppLogService.instance.add(
            'TTS',
            '语音服务返回错误：${(raw['base_resp'] as Map)['status_msg'] ?? raw['base_resp']}',
          );
          return null;
        }
        String? audioUrl;
        if (raw is Map) {
          final output = raw['output'];
          final data = raw['data'];
          final choices = raw['choices'];
          final message =
              choices is List && choices.isNotEmpty && choices.first is Map
                  ? (choices.first as Map)['message']
                  : null;
          final messageAudio = message is Map ? message['audio'] : null;
          final outputAudio = output is Map ? output['audio'] : null;
          final dataAudio = data is Map ? data['audio'] : null;
          audioUrl = raw['audio_url']?.toString() ??
              raw['url']?.toString() ??
              (messageAudio is Map
                  ? (messageAudio['url'] ?? messageAudio['audio_url'])
                      ?.toString()
                  : null) ??
              (outputAudio is Map
                  ? (outputAudio['url'] ?? outputAudio['audio_url'])?.toString()
                  : null) ??
              (dataAudio is Map
                  ? (dataAudio['url'] ?? dataAudio['audio_url'])?.toString()
                  : null) ??
              (output is Map
                  ? (output['audio_url'] ?? output['url'])?.toString()
                  : null) ??
              (data is Map
                  ? (data['audio_url'] ?? data['url'])?.toString()
                  : null);
          final inlineAudio = _inlineAudioFromTtsResponse(raw);
          if (inlineAudio != null && inlineAudio.isNotEmpty) {
            try {
              final compact = inlineAudio.replaceAll(RegExp(r'\s+'), '');
              bytes = RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact) &&
                      compact.length.isEven
                  ? Uint8List.fromList(List<int>.generate(
                      compact.length ~/ 2,
                      (index) => int.parse(
                          compact.substring(index * 2, index * 2 + 2),
                          radix: 16)))
                  : base64Decode(compact);
            } catch (_) {
              AppLogService.instance.add('TTS', '语音服务返回的内嵌音频无法解码');
              return null;
            }
          }
          if (audioUrl != null && audioUrl.isNotEmpty) {
            final audioResponse = await http
                .get(Uri.parse(audioUrl))
                .timeout(const Duration(seconds: 30));
            if (audioResponse.statusCode < 200 ||
                audioResponse.statusCode >= 300 ||
                audioResponse.bodyBytes.isEmpty) {
              AppLogService.instance
                  .add('TTS', '语音文件下载失败：HTTP ${audioResponse.statusCode}');
              return null;
            }
            bytes = audioResponse.bodyBytes;
          } else if (inlineAudio == null || inlineAudio.isEmpty) {
            AppLogService.instance.add('TTS', '语音合成返回 JSON，但没有可用音频');
            return null;
          }
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final extension = _audioExtension(bytes, contentType);
      final path =
          '${directory.path}/tide_tts_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await File(path).writeAsBytes(bytes);
      AppLogService.instance.add(
          'TTS', '语音合成成功：${text.length} 字，${bytes.length} bytes，已保存 $path');
      return path;
    } catch (e) {
      AppLogService.instance.add('TTS', '语音合成异常：$e');
      return null;
    }
  }

  String? _inlineAudioFromTtsResponse(dynamic raw) {
    if (raw is! Map) return null;
    String? readAudio(dynamic value) {
      if (value is! Map) return null;
      return (value['hex'] ?? value['audio_hex'] ?? value['data'])?.toString();
    }

    final output = raw['output'];
    final data = raw['data'];
    final choices = raw['choices'];
    final message =
        choices is List && choices.isNotEmpty && choices.first is Map
            ? (choices.first as Map)['message']
            : null;
    return readAudio(raw['audio']) ??
        readAudio(output is Map ? output['audio'] : null) ??
        readAudio(data is Map ? data['audio'] : null) ??
        readAudio(message is Map ? message['audio'] : null) ??
        (message is Map ? message['audio_data']?.toString() : null);
  }

  String _audioExtension(Uint8List bytes, String contentType) {
    final type = contentType.toLowerCase();
    if (type.contains('mpeg') || type.contains('mp3')) return 'mp3';
    if (type.contains('ogg')) return 'ogg';
    if (type.contains('aac')) return 'aac';
    if (type.contains('wav') || type.contains('wave')) return 'wav';
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) return 'mp3';
    if (bytes.length >= 4 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) return 'wav';
    if (bytes.length >= 4 &&
        bytes[0] == 0x4f &&
        bytes[1] == 0x67 &&
        bytes[2] == 0x67 &&
        bytes[3] == 0x53) return 'ogg';
    return 'wav';
  }

  // 空间广场：今日一言生成逻辑
  Future<String> getDailyQuote(String botId) async {
    final db = DBManager();
    final todayStr =
        "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    final lastDate = await db.getKV('quote_date_$botId');
    final lastQuote = await db.getKV('quote_text_$botId');

    if (lastDate == todayStr && lastQuote != null) return lastQuote;

    final bots = await db.getAllBots();
    final bot = bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
    if (bot.isEmpty || bot['chat_model'] == null) return "今天也要开心度过哦。";

    // 暗中调用 AI 引擎生成，但不暴露在聊天历史中。
    // persistResponse=false 保证生成的回复不会写入聊天室，也不会被自动摘要捕获；
    // includeChatHistory=false 避免今日一言影响正式对话的上下文。
    final res = await sendMessage(
        botId: botId,
        text:
            '这是空间广场的内部内容生成任务，不是在与用户聊天。请结合你的人设，生成一句全天通用的「今日一言」。只输出最终正文，禁止标题、引号、解释、字数说明、Markdown、心情标签和任何“正好X个字”等元话术；不得回应用户、延续聊天或提及对话内容；避免早安、午安、晚安及时间词。近三天已用文案：${(await Future.wait(List.generate(3, (i) async => await db.getKV('quote_text_${botId}_${DateTime.now().subtract(Duration(days: i + 1)).year}-${DateTime.now().subtract(Duration(days: i + 1)).month}-${DateTime.now().subtract(Duration(days: i + 1)).day}')))).whereType<String>().where((e) => e.isNotEmpty).join('｜')}。不得重复或高度近似。',
        persistResponse: false,
        includeChatHistory: false,
        enableAutoSummary: false);
    if (res['success'] == true) {
      var quote = res['reply']?.toString().trim() ?? '';
      // 即便模型仍然自带“今日一言：”前缀，也只保留最终内容，杜绝界面重复显示标题。
      quote = quote
          .replaceFirst(RegExp(r'^今日一言\s*[:：]\s*'), '')
          .replaceAll(RegExp(r'^[「『]|今日一言', caseSensitive: false), '')
          .trim();
      final normalized = quote.isEmpty ? '今天也要开心度过哦。' : quote;
      await db.setKV('quote_date_$botId', todayStr);
      await db.setKV('quote_text_$botId', normalized);
      // 同时写入带日期后缀的 key，供“近三天去重”按日期查询命中，
      // 避免上屏查询用带日期 key、而保存只写无日期 key 导致去重一直失效。
      await db.setKV('quote_text_${botId}_$todayStr', normalized);
      return normalized;
    }
    return "今天也要开心度过哦。";
  }

  // API 测速（返回 Map，兼容旧代码）
  Future<Map<String, dynamic>> testConnectionMap(
      String baseUrl, String apiKey, String modelName) async {
    final start = DateTime.now();
    try {
      final res = await http
          .post(
            Uri.parse("$baseUrl/chat/completions"),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer $apiKey"
            },
            body: jsonEncode({
              "model": modelName,
              "messages": [
                {"role": "user", "content": "1"}
              ],
              "max_tokens": 5
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return {
          'success': true,
          'delay': DateTime.now().difference(start).inMilliseconds
        };
      }
      return {'success': false, 'error': '服务端返回 HTTP ${res.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': '无法连接，请检查 URL 格式或网络'};
    }
  }

  // API 测速（返回 int 毫秒，供新 UI 使用；失败抛异常）
  Future<int> testConnection(
      String baseUrl, String apiKey, String modelName) async {
    final result = await testConnectionMap(baseUrl, apiKey, modelName);
    if (result['success'] == true) {
      return result['delay'] as int;
    }
    throw Exception(result['error'] ?? '连接失败');
  }

  bool _needsWebSearch(String text) {
    const cues = [
      '搜索',
      '查一下',
      '查找',
      '联网',
      '最新',
      '新闻',
      '实时',
      '今天',
      '天气',
      '汇率',
      '价格',
      '股价',
      '比赛结果'
    ];
    return cues.any(text.contains);
  }

  /// 归一化搜索服务商名称：剥离 UI 上附加的“（需外网）”等可达性标注，
  /// 兼容新旧取值，统一映射到路由用的规范化名称。
  String _normalizeSearchProvider(String raw) {
    final base = raw.replaceAll(RegExp(r'[（(].*[)）]'), '').trim();
    if (base.contains('Agent-Reach') || base.contains('Agent Reach')) {
      return 'Agent Reach';
    }
    if (base.contains('Tavily')) return 'Tavily';
    if (base.contains('博查') || base.contains('Bocha')) return '博查 Bocha';
    if (base.contains('Serper')) return 'Serper';
    if (base.contains('Brave')) return 'Brave Search';
    if (base.contains('Bing')) return 'Bing Web Search';
    return base;
  }

  Future<List<Map<String, String>>> _searchIfAuthorized(
      DBManager db, String query,
      {bool force = false}) async {
    if ((!force && !_needsWebSearch(query)) ||
        await db.getKV('web_search_enabled') != 'true') return [];
    final apiKey = (await db.getKV('web_search_api_key') ?? '').trim();
    if (apiKey.isEmpty) return [];
    final provider =
        _normalizeSearchProvider(await db.getKV('web_search_provider') ?? '');
    List<Map<String, String>> rows;
    try {
      late final http.Response response;
      if (provider == 'Tavily') {
        response = await http
            .post(
              Uri.parse('https://api.tavily.com/search'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(
                  {'api_key': apiKey, 'query': query, 'max_results': 5}),
            )
            .timeout(const Duration(seconds: 15));
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        rows = _searchRows(body['results']);
      } else if (provider == '博查 Bocha') {
        response = await http
            .post(
              Uri.parse('https://api.bochaai.com/v1/web-search'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey'
              },
              body: jsonEncode({'query': query, 'count': 5}),
            )
            .timeout(const Duration(seconds: 15));
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        rows = _searchRows(
            body['data']?['webPages']?['value'] ?? body['data']?['value']);
      } else if (provider == 'Serper') {
        response = await http
            .post(
              Uri.parse('https://google.serper.dev/search'),
              headers: {
                'Content-Type': 'application/json',
                'X-API-KEY': apiKey
              },
              body: jsonEncode({'q': query, 'num': 5}),
            )
            .timeout(const Duration(seconds: 15));
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        rows = _searchRows(body['organic']);
      } else if (provider == 'Brave Search') {
        response = await http.get(
          Uri.parse(
              'https://api.search.brave.com/res/v1/web/search?q=${Uri.encodeQueryComponent(query)}&count=5'),
          headers: {
            'Accept': 'application/json',
            'X-Subscription-Token': apiKey
          },
        ).timeout(const Duration(seconds: 15));
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        rows = _searchRows(body['web']?['results']);
      } else {
        response = await http.get(
          Uri.parse(
              'https://api.bing.microsoft.com/v7.0/search?q=${Uri.encodeQueryComponent(query)}&count=5'),
          headers: {'Ocp-Apim-Subscription-Key': apiKey},
        ).timeout(const Duration(seconds: 15));
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        rows = _searchRows(body['webPages']?['value']);
      }
    } catch (_) {
      rows = [];
    }
    // 路由策略：普通搜索引擎搜不到时，若已配置 Agent-Reach 桥接地址，
    // 自动降级到 Agent-Reach 的补充平台搜索渠道。
    if (rows.isEmpty) {
      // Agent-Reach 是内部兜底能力，桥接地址与普通搜索 API Key 分开保存，
      // 不暴露为用户可选的搜索服务商。
      final bridge = (await db.getKV('agent_reach_bridge_url') ?? '').trim();
      if (bridge.startsWith('http')) {
        final bridgeRows = await _searchViaAgentReach(bridge, query);
        if (bridgeRows.isNotEmpty) return bridgeRows;
      }
    }
    return rows;
  }

  /// Agent-Reach 平台路由：按查询意图命中 GitHub / YouTube / B站 / X / 小红书 /
  /// Reddit 等渠道，命中则走对应渠道，否则退回 its 全网语义搜索渠道。
  Future<List<Map<String, String>>> _searchViaAgentReach(
      String bridge, String query) async {
    try {
      final base = bridge.replaceFirst(RegExp(r'/+$'), '');
      if (!base.startsWith('http')) return [];
      final routes = <Map<String, dynamic>>[
        {
          'route': 'github',
          'cues': ['github', '仓库', 'repo', '代码仓库', 'issue']
        },
        {
          'route': 'youtube',
          'cues': ['youtube', 'youtube频道', '油管', '视频教程']
        },
        {
          'route': 'bilibili',
          'cues': ['b站', '哔哩', 'bilibili', 'bili', '弹幕']
        },
        {
          'route': 'twitter',
          'cues': ['推特', 'twitter', 'x平台', 'x站']
        },
        {
          'route': 'xiaohongshu',
          'cues': ['小红书', 'xhs', 'xiaohongshu', '种草']
        },
        {
          'route': 'reddit',
          'cues': ['reddit', '红迪']
        },
      ];
      final lower = query.toLowerCase();
      String? route;
      for (final entry in routes) {
        final cues = entry['cues'] as List;
        if (cues.any((cue) => lower.contains(cue.toString()))) {
          route = entry['route'] as String;
          break;
        }
      }
      final path = route != null ? '/$route/search' : '/exa/search';
      final response = await http
          .post(Uri.parse('$base$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'query': query, 'limit': 5}))
          .timeout(const Duration(seconds: 18));
      if (response.statusCode < 200 || response.statusCode >= 300) return [];
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return _searchRows(
          body['results'] ?? body['data'] ?? body['items'] ?? body);
    } catch (_) {
      return [];
    }
  }

  List<Map<String, String>> _searchRows(dynamic rows) {
    if (rows is! List) return [];
    return rows
        .map((raw) {
          final row = raw is Map ? raw : const <String, dynamic>{};
          return <String, String>{
            'title':
                row['title']?.toString() ?? row['name']?.toString() ?? '网页来源',
            'url': row['url']?.toString() ?? row['link']?.toString() ?? '',
            'snippet': row['content']?.toString() ??
                row['snippet']?.toString() ??
                row['description']?.toString() ??
                '',
          };
        })
        .where((row) => row['url']!.startsWith('http'))
        .toList();
  }

  bool _needsImageGeneration(String text) {
    const cues = ['生成图片', '生成一张图', '画一张', '画个', '帮我画', '生图', '画图', '绘制'];
    return cues.any(text.contains);
  }

  Future<String?> _generateImageIfAuthorized({
    required DBManager db,
    required String botId,
    required String prompt,
    bool force = false,
  }) async {
    if ((!force && !_needsImageGeneration(prompt)) ||
        await db.getKV('bot_image_generation_enabled') == 'false') return null;
    final prefs = await SharedPreferences.getInstance();
    final imageModelId =
        (prefs.getString('image_gen_model_$botId') ?? '').trim();
    if (imageModelId.isEmpty) return null;
    final provider = await db.getChatProviderById(imageModelId);
    if (provider == null) return null;
    final baseUrl = (provider['base_url']?.toString() ?? '')
        .replaceFirst(RegExp(r'/+$'), '');
    if (baseUrl.isEmpty) return null;
    // “不选择”或空风格时不给生图模型任何风格约束，让模型自行决定；
    // 只有填写了具体风格才拼进 prompt。
    final styleRaw = (await db.getKV('bot_image_style') ?? '').trim();
    final styleSuffix =
        (styleRaw.isEmpty || styleRaw == '不选择') ? '' : '，画面风格：$styleRaw。';
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/images/generations'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${provider['api_key']}'
            },
            body: jsonEncode({
              'model': provider['model'],
              'prompt': '$prompt$styleSuffix',
              'n': 1,
              'size': '1024x1024'
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final data = body['data'];
      if (data is! List || data.isEmpty) return null;
      final item = data.first;
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}/tide_image_${DateTime.now().millisecondsSinceEpoch}.png';
      final b64 = item['b64_json']?.toString();
      if (b64 != null && b64.isNotEmpty) {
        await File(path).writeAsBytes(base64Decode(b64));
        return path;
      }
      final url = item['url']?.toString() ?? '';
      if (url.startsWith('http')) {
        final file =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
        if (file.statusCode == 200) {
          await File(path).writeAsBytes(file.bodyBytes);
          return path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 统一执行工具调用并取得模型 follow-up 文本。供流式与非流式两条链路复用，
  /// 保证「工具结果 → 最终回答」在两种模式下行为一致。
  Future<void> _runStreamedTools({
    required DBManager db,
    required String botId,
    required List<Map<String, dynamic>> calls,
    required List<Map<String, dynamic>> messages,
    required String baseUrl,
    required String modelName,
    required String apiKey,
    required int maxTokens,
    void Function(String delta)? onDelta,
    required void Function(String) replyTextCallback,
    required void Function(Map) usageCallback,
    required void Function(List<Map<String, String>>) searchSourcesSetter,
    required void Function(String) generatedImageSetter,
    required void Function(Map<String, dynamic>) stickerSetter,
    required void Function(Map<String, dynamic>) pendingDeviceActionSetter,
    required void Function() silenceSetter,
  }) async {
    for (final call in calls) {
      final result = await _executeNativeToolCall(
        db: db,
        botId: botId,
        call: call,
      );
      if (result['sources'] is List) {
        searchSourcesSetter(
          (result['sources'] as List)
              .whereType<Map>()
              .map((item) => Map<String, String>.from(item))
              .toList(),
        );
      }
      final toolResult = result['result'];
      if (toolResult is Map && toolResult['silent'] == true) {
        silenceSetter();
        return;
      }
      if (toolResult is Map &&
          toolResult['image_path']?.toString().isNotEmpty == true) {
        generatedImageSetter(toolResult['image_path'].toString());
      }
      if (toolResult is Map && toolResult['pending_confirmation'] == true) {
        pendingDeviceActionSetter(Map<String, dynamic>.from(toolResult));
      }
      if (toolResult is Map) {
        final stickerValue = toolResult['sticker'];
        if (stickerValue is Map) {
          stickerSetter(Map<String, dynamic>.from(stickerValue));
        } else {
          final stickerPath =
              toolResult['sticker_path']?.toString().trim() ?? '';
          if (stickerPath.isNotEmpty) {
            stickerSetter({'file_path': stickerPath});
          }
        }
      }
      messages.add({
        'role': 'tool',
        'tool_call_id': call['id']?.toString() ?? '',
        'content': jsonEncode(result['result'] ?? result),
      });
    }
    // Keep the same transcript across multi-step tools. Each follow-up may ask
    // for another action; its result is appended and sent back until the model
    // stops using tools. A hard limit prevents accidental infinite automation.
    for (var round = 0; round < 12; round++) {
      final followUp = await http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': modelName,
              'messages': messages,
              'max_tokens': maxTokens,
              'tools': await _buildNativeTools(db,
                  botId: botId, allowSticker: false),
              'tool_choice': 'auto',
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (followUp.statusCode != 200) return;
      final decoded = jsonDecode(utf8.decode(followUp.bodyBytes));
      final message = decoded['choices']?[0]?['message'];
      final fu = decoded['usage'];
      if (fu is Map) usageCallback(fu);
      if (message is! Map) return;
      final next = message['content']?.toString() ?? '';
      final nextCalls = message['tool_calls'] is List
          ? (message['tool_calls'] as List)
              .whereType<Map>()
              .map((call) => Map<String, dynamic>.from(call))
              .toList()
          : <Map<String, dynamic>>[];
      if (nextCalls.isEmpty) {
        if (next.isNotEmpty) {
          replyTextCallback(next);
          onDelta?.call(next);
        }
        return;
      }
      messages.add({
        'role': 'assistant',
        'content': next,
        'tool_calls': nextCalls,
      });
      for (final call in nextCalls) {
        final result =
            await _executeNativeToolCall(db: db, botId: botId, call: call);
        final toolResult = result['result'];
        if (toolResult is Map && toolResult['pending_confirmation'] == true) {
          pendingDeviceActionSetter(Map<String, dynamic>.from(toolResult));
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': call['id']?.toString() ?? '',
          'content': jsonEncode(result['result'] ?? result),
        });
      }
    }
    replyTextCallback('任务已达到连续操作上限，请确认当前结果后再继续。');
  }

  Future<bool> _shouldOfferSticker(DBManager db) async {
    if (await db.getKV('bot_stickers_enabled') != 'true') return false;
    if ((await db.stickerEmotions()).isEmpty) return false;
    final chance =
        (int.tryParse(await db.getKV('bot_sticker_chance') ?? '') ?? 30)
            .clamp(0, 100);
    final selected =
        chance >= 100 || (chance > 0 && Random.secure().nextInt(100) < chance);
    AppLogService.instance.add('STICKER',
        selected ? '本轮允许表情包工具（概率 $chance%）' : '本轮不提供表情包工具（概率 $chance%）');
    return selected;
  }

  Future<String?> _chooseStickerEmotion(DBManager db) async {
    final emotions = await db.stickerEmotions();
    if (emotions.isEmpty) return null;
    return emotions[Random.secure().nextInt(emotions.length)];
  }

  Future<List<Map<String, dynamic>>> _buildNativeTools(DBManager db,
      {required String botId, bool allowSticker = true}) async {
    final tools = <Map<String, dynamic>>[];
    if (await db.getKV('web_search_enabled') == 'true' &&
        (await db.getKV('web_search_api_key') ?? '').trim().isNotEmpty) {
      tools.add({
        'type': 'function',
        'function': {
          'name': 'web_search',
          'description': '查询需要实时性、外部来源或事实核验的信息。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '简洁明确的搜索关键词'}
            },
            'required': ['query'],
            'additionalProperties': false,
          },
        },
      });
    }
    if (await db.getKV('bot_image_generation_enabled') != 'false') {
      // 具体 bot 是否配置生图模型由执行阶段校验，未配置时返回明确 tool 结果。
      tools.add(_imageToolSchema());
    }
    tools.add({
      'type': 'function',
      'function': {
        'name': 'create_future_task',
        'description':
            '仅在用户明确要求提醒、定时、稍后执行或安排未来事项时创建未来任务。创建前必须确认当前未来任务中没有同一事项；相同标题、时间或目的的任务不得重复创建。run_at 必须是当地未来时间，格式 YYYY-MM-DD HH:mm。',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': '简短任务标题'},
            'prompt': {'type': 'string', 'description': '到时要执行或提醒的完整内容'},
            'run_at': {
              'type': 'string',
              'description': '当地未来时间，YYYY-MM-DD HH:mm'
            },
            'frequency': {
              'type': 'string',
              'enum': ['once', 'daily'],
              'description': '一次或每天'
            }
          },
          'required': ['title', 'run_at'],
          'additionalProperties': false,
        },
      },
    });
    if (await LifeScheduleService.instance.enabled()) {
      tools.add({
        'type': 'function',
        'function': {
          'name': 'update_life_state',
          'description': '仅当真实聊天使生活状态确有必要改变时，更新自己的详细穿搭、心情或今日可变日程。绝不可删除或改写刚性事项。',
          'parameters': {
            'type': 'object',
            'properties': {
              'kind': {
                'type': 'string',
                'enum': ['outfit', 'schedule'],
                'description': 'outfit 仅换穿搭；schedule 替换今日可变日程且必须原样保留刚性事项',
              },
              'outfit': {'type': 'string', 'description': '换装时的完整从头到脚穿搭描述'},
              'mood': {'type': 'string', 'description': '可选的新心情'},
              'timeline': {
                'type': 'array',
                'items': {'type': 'object'},
                'description': '改日程时的完整时间线；刚性事项必须保留 time、activity 与 rigid:true',
              },
            },
            'required': ['kind'],
            'additionalProperties': false,
          },
        },
      });
    }
    if ((await db.getKV('adaptive_silence_enabled')) != 'false') {
      tools.add(_adaptiveSilenceToolSchema());
    }
    tools.add(_diaryToolSchema());
    if (allowSticker &&
        (await db.getKV('bot_stickers_enabled') == 'true') &&
        (await db.stickerEmotions()).isNotEmpty) {
      tools.add({
        'type': 'function',
        'function': {
          'name': 'send_sticker',
          'description': '在合适的情绪表达时发送一张已有表情包。',
          'parameters': {
            'type': 'object',
            'properties': {
              'emotion': {'type': 'string', 'description': '已存在的情绪分类'}
            },
            'required': ['emotion'],
            'additionalProperties': false,
          },
        },
      });
    }
    if (await DeviceCapabilityService.instance
        .isAuthorized(DeviceCapabilityService.controlFeature, botId)) {
      final allowed = await DeviceCapabilityService.instance
          .whitelist(DeviceCapabilityService.controlFeature);
      if (allowed.isNotEmpty) {
        final apps = await DeviceCapabilityService.instance.installedApps();
        final appSummary = apps
            .take(120)
            .map((app) => '${app['label']}(${app['packageName']})')
            .join('、');
        tools.add({
          'type': 'function',
          'function': {
            'name': 'request_device_action',
            'description':
                '请求执行已授权的手机操作。不会立即执行，TideBot 会向用户显示具体操作并等待一次明确确认。可按坐标或文字/资源ID操作、打开关闭应用及跳转。当前应用是 TideBot（com.yutan123.tidebot），需要用户及时查看消息可使用 jump_tidebot。已安装可启动应用：$appSummary',
            'parameters': {
              'type': 'object',
              'properties': {
                'action': {'type': 'string', 'enum': allowed.toList()..sort()},
                'x': {'type': 'integer'},
                'y': {'type': 'integer'},
                'text': {'type': 'string'},
                'packageName': {
                  'type': 'string',
                  'description': '目标应用包名；打开/关闭应用时使用'
                },
                'selector': {
                  'type': 'string',
                  'description': '屏幕中要点击的文字、描述或资源 ID'
                },
                'reason': {'type': 'string', 'description': '向用户说明这一步将做什么'}
              },
              'required': ['action', 'reason'],
              'additionalProperties': false,
            },
          },
        });
      }
    }
    return tools;
  }

  Map<String, dynamic> _adaptiveSilenceToolSchema() => {
        'type': 'function',
        'function': {
          'name': 'choose_silence',
          'description':
              '仅在用户明确不希望回复、对话自然结束且无需回应，或主动问候判断不宜打扰时调用。调用后本轮不会发送任何文字。绝不可用于求助、悲伤、愤怒、困惑、危机、提问或任何需要回应的情况；绝不可作为惩罚、冷暴力、控制或施压。',
          'parameters': {
            'type': 'object',
            'properties': {},
            'additionalProperties': false
          },
        },
      };
  Map<String, dynamic> _diaryToolSchema() => {
        'type': 'function',
        'function': {
          'name': 'write_diary',
          'description':
              '只在本机器人亲自参与的本轮聊天中，出现已经实际发生且明确说出的重要事件、稳定事实或真实感受时调用。绝不编造、推测、移植其他机器人的经历或称呼；日记不会作为聊天正文发送。',
          'parameters': {
            'type': 'object',
            'properties': {
              'entry': {'type': 'string', 'description': '第一人称、简洁具体的日记记录'}
            },
            'required': ['entry'],
            'additionalProperties': false
          },
        },
      };
  Map<String, dynamic> _imageToolSchema() => {
        'type': 'function',
        'function': {
          'name': 'generate_image',
          'description': '仅在用户明确要求生成、绘制或创作图片时调用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'prompt': {'type': 'string', 'description': '完整的绘图提示词'}
            },
            'required': ['prompt'],
            'additionalProperties': false,
          },
        },
      };

  Future<Map<String, dynamic>> _executeNativeToolCall({
    required DBManager db,
    required String botId,
    required Map<String, dynamic> call,
  }) async {
    final function = call['function'];
    if (function is! Map)
      return {
        'result': {'ok': false, 'error': '无效工具调用'}
      };
    final name = function['name']?.toString() ?? '';
    Map<String, dynamic> args = {};
    try {
      final raw = function['arguments']?.toString() ?? '{}';
      final parsed = jsonDecode(raw);
      if (parsed is Map) args = Map<String, dynamic>.from(parsed);
    } catch (_) {
      return {
        'result': {'ok': false, 'error': '工具参数不是合法 JSON'}
      };
    }
    if (name == 'request_device_action') {
      final action = args['action']?.toString() ?? '';
      final reason = args['reason']?.toString().trim() ?? '';
      final allowed = await DeviceCapabilityService.instance
          .isAuthorized(DeviceCapabilityService.controlFeature, botId);
      final whitelisted = await DeviceCapabilityService.instance
          .whitelist(DeviceCapabilityService.controlFeature);
      if (!allowed || !whitelisted.contains(action) || reason.isEmpty) {
        return {
          'result': {'ok': false, 'error': '该设备操作未获授权'}
        };
      }
      return {
        'result': {
          'ok': true,
          'pending_confirmation': true,
          'message': '操作尚未执行，必须由用户在界面中逐次确认。',
          'action': action,
          'reason': reason,
          if (args['x'] is num) 'x': (args['x'] as num).toInt(),
          if (args['y'] is num) 'y': (args['y'] as num).toInt(),
          if (args['text'] != null) 'text': args['text'].toString(),
          if (args['packageName'] != null)
            'packageName': args['packageName'].toString(),
          if (args['selector'] != null) 'selector': args['selector'].toString(),
        },
      };
    }
    if (name == 'choose_silence') {
      return {
        'result': {'ok': true, 'silent': true}
      };
    }
    if (name == 'write_diary') {
      final entry = args['entry']?.toString().trim() ?? '';
      if (entry.isEmpty)
        return {
          'result': {'ok': false, 'error': '缺少日记内容'}
        };
      await db.upsertMemoryItem(
          botId: botId,
          type: 'short',
          content: entry,
          title: '日记',
          category: 'diary',
          importance: 3);
      AppLogService.instance
          .add('DIARY', '机器人通过 write_diary 工具写入日记：${entry.length} 字');
      return {
        'result': {'ok': true, 'message': '日记已安全写入，不要在聊天中复述日记正文。'}
      };
    }
    if (name == 'web_search') {
      final query = args['query']?.toString().trim() ?? '';
      if (query.isEmpty)
        return {
          'result': {'ok': false, 'error': '缺少 query'}
        };
      final rows = await _searchIfAuthorized(db, query, force: true);
      return {
        'sources': rows,
        'result': {
          'ok': rows.isNotEmpty,
          'results': rows,
          'message': rows.isEmpty ? '没有可用搜索结果。' : '搜索完成，请仅依据结果回答并引用来源。',
        }
      };
    }
    if (name == 'generate_image') {
      var prompt = args['prompt']?.toString().trim() ?? '';
      final life = await LifeScheduleService.instance.ensureToday(botId);
      final outfit = life?['outfit']?.toString().trim() ?? '';
      if (outfit.isNotEmpty) {
        prompt = '$prompt。人物穿搭必须严格遵循：$outfit';
      }
      final path = prompt.isEmpty
          ? null
          : await _generateImageIfAuthorized(
              db: db, botId: botId, prompt: prompt, force: true);
      return {
        'result': {
          'ok': path != null,
          'image_path': path,
          'message': path == null ? '图片生成失败或未配置生图模型。' : '图片已生成并将作为聊天图片发送。',
        }
      };
    }
    if (name == 'create_future_task') {
      final title = args['title']?.toString().trim() ?? '';
      final prompt = args['prompt']?.toString().trim() ?? title;
      final rawRunAt = args['run_at']?.toString().trim() ?? '';
      final parsed = DateTime.tryParse(rawRunAt.replaceFirst(' ', 'T'));
      if (title.isEmpty || parsed == null) {
        return {
          'result': {
            'ok': false,
            'error': '缺少 title 或 run_at 格式不正确，应为 YYYY-MM-DD HH:mm'
          }
        };
      }
      final runAt = parsed.millisecondsSinceEpoch;
      if (runAt <= DateTime.now().millisecondsSinceEpoch) {
        return {
          'result': {'ok': false, 'error': '未来任务必须设置在当前时间之后'}
        };
      }
      final frequency =
          args['frequency']?.toString() == 'daily' ? 'daily' : 'once';
      final existingTasks = await db.querySchedules(botId);
      final normalizedTitle =
          title.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      final duplicate = existingTasks.any((task) {
        final oldTitle = (task['title']?.toString() ?? '')
            .replaceAll(RegExp(r'\s+'), '')
            .toLowerCase();
        final oldRunAt = (task['run_at'] as num?)?.toInt() ?? 0;
        return oldTitle == normalizedTitle &&
            oldRunAt == runAt &&
            task['status']?.toString() != 'done';
      });
      if (duplicate)
        return {
          'result': {
            'ok': true,
            'duplicate': true,
            'message': '相同未来任务已存在，未重复创建。'
          }
        };
      final id = 'future_${botId}_${runAt}_${title.hashCode.abs()}';
      await db.insertFutureTask({
        'id': id,
        'bot_id': botId,
        'title': title,
        'note': prompt,
        'time': runAt,
        'is_done': 0,
        'frequency': frequency,
        'prompt': prompt,
        'run_at': runAt,
        'status': 'pending',
      });
      return {
        'result': {'ok': true, 'id': id, 'message': '未来任务已创建：$title'}
      };
    }
    if (name == 'update_life_state') {
      final updated =
          await LifeScheduleService.instance.updateFromTool(botId, args);
      return {
        'result': {
          'ok': updated != null,
          'message':
              updated == null ? '未修改：日程不存在、参数无效，或试图改动刚性事项。' : '今日生活状态已更新。',
        }
      };
    }
    if (name == 'send_sticker') {
      final emotion = args['emotion']?.toString().trim() ?? '';
      final candidates = await db.queryStickers(emotion: emotion);
      final available =
          candidates.isEmpty ? await db.queryStickers() : candidates;
      final selected = available.isEmpty ? null : available.first;
      final targetPath = selected?['file_path']?.toString().trim() ?? '';
      if (targetPath.isEmpty) {
        return {
          'result': {'ok': false, 'error': '选中的表情包缺少文件路径'}
        };
      }
      return {
        'result': {
          'ok': true,
          'sticker': Map<String, dynamic>.from(selected!),
          'message': '表情包已选定。',
        }
      };
    }
    return {
      'result': {'ok': false, 'error': '未知工具：$name'}
    };
  }

  Future<String> _buildToolContext(DBManager db,
      {bool allowSticker = true, String? forcedStickerEmotion}) async {
    final parts = <String>[];
    if (await db.getKV('bot_image_generation_enabled') != 'false') {
      final style = (await db.getKV('bot_image_style') ?? '写实').trim();
      final styleRule = style.isEmpty || style == '不选择'
          ? '图片风格由你根据用户需求自行决定。'
          : '所有图片必须采用“$style”风格。';
      parts.add('【已授权工具：生图】当用户明确需要图片时，可建议使用生图；$styleRule 不要声称已生成不存在的图片。');
    }
    if (await db.getKV('web_search_enabled') == 'true') {
      final provider = _normalizeSearchProvider(
          await db.getKV('web_search_provider') ?? 'Tavily');
      final hasKey = (await db.getKV('web_search_api_key') ?? '').isNotEmpty;
      if (hasKey) {
        parts.add(
            '【已授权工具：联网搜索】可在用户明确要求实时信息、需要来源或无法可靠回答时提出搜索建议。当前服务商：$provider。搜索后必须附可点击来源；不要编造搜索结果。');
      }
    }
    if (allowSticker && forcedStickerEmotion != null) {
      parts.add(
          '【本轮表情包】概率已命中，TideBot 将在回复完成后自动从“$forcedStickerEmotion”分类随机发送一张。不要调用工具、不要讨论是否发送，也不要在正文输出贴纸协议。');
    }
    return parts.isEmpty ? '' : '\n${parts.join('\n')}';
  }

  // 构建核心防御护栏与游戏机制注入
  Future<String?> generateTTS(String text, String providerId) =>
      _generateTTS(text, providerId);
  Future<Map<String, dynamic>> testProviderCapabilities(
      String baseUrl, String apiKey, String model) async {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final modelName = model.split(',').first.trim();
    if (root.isEmpty || apiKey.trim().isEmpty || modelName.isEmpty) {
      return {'capabilities': <String>[], 'error': '请填写 API 地址、Key 和模型名'};
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
    bool success(http.Response response) =>
        response.statusCode >= 200 && response.statusCode < 300;

    // 每个探测返回 (是否成功, 耗时毫秒)；失败也返回耗时便于诊断。
    Future<Map<String, dynamic>> probe(
        String name, Future<bool> Function() run) async {
      final t0 = DateTime.now();
      var ok = false;
      var latency = 0;
      try {
        ok = await run();
      } catch (_) {
        ok = false;
      }
      latency = DateTime.now().difference(t0).inMilliseconds;
      return {'name': name, 'ok': ok, 'latency': latency};
    }

    String lastError = '';
    Future<bool> postJson(String path, Map<String, dynamic> body) async {
      try {
        final response = await http
            .post(Uri.parse('$root$path'),
                headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 30));
        final responseText =
            utf8.decode(response.bodyBytes, allowMalformed: true);
        if (!success(response) || response.bodyBytes.isEmpty) {
          final compact = responseText.replaceAll(RegExp(r'\s+'), ' ').trim();
          final summary =
              compact.length <= 240 ? compact : compact.substring(0, 240);
          lastError = 'HTTP ${response.statusCode}: $summary';
          return false;
        }
        try {
          final decoded = jsonDecode(responseText);
          if (decoded is! Map || decoded['error'] != null) {
            lastError = decoded is Map
                ? (decoded['error']?.toString() ?? '响应格式异常')
                : '响应格式异常';
            return false;
          }
          if (path == '/chat/completions') {
            final content = _extractChatContent(decoded);
            if (content.isEmpty) lastError = 'HTTP 200，但未解析到聊天正文';
            return content.isNotEmpty;
          }
          if (path == '/images/generations') {
            return decoded['data'] is List &&
                (decoded['data'] as List).isNotEmpty;
          }
          return true;
        } catch (error) {
          lastError = '响应解析失败：$error';
          return false;
        }
      } catch (error) {
        lastError = '请求异常：$error';
        return false;
      }
    }

    Future<bool> stt() async {
      try {
        // A minimal valid PCM WAV avoids treating a missing multipart file as a test.
        const wav = <int>[
          82,
          73,
          70,
          70,
          36,
          0,
          0,
          0,
          87,
          65,
          86,
          69,
          102,
          109,
          116,
          32,
          16,
          0,
          0,
          0,
          1,
          0,
          1,
          0,
          128,
          62,
          0,
          0,
          0,
          125,
          0,
          0,
          2,
          0,
          16,
          0,
          100,
          97,
          116,
          97,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ];
        final request = http.MultipartRequest(
            'POST', Uri.parse('$root/audio/transcriptions'))
          ..headers['Authorization'] = 'Bearer $apiKey'
          ..fields['model'] = modelName
          ..files.add(http.MultipartFile.fromBytes('file', wav,
              filename: 'tidebot-test.wav', contentType: null));
        final response =
            await request.send().timeout(const Duration(seconds: 20));
        return response.statusCode >= 200 && response.statusCode < 300;
      } catch (_) {
        return false;
      }
    }

    const onePixel =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

    // 并发探测文本、STT、识图、生图四项能力，任意一项成功即判定通过，
    // 并返回四项中「最快成功」的延迟（毫秒）。
    final probes = await Future.wait<Map<String, dynamic>>([
      probe(
          '文本',
          () => postJson('/chat/completions', {
                'model': modelName,
                'messages': [
                  {'role': 'user', 'content': 'ping'}
                ],
                'max_tokens': 32,
              })),
      probe('STT', stt),
      probe(
          '识图',
          () => postJson('/chat/completions', {
                'model': modelName,
                'messages': [
                  {
                    'role': 'user',
                    'content': [
                      {
                        'type': 'text',
                        'text': 'Describe this image in one word.'
                      },
                      {
                        'type': 'image_url',
                        'image_url': {'url': onePixel}
                      },
                    ],
                  }
                ],
                'max_tokens': 8,
              })),
      probe(
          '生图',
          () => postJson('/images/generations', {
                'model': modelName,
                'prompt': 'A single blue pixel.',
                'size': '256x256',
                'n': 1,
              })),
    ]);

    final capabilities = <String>[];
    final latencies = <String, int>{};
    int? fastest;
    String? fastestName;
    for (final p in probes) {
      final name = p['name'] as String;
      final ok = p['ok'] as bool;
      final latency = p['latency'] as int;
      latencies[name] = latency;
      if (ok) {
        capabilities.add(name);
        if (fastest == null || latency < fastest) {
          fastest = latency;
          fastestName = name;
        }
      }
    }

    final passed = capabilities.contains('文本');
    return {
      'capabilities': capabilities,
      'passed': passed,
      'latencies': latencies,
      'fastest_latency': fastest,
      'fastest_name': fastestName,
      // 基础聊天请求成功才算配置可用；其他能力是附加探测。
      if (!passed) 'error': lastError.isEmpty ? '聊天模型基础请求失败' : lastError,
    };
  }

  String _safetyContext(String userText) {
    final risky = RegExp(
            r'(色情|裸聊|成人视频|强奸|轮奸|未成年.{0,6}(性|裸|色情)|自杀|自残|割腕|炸弹|爆炸物|制毒|毒品|枪支|杀人|恐怖袭击|极端组织|诈骗|洗钱|盗号|破解|木马|勒索|人肉|仇恨|种族灭绝)',
            caseSensitive: false)
        .hasMatch(userText);
    return risky
        ? '\n【安全处理】用户消息可能涉及违法、危险、露骨、仇恨、欺诈、隐私或自伤内容。不要生成、补全、鼓励或提供可执行细节；保持你的人设，以温和、不评判的方式拒绝或转移到安全话题。若涉及即时自伤或他伤风险，优先鼓励联系当地紧急服务、可信赖的人或专业支持。'
        : '\n【安全规则】不得生成违法、危险、露骨色情、剥削未成年人、仇恨骚扰、欺诈、隐私侵害或自伤他伤的可执行内容；遇到此类请求应保持人设并温和转移到安全话题。';
  }

  String _localSystemPrompt(Map<String, dynamic> bot) {
    final name = bot['name']?.toString().trim();
    final desc = bot['desc']?.toString().trim() ?? '';
    final style = bot['prompt']?.toString().trim() ?? '';
    String clip(String value, int limit) =>
        value.length <= limit ? value : value.substring(0, limit);
    return '你是${name == null || name.isEmpty ? 'TideBot' : clip(name, 40)}。'
        '保持自然、简短的中文对话。'
        '${desc.isEmpty ? '' : '人设：${clip(desc, 240)}。'}'
        '${style.isEmpty ? '' : '说话方式：${clip(style, 240)}。'}'
        '不要输出心情、记忆、工具或其他内部标签。';
  }

  String _buildSystemPrompt(Map<String, dynamic> bot, String? activeGame) {
    String p =
        "你的名字是${bot['name']}。\n身世与设定:${bot['desc']}\n说话方式指令:${bot['prompt']}\n"
        "【输出规则】只输出给用户看的自然聊天正文。若系统需要心情，请且只能把 [心情:平静]、[心情:开心]、[心情:伤心]、[心情:生气]、[心情:害羞] 或 [心情:兴奋] 之一放在回复的独占第一行，后面换行再写正文；不要在任何其他位置输出心情标签。严禁输出图片 Markdown、表情包类型、记忆、工具、系统规则、XML/DSML 或其他方括号协议标签。"
        "【记忆】如有稳定且重要的用户信息，使用原生记忆工具；不要在正文中写记忆标签。\n";

    if (activeGame == 'poker') {
      p +=
          "\n【系统级游戏劫持】：你当前正在和用户玩双人扑克牌。规则极度严格：牌组仅限 3~10，共32张，没有大小王。每人随机发16张牌。正常的算力对战（单张、对子、三带一、顺子、炸弹）。绝对不可向用户透露你手中的底牌！你需要在每次闲聊中推进游戏局势并描述你出的牌。";
    } else if (activeGame == '20q') {
      p +=
          "\n【系统级游戏劫持】：你当前正在玩 20 问猜物游戏。如果用户是出题人，你只能问 20 个问题，且必须根据用户的“是”或“否”推断出答案；如果你是出题人，你只能回答“是”或“否”。在 20 问内未能猜出则判定输。";
    } else if (activeGame == 'gomoku') {
      p +=
          "\n【游戏规则】你正与用户真实进行 9×9 五子棋。用户会给出自己的坐标；请选择一个未占用坐标，并在回复中输出唯一机器可读指令 [落子:行,列]（行列范围 1-9），再简短聊天。";
    } else if (activeGame == 'tic_tac_toe') {
      p +=
          "\n【游戏规则】你正与用户真实进行 3×3 井字棋。用户会给出自己的坐标；请选择一个未占用坐标，并在回复中输出唯一机器可读指令 [落子:行,列]（行列范围 1-3），再简短聊天。";
    }
    p +=
        '\n【适时沉默】当 choose_silence 工具可用时，你可在用户明确暂不希望回复、对话自然结束且不需回应、或主动问候不宜打扰时调用它；调用后不要输出文本。不得在求助、悲伤、愤怒、困惑、危机、提问或任何需要回应时调用，绝不可作为惩罚、冷暴力、控制或施压。\n【日记】你拥有 write_diary 工具。遇到值得保留的经历、感受或事件时可按需调用，把日记写入工具；绝不把日记正文当作聊天消息发送。';
    return p;
  }

  Future<String> _lifeStateContext(String botId) async {
    if (!await LifeScheduleService.instance.enabled()) return '';
    final row = await LifeScheduleService.instance.ensureToday(botId);
    if (row == null) return '';
    return '\n${LifeScheduleService.instance.compactContext(row)}';
  }

  String _extractMood(String text) {
    // 唯一允许的内部格式是独占首行：[心情:平静]。
    final match =
        RegExp(r'^\s*\[心情\s*[:：]\s*(平静|开心|伤心|生气|害羞|兴奋)\s*\]\s*(?:\r?\n|$)')
            .firstMatch(text);
    return match?.group(1) ?? '平静';
  }

  /// 解析模型通过内部协议 [记忆:类型|内容]（可多条）主动要求记住的信息，
  /// 以第一人称、无标题、逐条写入 memories 表。
  /// - [记忆:长期|...] -> type=long（用户画像、机器人身份、自我认识等稳定信息）
  /// - [记忆:...]      -> type=short（近期日记式事件）
  Future<void> _persistModelMemories(
    DBManager db,
    String botName,
    String botId,
    String rawReply,
  ) async {
    try {
      final regex = RegExp(r'\[记忆\s*[:：]\s*([^\]]+)\]');
      final matches = regex.allMatches(rawReply).toList();
      if (matches.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      var idx = 0;
      for (final m in matches) {
        var content = m.group(1)?.trim() ?? '';
        if (content.isEmpty) continue;
        var type = 'short';
        // 支持 [记忆:长期|内容] 显式分类；其余事件/感受按第一人称日记写为短期。
        final longPrefix = RegExp(r'^长期\s*[|｜]\s*');
        if (longPrefix.hasMatch(content)) {
          type = 'long';
          content = content.replaceFirst(longPrefix, '').trim();
        }
        content = content
            .replaceFirst(
                RegExp(r'^(?:内容|短期|short)\s*[|｜]\s*', caseSensitive: false), '')
            .trim();
        if (content.isEmpty) continue;
        // 长期记忆绝对不能出现任何时间相关词汇（用户硬性要求）。“我记得”
        // 前缀也绝不写入（统一走 _cleanLongMemoryText）。
        if (type == 'long') {
          content = _cleanLongMemoryText(content);
        }
        // 记忆采用第一人称，但不强制以“我”开头：例如“京太郎每天睡够8小时”
        // 就是正确写法。若模型写出了“我京太郎...”，去掉误加的“我”，避免把
        // 第三人称称呼误当成机器人自己的名字。绝不添加“我记得”前缀。
        content = _stripLooseWo(content);
        content = content.trim();
        if (content.isEmpty) continue;
        await db.upsertMemoryItem(
          botId: botId,
          type: type,
          title: '',
          content: content,
          timestamp: now + idx * 1000,
        );
        idx++;
      }
    } catch (e) {
      print('[memory] persist requested memory failed: $e');
    }
  }

  /// 长期记忆清洗：去掉所有时间相关词，并把“我记得/我记起”开头替换为其后正文，
  /// 保证长期记忆为稳定的第一人称，且绝不残留时间词。写入与注入路径共用，
  /// 兜底处理历史遗留的未清洗长期记忆，确保展示给模型的一定符合规则。
  String _cleanLongMemoryText(String content) {
    var s = content.trim();
    s = s.replaceAll(RegExp(r'^(我)?\s*记得\s*[，,:：]?\s*'), '');
    s = s.replaceAll(
      RegExp(
          r'今天上午|今天中午|今天下午|今天早上|今天夜里|今天|昨天下午|昨天早上|昨天夜里|昨天|明天|前天|后天|昨晚|今晚|今早|近日|最近|上周|本周|下周|刚才|刚刚|现在|此刻|之前|以前|几小时前|几天前|几个星期前|一个月前|凌晨|早上|中午|下午|晚上'),
      '',
    );
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    // 不强制以“我”开头。若模型写出了“我京太郎...”，去掉误加的“我”。
    s = _stripLooseWo(s);
    return s.trim();
  }

  /// 去掉记忆正文前被模型误加的“我”，避免“我京太郎…”。只会在“我”之后
  /// 直接跟着一个疑似人名/称呼（非常见第一人称搭配词）时移除；而“我今天
  /// 很高兴”“我觉得…”等正确的第一人称写法会被保留。
  String _stripLooseWo(String s) {
    // 常见第一人称后续词，遇到这些就说明“我”是真实主语，不能删除。
    const keepList = [
      '今天',
      '今天上午',
      '今天中午',
      '今天下午',
      '今天早上',
      '今天夜里',
      '昨天',
      '明天',
      '前天',
      '后天',
      '昨晚',
      '记得',
      '觉得',
      '想',
      '会',
      '要',
      '是',
      '爱',
      '喜欢',
      '希望',
      '知道',
      '认为',
      '正在',
      '已经',
      '刚',
      '最近',
      '现在',
      '能',
      '可以',
      '应该',
      '很',
      '真的',
      '有点',
      '有些',
      '其实',
      '也',
      '都',
      '还',
      '总',
      '常',
      '曾经',
      '终于',
      '忽然',
      '突然',
      '打算',
      '准备',
      '决定',
      '答应',
      '保证',
      '没有',
      '不是',
      '不会',
      '不想',
      '说不出',
      '很好',
      '很累',
      '很开心'
    ];
    final keep = keepList.map((w) => RegExp.escape(w)).join('|');
    final re = RegExp('^我(?=[\\u4e00-\\u9fa5]{2})(?!$keep)');
    return s.replaceAll(re, '');
  }
}
