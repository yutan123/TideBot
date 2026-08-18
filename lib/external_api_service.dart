import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai.dart';
import 'app_log_service.dart';
import 'db.dart';

/// A small OpenAI-compatible LAN gateway backed by one TideBot persona.
/// It deliberately exposes only models and non-streaming chat completions.
class ExternalApiService {
  ExternalApiService._();
  static final instance = ExternalApiService._();

  HttpServer? _server;
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

  Future<bool> start() async {
    if (_server != null) return true;
    final db = DBManager();
    final enabled = await db.getKV('external_api_enabled') == 'true';
    if (!enabled) return false;
    var requested =
        int.tryParse(await db.getKV('external_api_port') ?? '') ?? 6666;
    requested = requested.clamp(1024, 65535);
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, requested,
          shared: true);
    } on SocketException {
      try {
        _server =
            await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
      } on SocketException catch (error) {
        AppLogService.instance.add('EXTERNAL_API', '外部访问服务启动失败：$error');
        return false;
      }
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
      AppLogService.instance.add('EXTERNAL_API', requestLabel);
      final db = DBManager();
      final expected = await db.getKV('external_api_key') ?? 'tidebot';
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
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body);
        if (decoded is! Map) return _error(request, 400, '请求体必须是 JSON 对象');
        if (decoded['stream'] == true) {
          return _error(request, 400, '外部访问服务暂不支持 stream=true，请使用非流式请求');
        }
        final botId = await db.getKV('external_api_bot_id') ?? '';
        final bot = botId.isEmpty ? null : await db.getBotById(botId);
        if (bot == null) return _error(request, 400, '未选择可用机器人');
        if (bot['is_disabled'] == 1 || bot['is_disabled'] == true) {
          return _error(request, 403, '所选机器人已禁用');
        }
        final messages = decoded['messages'];
        if (messages is! List || messages.isEmpty) {
          return _error(request, 400, 'messages 不能为空');
        }
        String text = '';
        for (final item in messages.reversed) {
          if (item is! Map || item['role'] != 'user') continue;
          final content = item['content'];
          if (content is String) {
            text = content.trim();
          } else if (content is List) {
            text = content
                .whereType<Map>()
                .map((part) => part['text']?.toString() ?? '')
                .join()
                .trim();
          }
          if (text.isNotEmpty) break;
        }
        if (text.isEmpty) return _error(request, 400, '未找到 user 文本消息');
        final sync = await db.getKV('external_api_sync_messages') != 'false';
        // Inbound platform traffic is persisted as a normal TideBot turn.
        // App-originated messages never enter this HTTP handler, so they are
        // not echoed back to external platforms.
        if (sync) {
          final now = DateTime.now().millisecondsSinceEpoch;
          await db.insertMessage({
            'id': 'external_u_$now',
            'bot_id': botId,
            'role': 'user',
            'type': 'text',
            'content': text,
            'file_path': null,
            'timestamp': now,
          });
        }
        final result = await AIManager().sendMessage(
          botId: botId,
          text: text,
          persistResponse: sync,
          includeChatHistory: sync,
        );
        if (result['success'] != true) {
          return _error(
              request, 502, result['error']?.toString() ?? 'TideBot 上游模型请求失败');
        }
        final reply = result['reply']?.toString() ?? '';
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
          ]
        });
      }
      _error(request, 404, 'Not found');
    } catch (error) {
      AppLogService.instance.add('EXTERNAL_API', '请求处理失败：$error');
      _error(request, 500, 'Internal server error');
    }
  }

  String _modelId(Map<String, dynamic> bot) {
    final name = bot['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'tidebot' : name;
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
