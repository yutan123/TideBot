import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';
import 'media_preprocessor.dart';

import 'ops.dart';
import 'app_state.dart';
import 'local_llama.dart';

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
    String? activeGame,
    bool persistResponse = true,
    bool includeChatHistory = true,
    bool enableAutoSummary = true,
    void Function(String delta)? onDelta,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final primaryLocal =
        (prefs.getString('local_chat_model_$botId') ?? '').trim();
    final backupLocal =
        (prefs.getString('local_backup_model_$botId') ?? '').trim();
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
    final backup = {
      'local': backupLocal,
      'provider': backupRemote.isNotEmpty ? backupRemote : primaryRemote,
    };
    final attempts = <Map<String, String>>[
      primary,
      if (backupLocal.isNotEmpty || backupRemote.isNotEmpty) backup,
      if (backupLocal.isNotEmpty || backupRemote.isNotEmpty) backup,
      if (backupLocal.isEmpty && backupRemote.isEmpty) primary,
      if (backupLocal.isEmpty && backupRemote.isEmpty) primary,
    ].take(3).toList();

    Map<String, dynamic>? lastFailure;
    for (var index = 0; index < attempts.length; index++) {
      final candidate = attempts[index];
      final result = await _sendMessageOnce(
        botId: botId,
        text: text,
        imagePath: imagePath,
        activeGame: activeGame,
        persistResponse: persistResponse,
        includeChatHistory: includeChatHistory,
        enableAutoSummary: enableAutoSummary,
        // Streaming can only safely happen for the final attempt: an earlier
        // failed SSE stream must never leave partial text in the visible bubble.
        onDelta: index == attempts.length - 1 ? onDelta : null,
        forcedLocalId: candidate['local']!,
        forcedProviderId: candidate['provider']!,
      );
      if (result['success'] == true) return result;
      lastFailure = result;
    }
    return {
      ...?lastFailure,
      'error': '主模型和备用模型均请求失败（已自动尝试 3 次）。${lastFailure?['error'] ?? ''}',
    };
  }

  Future<Map<String, dynamic>> _sendMessageOnce({
    required String botId,
    required String text,
    String? imagePath,
    String? activeGame,
    bool persistResponse = true,
    bool includeChatHistory = true,
    bool enableAutoSummary = true,
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
    final localId = forcedLocalId.isNotEmpty
        ? forcedLocalId
        : (prefs.getString('local_chat_model_$botId') ?? '').trim();
    if (localId.isNotEmpty) {
      try {
        final history = includeChatHistory
            ? await db.getChatHistory(botId).timeout(const Duration(seconds: 8))
            : <Map<String, dynamic>>[];
        final localMessages = <Map<String, dynamic>>[
          {'role': 'system', 'content': _buildSystemPrompt(bot, activeGame)},
        ];
        for (final msg in history.take(20)) {
          if (msg['type'] == 'text') {
            localMessages.add({
              'role': msg['role'],
              'content': msg['content'],
            });
          }
        }
        if (history.isEmpty || history.last['content']?.toString() != text) {
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
          await db.insertChatMessage({
            'id': messageId,
            'bot_id': botId,
            'role': 'assistant',
            'type': 'text',
            'content': reply,
            'file_path': null,
            'mood': localMood,
            'timestamp': ts + 1,
          });
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

    // Keep stable instructions first for provider prefix caches. Dynamic time is
    // appended last, and history is packed newest-first within the user budget.
    // 稳定记忆放在系统提示的固定位置，动态的中短期记忆限制条数和体积，
    // 避免每轮请求无边界增长，同时尽可能保留服务商前缀缓存命中。
    final longMemories = activeGame == null
        ? await db.queryMemories(botId, type: 'long', limit: 12)
        : <Map<String, dynamic>>[];
    final mediumMemories = activeGame == null
        ? await db.queryMemories(botId, type: 'medium', limit: 6)
        : <Map<String, dynamic>>[];
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

    final longMemoryContext = memoryLines(longMemories, 1800);
    final mediumMemoryContext = memoryLines(mediumMemories, 1600);
    final shortMemoryContext = memoryLines(shortMemories, 1200);
    final toolContext = await _buildToolContext(db);
    final systemPrompt = _buildSystemPrompt(bot, activeGame) +
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
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    final historyMessages = <Map<String, dynamic>>[];
    var usedChars = 0;
    final charBudget = (maxContext * 3.2).floor();
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
      if (usedChars + content.length > charBudget &&
          historyMessages.isNotEmpty) {
        break;
      }
      // 时间只作为系统级元信息保留，不能与可复述的对话正文混排。
      historyMessages.add({'role': msg['role'], 'content': content});
      usedChars += content.length;
    }
    messages.addAll(historyMessages.reversed);
    var lastIsCurrentUser = false;
    // 若最末一条上下文恰好就是本次发送的 user 文本（内存补写导致），
    // 标记以免下方再次追加造成重复喂给模型
    if (history.isNotEmpty) {
      final lastMsg = history.last;
      if ((lastMsg['role'] == 'user') &&
          (lastMsg['content']?.toString() == text) &&
          history.length < 20) {
        lastIsCurrentUser = true;
      }
    }
    // 图片先交给明确配置的视觉模型转述，再将转述交给聊天模型；
    // 未配置视觉模型时仅使用本地 OCR/元数据，绝不把普通聊天模型当作视觉模型。
    if (imagePath != null && imagePath.isNotEmpty) {
      String mediaContext;
      try {
        final prefs = await SharedPreferences.getInstance();
        final visionId = (prefs.getString('vision_model_$botId') ?? '').trim();
        if (visionId.isNotEmpty) {
          final visionProvider = await db.getChatProviderById(visionId);
          if (visionProvider != null) {
            mediaContext = await _describeImage(
              provider: visionProvider,
              imagePath: imagePath,
              userText: text,
            );
          } else {
            mediaContext =
                await MediaPreprocessor().imageFallbackText(imagePath);
          }
        } else {
          mediaContext = await MediaPreprocessor().imageFallbackText(imagePath);
        }
      } catch (e) {
        mediaContext = '[图片预处理失败：$e]';
      }
      final contentWithMedia = '$text\n\n$mediaContext';
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
      messages.add({
        'role': 'system',
        'content':
            '现实时间附注：${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}。仅在用户问题与时间有关时使用。',
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
      final tools = await _buildNativeTools(db);
      final payload = <String, dynamic>{
        'model': modelName,
        'messages': messages,
        'max_tokens': bot['max_tokens'] ?? 10000,
        if (tools.isNotEmpty) 'tools': tools,
        if (tools.isNotEmpty) 'tool_choice': 'auto',
        // 流式与工具调用共存：始终开启 stream，SSE 分片同时收集 tool_calls，
        // 流式结束后若命中工具再执行并做一次非流式 follow-up 取得最终回答。
        if (onDelta != null) 'stream': true,
      };
      String replyText = '';
      String? generatedImagePath;
      Map usage = const {};
      String errorBody = '';
      int statusCode;
      if (onDelta != null) {
        final request =
            http.Request('POST', Uri.parse('$baseUrl/chat/completions'))
              ..headers.addAll({
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream',
                'Authorization': 'Bearer ${provider['api_key']}',
              })
              ..body = jsonEncode(payload);
        final response =
            await request.send().timeout(const Duration(seconds: 40));
        statusCode = response.statusCode;
        if (statusCode == 200) {
          final contentType =
              response.headers['content-type']?.toLowerCase() ?? '';
          if (contentType.contains('application/json')) {
            final body = await response.stream.bytesToString();
            final json = jsonDecode(body);
            replyText =
                json['choices']?[0]?['message']?['content']?.toString() ?? '';
            usage = json['usage'] is Map ? json['usage'] as Map : const {};
            if (replyText.isNotEmpty) onDelta(replyText);
          } else {
            // SSE 流式：逐段回传文本，同时按 index 拼接 tool_calls 分片，
            // 以便工具调用与流式共存。流式结束后统一执行工具并做 follow-up。
            final pendingCalls = <int, Map<String, dynamic>>{};
            await response.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .forEach((line) {
              if (!line.startsWith('data:')) return;
              final data = line.substring(5).trim();
              if (data == '[DONE]' || data.isEmpty) return;
              try {
                final event = jsonDecode(data);
                final delta =
                    event['choices']?[0]?['delta'] as Map? ?? const {};
                final content = delta['content']?.toString() ?? '';
                if (content.isNotEmpty) {
                  replyText += content;
                  onDelta(content);
                }
                // 累加 tool_calls 片段（每个 index 独立拼接 arguments）。
                final chunk = delta['tool_calls'];
                if (chunk is List) {
                  for (final c in chunk.whereType<Map>()) {
                    final idx = ((c['index'] as num?)?.toInt() ?? 0);
                    final call = pendingCalls.putIfAbsent(
                        idx,
                        () => {
                              'id': c['id']?.toString() ?? '',
                              'type': c['type']?.toString() ?? 'function',
                              'function': {
                                'name': '',
                                'arguments': '',
                              }
                            });
                    final fn = c['function'] as Map?;
                    if (fn != null) {
                      final idNow = c['id']?.toString() ?? '';
                      if (idNow.isNotEmpty) call['id'] = idNow;
                      final fnMap = call['function'] as Map;
                      final nameChunk = fn['name']?.toString() ?? '';
                      if (nameChunk.isNotEmpty) {
                        fnMap['name'] = (fnMap['name'] as String) + nameChunk;
                      }
                      final argsChunk = fn['arguments']?.toString() ?? '';
                      if (argsChunk.isNotEmpty) {
                        fnMap['arguments'] =
                            (fnMap['arguments'] as String) + argsChunk;
                      }
                      call['function'] = fnMap;
                    }
                  }
                }
                if (event['usage'] is Map) usage = event['usage'] as Map;
              } catch (_) {}
            });
            if (pendingCalls.isNotEmpty) {
              final calls = pendingCalls.values
                  .where((c) =>
                      (c['function'] as Map?)?['name']?.toString().isNotEmpty ==
                      true)
                  .toList();
              if (calls.isNotEmpty) {
                messages.add({
                  'role': 'assistant',
                  'content': replyText,
                  'tool_calls': calls,
                });
                await _runStreamedTools(
                    db: db,
                    botId: botId,
                    calls: calls,
                    messages: messages,
                    baseUrl: baseUrl,
                    modelName: modelName,
                    apiKey: provider['api_key']?.toString() ?? '',
                    maxTokens: bot['max_tokens'] ?? 10000,
                    onDelta: onDelta,
                    replyTextCallback: (t) => replyText = t,
                    usageCallback: (u) => usage = u,
                    searchSourcesSetter: (l) => searchSources = l,
                    generatedImageSetter: (p) => generatedImagePath = p);
              }
            }
          }
        } else {
          errorBody = await response.stream.bytesToString();
        }
      } else {
        final response = await http
            .post(
              Uri.parse('$baseUrl/chat/completions'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${provider['api_key']}'
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 40));
        statusCode = response.statusCode;
        errorBody = utf8.decode(response.bodyBytes);
        if (statusCode == 200) {
          final json = jsonDecode(errorBody);
          final message = json['choices']?[0]?['message'];
          replyText = message?['content']?.toString() ?? '';
          usage = json['usage'] is Map ? json['usage'] as Map : const {};
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
                  generatedImageSetter: (p) => generatedImagePath = p);
            }
          }
        }
      }
      print('[ai] response status=$statusCode');
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
        if (enableAutoSummary && includeChatHistory && persistResponse) {
          unawaited(_summarizeHistoryIfNeeded(
            bot: bot,
            botId: botId,
            provider: provider,
            modelName: modelName,
            history: history,
            maxContext: maxContext,
          ));
        }

        // 情绪、时间、工具与游戏标记均是内部协议，绝不能进入用户可见文本。
        String mood = _extractMood(replyText);
        // 先抽取模型主动要求记住的信息，再剥离可见文本，避免把它们留在气泡里。
        await _persistModelMemories(db, bot['name']?.toString() ?? 'TideBot',
            bot['id']?.toString() ?? botId, replyText);
        replyText = _cleanVisibleReply(replyText);

        // 工具调用可能已返回图片路径，先初始化供下方落库使用。
        // 语音模态处理：TTS 生成改为后台执行，绝不阻塞文本回复，
        // 否则 TTS 请求最长 20 秒会卡死整个发送链路，导致"发送没反应/无气泡"。
        final ts = DateTime.now().millisecondsSinceEpoch;
        final msgId = 'msg_a_${ts + 1}';
        Map<String, dynamic>? sticker;
        if (persistResponse &&
            await db.getKV('bot_stickers_enabled') == 'true') {
          final chance =
              (int.tryParse(await db.getKV('bot_sticker_chance') ?? '') ?? 50)
                  .clamp(1, 100);
          if (Random().nextInt(100) < chance) {
            final candidates = await db.queryStickers(emotion: mood);
            final available =
                candidates.isEmpty ? await db.queryStickers() : candidates;
            if (available.isNotEmpty) {
              sticker = available[Random().nextInt(available.length)];
            }
          }
        }
        if (persistResponse) {
          await db.insertChatMessage({
            'id': msgId,
            'bot_id': botId,
            'role': 'assistant',
            'type': 'text',
            'content': replyText,
            'file_path': null,
            'mood': mood,
            'sources_json':
                searchSources.isEmpty ? null : jsonEncode(searchSources),
            'timestamp': ts + 1
          });
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
              'id': 'msg_s_${ts + 3}',
              'bot_id': botId,
              'role': 'assistant',
              'type': 'sticker',
              // emotion 是素材匹配元数据，不保存为可见聊天正文。
              'content': '',
              'file_path': sticker['file_path']?.toString(),
              'mood': mood,
              'timestamp': ts + 3,
            });
          }

          final ttsModel = bot['tts_model'];
          if (ttsModel != null && ttsModel.toString().isNotEmpty) {
            // fire-and-forget：后台生成语音，成功后单独把该气泡升级为 audio 类型（replace 覆盖同 id）
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
      return {
        'error': '网络连接失败：请检查网络、Base URL 和服务端状态',
        'error_log': e.toString(),
        'error_code': 'network',
      };
    }
  }

  String _cleanVisibleReply(String raw) {
    // 部分模型以 DSML/XML 文本模拟工具调用；这是内部协议，绝不能进入消息气泡。
    final withoutDsml = raw
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
    return withoutDsml
        .replaceAll(RegExp(r'\[心情\s*:\s*[^\]]*\]'), '')
        .replaceAll(RegExp(r'\[发送时间\s*：[^\]]*\]'), '')
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

  /// Transcribes an audio file through an OpenAI-compatible provider selected

  /// in the bot's STT setting. Returns null for missing configuration, unsupported
  /// providers, or request failures so callers can preserve the original recording.
  Future<String?> transcribeAudio({
    required String botId,
    required String audioPath,
  }) async {
    try {
      final bot = await DBManager().getBotById(botId);
      final prefs = await SharedPreferences.getInstance();
      // STT selection is currently persisted per bot in preferences by the
      // model settings page; keep the database field as a compatibility fallback.
      final providerId = (prefs.getString('stt_model_$botId') ??
              bot?['stt_model']?.toString() ??
              '')
          .trim();
      if (providerId.isEmpty || !await File(audioPath).exists()) return null;

      final provider = await DBManager().getChatProviderById(providerId);
      if (provider == null) return null;
      final baseUrl = provider['base_url']
              ?.toString()
              .trim()
              .replaceFirst(RegExp(r'/+$'), '') ??
          '';
      final model = provider['model']?.toString().split(',').first.trim() ?? '';
      if (baseUrl.isEmpty || model.isEmpty) return null;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/audio/transcriptions'),
      )
        ..headers['Authorization'] = 'Bearer ${provider['api_key']}'
        ..fields['model'] = model
        ..fields['response_format'] = 'json'
        ..files.add(await http.MultipartFile.fromPath('file', audioPath));
      final streamed =
          await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final text = decoded is Map ? decoded['text']?.toString().trim() : null;
      return text == null || text.isEmpty ? null : text;
    } catch (e) {
      print('[stt] transcription failed: $e');
      return null;
    }
  }

  // 特异化 TTS 处理 (兼容标准协议与阿里云百炼特异 Payload)
  Future<String?> _generateTTS(String text, String providerId) async {
    // TTS provider 独立存放于 tts_provider_list，用 id 前缀 ts_ 标识，含 voice 音色字段
    final list = await DBManager().queryTtsProviders();
    Map<String, dynamic>? provider;
    try {
      provider = list.firstWhere((p) => p['id'] == providerId);
    } catch (_) {}
    if (provider == null) return null;

    final String voice = (provider['voice'] as String? ?? '').trim().isEmpty
        ? 'alloy'
        : (provider['voice'] as String?).toString();
    try {
      http.Response res;
      final modelName = (provider['model'] as String? ?? '').trim();
      final modelForUrl =
          modelName.isEmpty ? provider['name'].toString() : modelName;

      if (provider['base_url'].toString().contains('dashscope')) {
        res = await http
            .post(
              Uri.parse(
                  "https://dashscope.aliyuncs.com/api/v1/services/audio/tts/text-to-wav"),
              headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer ${provider['api_key']}"
              },
              body: jsonEncode({
                "model": modelForUrl,
                "input": {"text": text},
                "parameters": {"format": "wav"}
              }),
            )
            .timeout(const Duration(seconds: 20));
      } else {
        res = await http
            .post(
              Uri.parse("${provider['base_url']}/audio/speech"),
              headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer ${provider['api_key']}"
              },
              body: jsonEncode(
                  {"model": modelName, "input": text, "voice": voice}),
            )
            .timeout(const Duration(seconds: 20));
      }

      if (res.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final path =
            '${directory.path}/tide_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
        await File(path).writeAsBytes(res.bodyBytes);
        return path;
      }
    } catch (e) {
      print("TTS Error: $e");
    }
    return null;
  }

  /// Compresses older ordinary chat into first-person diary entries.
  /// It runs in the background so a normal reply is never delayed.
  ///
  /// 机器人的记忆是"第一人称日记"，不是对话摘要（不写"本次对话讨论了..."）。
  /// 模型须返回 JSON 数组，每一条是机器人第一人称记录的真实事件/感受的简短句子，
  /// 且每条都是独立条目（无标题、不合并成一段长文），由应用端逐条落库到 medium。
  Future<void> _summarizeHistoryIfNeeded({
    required Map<String, dynamic> bot,
    required String botId,
    required Map<String, dynamic> provider,
    required String modelName,
    required List<Map<String, dynamic>> history,
    required int maxContext,
  }) async {
    try {
      final textHistory =
          history.where((m) => m['type'] == 'text').toList(growable: false);
      final totalChars = textHistory.fold<int>(
          0, (sum, m) => sum + (m['content']?.toString().length ?? 0));
      // 在上下文接近上限前就归档，避免等到模型已被截断才尝试总结。
      final threshold = (maxContext * 3.2).floor();
      if (totalChars < threshold && textHistory.length < 16) return;

      final cutoff =
          (textHistory.length * 0.60).floor().clamp(1, textHistory.length);
      final older = textHistory.take(cutoff).toList();
      if (older.isEmpty) return;
      final endTimestamp = older.last['timestamp']?.toString() ?? '0';
      final db = DBManager();
      final summaryKey = 'memory_summary_until_$botId';
      if (await db.getKV(summaryKey) == endTimestamp) return;
      final transcript = older
          .map((m) =>
              '${m['role'] == 'user' ? '用户' : bot['name']}：${m['content']}')
          .join('\n');
      final baseUrl = (provider['base_url']?.toString().trim() ?? '')
          .replaceFirst(RegExp(r'/+$'), '');
      if (baseUrl.isEmpty) return;
      // 把所有已存的"日记"条目一并取回，连同新出现的聊天内容一起交给模型改写合并，
      // 让模型基于"已有记忆 + 新信息"输出一套全新的完整日记，而不是只按新聊天增量新增。
      final existingMemories = await db.queryMemories(botId, type: 'medium');
      final existingText = existingMemories.isEmpty
          ? '（目前还没有任何日记）'
          : existingMemories
              .map((m) => (m['content']?.toString() ?? '').trim())
              .where((c) => c.isNotEmpty)
              .join('\n');
      final userPayload = '【已有的日记】\n'
          '$existingText\n\n'
          '【新发生的聊天内容】\n'
          '$transcript';
      // 以 JSON 数组形式返回"第一人称日记条目"，杜绝把一段长总结当一个记忆。
      final response = await http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${provider['api_key']}',
            },
            body: jsonEncode({
              'model': modelName,
              'messages': [
                {
                  'role': 'system',
                  'content': '你是一个机器人，正在维护自己的"日记"（记忆库）。已有的日记里记录了过去的真实事件与感受，新发生的聊天内容里可能有新的值得记住的信息。'
                      '请以机器人的第一人称（用"我"）把【已有日记】和【新发生的聊天内容】合并整理成一份全新的完整日记。要求：\n'
                      '1. 直接输出一个 JSON 字符串数组，数组元素是字符串，例如 ["我记得用户的生日是5月20日", "用户最近在准备面试，我给他打气"]。\n'
                      '2. 每条都是独立条目，不要合并成长文，也不要给任何一条加标题或编号。\n'
                      '3. 保留已有日记里仍然成立的事实（可改写得更简洁、合并重复项），补充新聊天中值得记住的新内容，删除已过时或不再需要的信息。\n'
                      '4. 用第一人称书写，不要用"本次对话""讨论""用户说"这类转述口吻总结聊天过程。\n'
                      '5. 不编造，不写心情标签。若没有任何值得记住的信息，输出 []。',
                },
                {'role': 'user', 'content': userPayload},
              ],
              'max_tokens': 1200,
            }),
          )
          .timeout(const Duration(seconds: 50));
      if (response.statusCode != 200) return;
      String bodyText = utf8.decode(response.bodyBytes).trim();
      // 兼容模型把 JSON 包在 ```json ... ``` 代码块里的情况。
      final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
      final fenceMatch = fence.firstMatch(bodyText);
      if (fenceMatch != null) bodyText = fenceMatch.group(1)!.trim();
      // 提取第一个 [...] 数组片段作为条目列表。
      final arrayStart = bodyText.indexOf('[');
      final arrayEnd = bodyText.lastIndexOf(']');
      if (arrayStart < 0 || arrayEnd <= arrayStart) return;
      final List<dynamic> entries =
          jsonDecode(bodyText.substring(arrayStart, arrayEnd + 1));
      final newEntries = entries
          .map((e) => e?.toString().trim() ?? '')
          .where((c) => c.isNotEmpty)
          .toList();
      if (newEntries.isEmpty) return;
      // 先删除旧的 medium 日记，再用模型改写合并后的完整集合整体替换落库，
      // 避免日记在反复总结下无限膨胀。
      for (final old in existingMemories) {
        final id = old['id']?.toString();
        if (id != null && id.isNotEmpty) await db.deleteMemory(id);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var idx = 0; idx < newEntries.length; idx++) {
        // 拆成独立、无标题、第一人称的日记条目逐条落库到 medium。
        await db.upsertMemoryItem(
          botId: botId,
          type: 'medium',
          title: '',
          content: newEntries[idx],
          timestamp: now + idx * 1000,
        );
      }
      await db.setKV(summaryKey, endTimestamp);
    } catch (e) {
      print('[memory] auto summary failed: $e');
    }
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
            '请结合你的人设，生成一句全天通用的「今日一言」，字数严格在10到15字。它会贯穿整天展示：禁止早安、午安、晚安、早晨/中午/晚上等时间词，禁止问候和提醒当前时间，不要包含[心情]标签。',
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
    final style = await db.getKV('bot_image_style') ?? '写实';
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
              'prompt': '$prompt。画面风格：$style。',
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
      if (toolResult is Map &&
          toolResult['image_path']?.toString().isNotEmpty == true) {
        generatedImageSetter(toolResult['image_path'].toString());
      }
      messages.add({
        'role': 'tool',
        'tool_call_id': call['id']?.toString() ?? '',
        'content': jsonEncode(result['result'] ?? result),
      });
    }
    // follow-up：把工具结果回传模型，取得最终自然语言回复。
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
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (followUp.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(followUp.bodyBytes));
      final next =
          decoded['choices']?[0]?['message']?['content']?.toString() ?? '';
      if (next.isNotEmpty) {
        replyTextCallback(next);
        onDelta?.call(next);
      }
      final fu = decoded['usage'];
      if (fu is Map) usageCallback(fu);
    }
  }

  Future<List<Map<String, dynamic>>> _buildNativeTools(DBManager db) async {
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
    if (await db.getKV('bot_stickers_enabled') == 'true' &&
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
    return tools;
  }

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
      final prompt = args['prompt']?.toString().trim() ?? '';
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
    if (name == 'send_sticker') {
      final emotion = args['emotion']?.toString().trim() ?? '';
      final candidates = await db.queryStickers(emotion: emotion);
      final available =
          candidates.isEmpty ? await db.queryStickers() : candidates;
      return {
        'result': {
          'ok': available.isNotEmpty,
          'message': available.isEmpty ? '没有可用表情包。' : '表情包已选定。',
        }
      };
    }
    return {
      'result': {'ok': false, 'error': '未知工具：$name'}
    };
  }

  Future<String> _buildToolContext(DBManager db) async {
    final parts = <String>[];
    if (await db.getKV('bot_image_generation_enabled') != 'false') {
      final style = await db.getKV('bot_image_style') ?? '写实';
      parts.add(
          '【已授权工具：生图】当用户明确需要图片时，可建议使用生图；所有图片必须采用“$style”风格。不要声称已生成不存在的图片。');
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
    if (await db.getKV('bot_stickers_enabled') == 'true') {
      final emotions = await db.stickerEmotions();
      if (emotions.isNotEmpty) {
        parts.add(
            '【已授权工具：表情包】现有情绪分类：${emotions.join('、')}。若要在回复时附带表情包，必须在回复末尾另起一行单独输出机器指令 [表情包:情绪]，只能选择上列情绪之一，不能虚构素材。该指令是内部协议，绝不能在聊天正文里写出"表情包"、"表情包类型"、"type"等字样。');
      }
    }
    return parts.isEmpty ? '' : '\n${parts.join('\n')}';
  }

  // 构建核心防御护栏与游戏机制注入
  String _buildSystemPrompt(Map<String, dynamic> bot, String? activeGame) {
    String p =
        "你的名字是${bot['name']}。\n身世与设定:${bot['desc']}\n说话方式指令:${bot['prompt']}\n"
        "【底层强制核心规则】: 你必须在每次回复的最开头，输出当前的心情标签，格式只能是[心情:开心]、[心情:伤心]、[心情:生气]、[心情:平静]四个中的一个。"
        "【记忆工具】：如果你从用户的话里捕捉到值得记住的确定信息，请在本条回复末尾另起一行输出机器指令。\n"
        "- 稳定的长期信息（用户的名字、喜好、身份、你们的关系状态、对我的称呼、我对自我的认识等）用 [记忆:长期|内容]，例如 [记忆:长期|我记得用户的名字是李小明]。\n"
        "- 近期发生过的事件/感受（用第一人称写的日记式短句）用 [记忆:内容]，例如 [记忆:今天我们一起去公园散步了]。\n"
        "一条记忆一个标签，多条则连续输出；内容务必用第一人称（以“我”的口吻）。该指令是内部协议，绝不能出现在发给用户的可见正文里，也绝不能把“记忆”字样泄露给用户。";

    if (activeGame == 'poker') {
      p +=
          "\n【系统级游戏劫持】：你当前正在和用户玩双人扑克牌。规则极度严格：牌组仅限 3~10，共32张，没有大小王。每人随机发16张牌。正常的算力对战（单张、对子、三带一、顺子、炸弹）。绝对不可向用户透露你手中的底牌！你需要在每次闲聊中推进游戏局势并描述你出的牌。";
    } else if (activeGame == '20q') {
      p +=
          "\n【系统级游戏劫持】：你当前正在玩 20 问猜物游戏。如果用户是出题人，你只能问 20 个问题，且必须根据用户的“是”或“否”推断出答案；如果你是出题人，你只能回答“是”或“否”。在 20 问内未能猜出则判定输。";
    } else if (activeGame == 'gomoku') {
      p +=
          "\n【游戏规则】：你正与用户真实进行 9×9 五子棋。用户会给出自己的坐标；请选择一个未占用坐标，并在回复最开头紧接心情标签后输出唯一机器可读指令 [落子:行,列]（行列范围 1-9）。不得输出不存在的落子，不得跳过回合；再简短聊天。";
    } else if (activeGame == 'tic_tac_toe') {
      p +=
          "\n【游戏规则】：你正与用户真实进行 3×3 井字棋。用户会给出自己的坐标；请选择一个未占用坐标，并在回复最开头紧接心情标签后输出唯一机器可读指令 [落子:行,列]（行列范围 1-3）。不得输出不存在的落子，不得跳过回合；再简短聊天。";
    }
    return p;
  }

  String _extractMood(String text) {
    if (text.contains('[心情:开心]')) return '开心';
    if (text.contains('[心情:伤心]')) return '伤心';
    if (text.contains('[心情:生气]')) return '生气';
    return '平静';
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
        if (content.isEmpty) continue;
        // 强制第一人称：以“我”开头，避免出现像“用户叫xxx”这类第三人称口吻。
        if (!RegExp(r'^(我|我记得|我知道|我了解到|用户告诉我|用户说过|用户是|我的|今天|昨天|我们)',
                caseSensitive: false)
            .hasMatch(content)) {
          content = '我记得$content';
        }
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
}
