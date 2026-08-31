import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'ai.dart';
import 'app_log_service.dart';
import 'message_delivery_service.dart';
import 'db.dart';
import 'bot_state.dart';

/// A small OpenAI-compatible LAN gateway backed by one TideBot persona.
/// It exposes the standard models and chat completions endpoints.
class ExternalApiService {
  ExternalApiService._();
  static final instance = ExternalApiService._();
  static const _maxRequestsPerMinute = 30;
  static const _maxTrackedClients = 256;

  HttpServer? _server;
  final Map<String, List<DateTime>> _recentRequests = {};
  int? get activePort => _server?.port;
  bool get running => _server != null;

  /// The LAN address is device-dependent. `anyIPv4` makes the server listen on
  /// every interface, while clients must use a concrete private IPv4 address.
  Future<List<String>> baseUrls({int? port}) async {
    final effectivePort = port ?? _server?.port ?? 6666;
    final addresses = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
            addresses.add('http://${address.address}:$effectivePort/v1');
          }
        }
      }
    } catch (_) {}
    return addresses.toList()..sort();
  }

  Future<String> preferredBaseUrl({int? port}) async {
    final urls = await baseUrls(port: port);
    final selected = await DBManager().getKV('external_api_base_url') ?? '';
    if (urls.contains(selected)) return selected;
    return urls.isNotEmpty
        ? urls.first
        : 'http://127.0.0.1:${port ?? _server?.port ?? 6666}/v1';
  }

  Future<void> setPreferredBaseUrl(String url) async {
    final urls = await baseUrls();
    if (!urls.contains(url)) throw ArgumentError.value(url, 'url', '不是当前可用地址');
    await DBManager().setKV('external_api_base_url', url);
  }

  Future<Map<String, dynamic>?> _boundBot(DBManager db) async {
    final botId = await db.getKV('external_api_bot_id') ?? '';
    if (botId.isEmpty) return null;
    final bot = await db.getBotById(botId);
    if (bot == null) return null;
    if (isBotDisabled(bot['is_disabled'])) return null;
    return bot;
  }

  Future<bool> start() async {
    if (_server != null) return true;
    final db = DBManager();
    final enabled = await db.getKV('external_api_enabled') == 'true';
    if (!enabled) return false;
    final bot = await _boundBot(db);
    if (bot == null) {
      AppLogService.instance.add('EXTERNAL_API', '外部访问服务未启动：未绑定可用机器人');
      return false;
    }
    var requested =
        int.tryParse(await db.getKV('external_api_port') ?? '') ?? 6666;
    requested = requested.clamp(1024, 65535);
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, requested,
          shared: true);
    } on SocketException catch (error) {
      AppLogService.instance
          .add('EXTERNAL_API', '外部访问服务启动失败：端口 $requested 不可用：$error');
      return false;
    }
    await db.setKV('external_api_port', '${_server!.port}');
    unawaited(_listen(_server!));
    AppLogService.instance
        .add('EXTERNAL_API', '外部访问服务已启动：http://0.0.0.0:${_server!.port}/v1');
    return true;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
    AppLogService.instance.add('EXTERNAL_API', '外部访问服务已停止');
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> _listen(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final requestLabel =
        '${request.method} ${request.uri.path} from ${request.connectionInfo?.remoteAddress.address ?? 'unknown'}';
    try {
      if (request.method == 'OPTIONS') {
        _json(request, 204, const {});
        return;
      }
      if (!_allowRequest(request)) {
        return _json(request, 429, {
          'error': {
            'message': 'Rate limit exceeded',
            'type': 'rate_limit_error',
            'code': 'rate_limit_exceeded',
          }
        });
      }
      AppLogService.instance.add('EXTERNAL_API', requestLabel);
      final db = DBManager();
      final expected = (await db.getKV('external_api_key') ?? '').trim();
      if (expected.isEmpty) {
        return _json(request, 503, {
          'error': {
            'message': 'External API key is not configured',
            'type': 'configuration_error'
          }
        });
      }
      final authorization =
          request.headers.value(HttpHeaders.authorizationHeader) ?? '';
      final supplied = authorization.startsWith('Bearer ')
          ? authorization.substring(7).trim()
          : request.uri.queryParameters['api_key'] ?? '';
      if (supplied != expected) {
        return _json(request, 401, {
          'error': {
            'message': 'Invalid API key',
            'type': 'authentication_error'
          }
        });
      }
      if (request.method == 'GET' && request.uri.path == '/v1/models') {
        final botId = await db.getKV('external_api_bot_id') ?? '';
        final bot = botId.isEmpty ? null : await db.getBotById(botId);
        if (bot == null) return _error(request, 400, '未选择可用机器人');
        return _json(request, 200, {
          'object': 'list',
          'data': [
            {
              'id': _modelId(bot),
              'object': 'model',
              'owned_by': 'tidebot',
            }
          ]
        });
      }
      if (request.method == 'POST' &&
          request.uri.path == '/v1/chat/completions') {
        final body = await utf8.decoder
            .bind(request)
            .join()
            .timeout(const Duration(seconds: 15));
        if (body.length > 2 * 1024 * 1024) {
          return _error(request, 413, '请求体超过 2 MB 限制');
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map) return _error(request, 400, '请求体必须是 JSON 对象');
        final stream = decoded['stream'] == true;
        final botId = await db.getKV('external_api_bot_id') ?? '';
        final bot = botId.isEmpty ? null : await db.getBotById(botId);
        if (bot == null) return _error(request, 400, '未选择可用机器人');
        final disabled = isBotDisabled(bot['is_disabled']);
        AppLogService.instance.add(
          'EXTERNAL_API',
          '已选择机器人 ${bot['id'] ?? botId}，is_disabled=${bot['is_disabled']}，标准化禁用状态=$disabled',
        );
        if (disabled) {
          return _error(request, 403, '所选机器人已禁用');
        }
        final messages = decoded['messages'];
        if (messages is! List || messages.isEmpty) {
          return _error(request, 400, 'messages 不能为空');
        }
        final normalized = _normalizeMessages(messages);
        if (normalized == null || normalized.isEmpty) {
          return _error(request, 400, 'messages 格式无效');
        }
        final userMessages = normalized
            .where((item) => item['role'] == 'user')
            .toList(growable: false);
        if (userMessages.isEmpty) {
          return _error(request, 400, 'messages 必须包含 user 消息');
        }
        final latestUser = userMessages.last;
        final text = latestUser['text']?.toString().trim() ?? '';
        final imagePaths = <String>[];
        for (final image in latestUser['images'] as List<dynamic>) {
          final path = await _materializeImage(image.toString());
          if (path == null) {
            return _error(request, 400, '图片地址无效、无法下载或超过 8 MB');
          }
          imagePaths.add(path);
        }
        if (text.isEmpty && imagePaths.isEmpty) {
          return _error(request, 400, 'user 消息必须包含文本或图片');
        }
        final priorTurns = normalized.length > 1
            ? normalized
                .take(normalized.length - 1)
                .map((item) => '${item['role']}: ${item['text']}')
                .where((line) => line.split(': ').last.trim().isNotEmpty)
                .join('\n')
            : '';
        final prompt = priorTurns.isEmpty
            ? text
            : '以下是外部客户端提供的对话上下文，请保持角色和语义连续：\n$priorTurns\n\nuser: $text';
        final sync = await db.getKV('external_api_sync_messages') != 'false';
        // Inbound platform traffic is persisted as a normal TideBot turn.
        // App-originated messages never enter this HTTP handler, so they are
        // not echoed back to external platforms.
        if (sync) {
          final now = DateTime.now().millisecondsSinceEpoch;
          await MessageDeliveryService.instance.insert({
            'id': 'external_u_$now',
            'bot_id': botId,
            'role': 'user',
            'type': 'text',
            'content': text,
            'file_path': null,
            'timestamp': now,
          });
        }
        AppLogService.instance.add('EXTERNAL_API',
            '已桥接入站消息至 ${bot['name'] ?? botId}，同步记录=${sync ? '开启' : '关闭'}');
        final cancellationToken = AICancellationToken();
        // A closed response is the only lifecycle signal exposed by dart:io's
        // server response. It also protects long-running upstream work when the
        // handler is terminated before it can write the completion.
        unawaited(request.response.done.whenComplete(cancellationToken.cancel));
        final result = await AIManager().sendMessage(
          botId: botId,
          text: prompt,
          imagePaths: imagePaths,
          persistResponse: sync,
          includeChatHistory: sync,
          cancellationToken: cancellationToken,
        );
        cancellationToken.throwIfCancelled();
        if (result['success'] != true) {
          return _error(
              request, 502, result['error']?.toString() ?? 'TideBot 上游模型请求失败');
        }
        final reply = result['reply']?.toString() ?? '';
        final rawUsage = result['usage'];
        final usage = rawUsage is Map
            ? {
                'prompt_tokens':
                    (rawUsage['prompt_tokens'] as num?)?.toInt() ?? 0,
                'completion_tokens':
                    (rawUsage['completion_tokens'] as num?)?.toInt() ?? 0,
                'total_tokens':
                    (rawUsage['total_tokens'] as num?)?.toInt() ?? 0,
              }
            : <String, int>{};
        AppLogService.instance
            .add('EXTERNAL_API', '桥接完成，已将 TideBot 回复返回调用方（${reply.length} 字）');
        if (stream) {
          final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final id = 'chatcmpl-tidebot-$created';
          await _writeSse(request, {
            'id': id,
            'object': 'chat.completion.chunk',
            'created': created,
            'model': _modelId(bot),
            'choices': [
              {
                'index': 0,
                'delta': {'role': 'assistant'},
                'finish_reason': null,
              }
            ],
          });
          if (reply.isNotEmpty) {
            await _writeSse(request, {
              'id': id,
              'object': 'chat.completion.chunk',
              'created': created,
              'model': _modelId(bot),
              'choices': [
                {
                  'index': 0,
                  'delta': {'content': reply},
                  'finish_reason': null,
                }
              ],
            });
          }
          await _writeSse(request, {
            'id': id,
            'object': 'chat.completion.chunk',
            'created': created,
            'model': _modelId(bot),
            'choices': [
              {'index': 0, 'delta': {}, 'finish_reason': 'stop'}
            ],
            if (usage.isNotEmpty) 'usage': usage,
          });
          return _finishSse(request);
        }
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        return _json(request, 200, {
          'id': 'chatcmpl-tidebot-$now',
          'object': 'chat.completion',
          'created': now,
          'model': _modelId(bot),
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': reply},
              'finish_reason': 'stop'
            }
          ],
          if (usage.isNotEmpty) 'usage': usage,
        });
      }
      _error(request, 404, 'Not found');
    } on AICancelledException {
      AppLogService.instance.add('EXTERNAL_API', '客户端已断开，已取消上游模型请求');
      return;
    } catch (error) {
      AppLogService.instance.add('EXTERNAL_API', '请求处理失败：$error');
      try {
        _error(request, 500, 'Internal server error');
      } catch (_) {
        // The peer may have closed the response while upstream work was running.
      }
    }
  }

  List<Map<String, dynamic>>? _normalizeMessages(List<dynamic> raw) {
    final normalized = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) return null;
      final role = item['role']?.toString().trim() ?? '';
      if (!const {'system', 'user', 'assistant', 'tool'}.contains(role)) {
        return null;
      }
      final textParts = <String>[];
      final images = <String>[];
      final content = item['content'];
      if (content is String) {
        textParts.add(content);
      } else if (content is List) {
        for (final part in content) {
          if (part is! Map) return null;
          switch (part['type']?.toString()) {
            case 'text':
              final value = part['text']?.toString() ?? '';
              if (value.isNotEmpty) textParts.add(value);
            case 'image_url':
              final image = part['image_url'];
              final url = image is Map ? image['url'] : image;
              if (url?.toString().trim().isNotEmpty == true) {
                images.add(url.toString().trim());
              }
            default:
              return null;
          }
        }
      } else if (content != null) {
        return null;
      }
      normalized.add({
        'role': role,
        'text': textParts.join(),
        'images': images,
      });
    }
    return normalized;
  }

  Future<String?> _materializeImage(String source) async {
    try {
      final bytes = source.startsWith('data:')
          ? _decodeDataUri(source)
          : await _downloadImage(source);
      if (bytes == null || bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
        return null;
      }
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/external_api_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (error) {
      AppLogService.instance.add('EXTERNAL_API', '多模态图片处理失败：$error');
      return null;
    }
  }

  Uint8List? _decodeDataUri(String source) {
    final comma = source.indexOf(',');
    if (comma < 0) return null;
    final metadata = source.substring(5, comma).toLowerCase();
    if (!metadata.contains(';base64')) return null;
    return Uint8List.fromList(base64Decode(source.substring(comma + 1)));
  }

  Future<Uint8List?> _downloadImage(String source) async {
    final uri = Uri.tryParse(source);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final declared = response.headers['content-length'];
    if (declared != null &&
        int.tryParse(declared) != null &&
        int.parse(declared) > 8 * 1024 * 1024) {
      return null;
    }
    return response.bodyBytes;
  }

  Future<void> _writeSse(
      HttpRequest request, Map<String, dynamic> payload) async {
    final response = request.response;
    response.headers.contentType =
        ContentType('text', 'event-stream', charset: 'utf-8');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    response.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.write('data: ${jsonEncode(payload)}\n\n');
    await response.flush();
  }

  Future<void> _finishSse(HttpRequest request) async {
    request.response.write('data: [DONE]\n\n');
    await request.response.close();
  }

  String _modelId(Map<String, dynamic> bot) {
    final name = bot['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'tidebot' : name;
  }

  bool _allowRequest(HttpRequest request) {
    final client = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 1));
    _recentRequests.removeWhere((_, timestamps) {
      timestamps.removeWhere((timestamp) => timestamp.isBefore(cutoff));
      return timestamps.isEmpty;
    });
    if (_recentRequests.length >= _maxTrackedClients &&
        !_recentRequests.containsKey(client)) {
      return false;
    }
    final timestamps = _recentRequests.putIfAbsent(client, () => <DateTime>[]);
    if (timestamps.length >= _maxRequestsPerMinute) return false;
    timestamps.add(now);
    return true;
  }

  void _error(HttpRequest request, int code, String message) =>
      _json(request, code, {
        'error': {'message': message, 'type': 'invalid_request_error'}
      });

  void _json(HttpRequest request, int code, Map<String, dynamic> body) {
    request.response.statusCode = code;
    request.response.headers.contentType = ContentType.json;
    request.response.headers
        .set(HttpHeaders.accessControlAllowOriginHeader, '*');
    request.response.write(jsonEncode(body));
    request.response.close();
  }
}
