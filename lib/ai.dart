import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  Future<Map<String, dynamic>> sendMessage({
    required String botId,
    required String text,
    String? imagePath,
    String? activeGame, // 支持动态注入游戏规则
    bool persistResponse = true,
    bool includeChatHistory = true,
    bool enableAutoSummary = true,
    void Function(String delta)? onDelta,
  }) async {
    final db = DBManager();
    // 数据库初始化异常/卡住时必须尽快回到聊天室 finally，不能无限显示“正在输入中”。
    final bots = await db.getAllBots().timeout(const Duration(seconds: 8));

    final bot = bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
    if (bot.isEmpty) return {'error': '系统异常：生命体档案丢失'};

    // 已选择本地 GGUF 时，绕过远程 provider，执行真实 llama.cpp 推理。
    final prefs = await SharedPreferences.getInstance();
    final localId = (prefs.getString('local_chat_model_$botId') ?? '').trim();
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
        final reply = await LocalLlama.instance.generate(
          path: path,
          messages: localMessages,
        );
        return {'success': true, 'reply': reply, 'local': true};
      } catch (e, st) {
        return {
          'error': '本地模型推理失败：$e',
          'error_code': 'local_inference',
          'error_log': '$e\n$st',
        };
      }
    }

    // 提取该 bot 配置的 provider id（存在 bots.chat_model 字段，由聊天室设置弹窗写入）
    final providerId = bot['chat_model'];
    if (providerId == null || providerId.toString().isEmpty)
      return {'error': '未配置引擎中枢，请先在聊天页设置模型'};
    // 优先用统一的聊天链路读取，兼容 API 设置页的 provider_list
    final provider = await db.getChatProviderById(providerId.toString());
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
    final mediumMemories = activeGame == null
        ? await db.queryMemories(botId, type: 'medium', limit: 3)
        : <Map<String, dynamic>>[];
    final memoryContext = mediumMemories
        .map((m) => m['content']?.toString().trim() ?? '')
        .where((content) => content.isNotEmpty)
        .join('\n');
    final systemPrompt = _buildSystemPrompt(bot, activeGame) +
        (memoryContext.isEmpty ? '' : '\n【已整理的中期记忆，仅在相关时参考】\n$memoryContext');
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    final historyMessages = <Map<String, dynamic>>[];
    var usedChars = 0;
    final charBudget = (maxContext * 3.2).floor();
    for (final msg in history.reversed) {
      if (msg['type'] != 'text') continue;
      final content = msg['content']?.toString() ?? '';
      if (content.isEmpty) continue;
      if (usedChars + content.length > charBudget &&
          historyMessages.isNotEmpty) {
        break;
      }
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
      final payload = {
        'model': modelName,
        'messages': messages,
        'max_tokens': bot['max_tokens'] ?? 10000,
        if (onDelta != null) 'stream': true,
      };
      String replyText = '';
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
                    event['choices']?[0]?['delta']?['content']?.toString() ??
                        '';
                if (delta.isNotEmpty) {
                  replyText += delta;
                  onDelta(delta);
                }
                if (event['usage'] is Map) usage = event['usage'] as Map;
              } catch (_) {}
            });
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
          replyText =
              json['choices']?[0]?['message']?['content']?.toString() ?? '';
          usage = json['usage'] is Map ? json['usage'] as Map : const {};
        }
      }
      print('[ai] response status=$statusCode');
      if (statusCode == 200) {
        final promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ??
            (messages.fold<int>(
                        0,
                        (sum, m) =>
                            sum + (m['content']?.toString().length ?? 0)) /
                    3.2)
                .ceil();
        final completionTokens =
            (usage['completion_tokens'] as num?)?.toInt() ??
                (replyText.length / 3.2).ceil();
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

        // 情绪提取器：解析并剔除底层情绪标签
        String mood = _extractMood(replyText);
        replyText = replyText.replaceAll(RegExp(r'\[心情:.*?\]'), '').trim();

        // 语音模态处理：TTS 生成改为后台执行，绝不阻塞文本回复，
        // 否则 TTS 请求最长 20 秒会卡死整个发送链路，导致"发送没反应/无气泡"。
        final ts = DateTime.now().millisecondsSinceEpoch;
        final msgId = 'msg_a_${ts + 1}';
        if (persistResponse) {
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
                    'timestamp': ts + 1,
                  });
                } catch (_) {}
              }
            }());
          }
        }
        return {'success': true, 'reply': replyText, 'message_id': msgId};
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

  /// Compresses older ordinary chat into a reviewable medium-term memory.
  /// It runs in the background so a normal reply is never delayed.
  Future<void> _summarizeHistoryIfNeeded({
    required Map<String, dynamic> bot,
    required String botId,
    required Map<String, dynamic> provider,
    required String modelName,
    required List<Map<String, dynamic>> history,
    required int maxContext,
  }) async {
    try {
      final totalChars = history.where((m) => m['type'] == 'text').fold<int>(
          0, (sum, m) => sum + (m['content']?.toString().length ?? 0));
      final threshold = (maxContext * 3.2 * 0.9).floor();
      if (totalChars < threshold || history.length < 8) return;

      final cutoff = (history.length * 0.65).floor();
      final older =
          history.take(cutoff).where((m) => m['type'] == 'text').toList();
      if (older.isEmpty) return;
      final endTimestamp = older.last['timestamp']?.toString() ?? '0';
      final db = DBManager();
      final summaryKey = 'memory_summary_until_$botId';
      if (await db.getKV(summaryKey) == endTimestamp) return;
      final transcript = older
          .map((m) =>
              '${m['role'] == 'user' ? '用户' : bot['name']}：${m['content']}')
          .join('\n');
      final baseUrl = provider['base_url']
              ?.toString()
              .trim()
              .replaceFirst(RegExp(r'/+$'), '') ??
          '';
      if (baseUrl.isEmpty) return;
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
                  'content':
                      '将以下聊天压缩为可供未来对话参考的中期记忆。保留用户偏好、关系进展、已确认事实、未完成事项；不要编造，不要写心情标签，使用简洁中文要点。',
                },
                {'role': 'user', 'content': transcript},
              ],
              'max_tokens': 800,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final summary =
          decoded['choices']?[0]?['message']?['content']?.toString().trim() ??
              '';
      if (summary.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insertMemory({
        'id': 'summary_${botId}_$endTimestamp',
        'bot_id': botId,
        'title': '对话摘要 ${DateTime.now().toString().substring(0, 10)}',
        'type': 'medium',
        'content': summary,
        'timestamp': now,
      });
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

    // 暗中调用 AI 引擎生成，但不暴露在聊天历史中
    final res = await sendMessage(
        botId: botId,
        text: "请结合你的人设，生成一句今天的早安问候或感悟，字数严格在10到15字，不要废话，不要包含[心情]标签。");
    if (res['success'] == true) {
      final quote = res['reply']?.toString().trim() ?? '';
      // sendMessage persists its assistant reply. Remove only that generated
      // reply; never delete a real user message from the conversation.
      final history = await db.getChatHistory(botId);
      if (history.isNotEmpty && history.last['role'] == 'assistant') {
        await db.deleteMessage(history.last['id']);
      }
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
      if (res.statusCode == 200)
        return {
          'success': true,
          'delay': DateTime.now().difference(start).inMilliseconds
        };
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

  // 构建核心防御护栏与游戏机制注入
  String _buildSystemPrompt(Map<String, dynamic> bot, String? activeGame) {
    String p =
        "你的名字是${bot['name']}。\n身世与设定:${bot['desc']}\n说话方式指令:${bot['prompt']}\n"
        "【底层强制核心规则】: 你必须在每次回复的最开头，输出当前的心情标签，格式只能是[心情:开心]、[心情:伤心]、[心情:生气]、[心情:平静]四个中的一个。";

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
}
