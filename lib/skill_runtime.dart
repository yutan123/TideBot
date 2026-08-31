import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class SkillValidationResult {
  final Map<String, dynamic>? manifest;
  final String? error;

  const SkillValidationResult({this.manifest, this.error});
  bool get isValid => manifest != null && error == null;
}

class TideSkillValidator {
  static const executors = {'native', 'http', 'mcp_proxy', 'prompt'};
  static const supportedApiVersions = {'1'};
  static const supportedPermissions = {
    'network',
    'mcp',
    'prompt',
    'native',
  };

  static SkillValidationResult validate(dynamic raw) {
    if (raw is! Map) {
      return const SkillValidationResult(error: 'manifest 必须是 JSON 对象');
    }
    final manifest = Map<String, dynamic>.from(raw);
    for (final key in const ['id', 'name', 'version', 'tools']) {
      if (manifest[key] == null || manifest[key].toString().trim().isEmpty) {
        return SkillValidationResult(error: '缺少 manifest.$key');
      }
    }
    final id = manifest['id'].toString().trim();
    if (!RegExp(r'^[a-zA-Z0-9._-]{1,80}$').hasMatch(id)) {
      return const SkillValidationResult(error: 'Skill id 格式无效');
    }
    final apiVersion = manifest['api_version']?.toString().trim();
    if (apiVersion != null &&
        apiVersion.isNotEmpty &&
        !supportedApiVersions.contains(apiVersion)) {
      return SkillValidationResult(
          error: '不支持的 manifest.api_version：$apiVersion');
    }
    final permissions = manifest['permissions'];
    if (permissions != null) {
      if (permissions is! List ||
          permissions.any((value) => value is! String) ||
          permissions.any((value) => !supportedPermissions.contains(value))) {
        return const SkillValidationResult(
            error: 'manifest.permissions 包含不支持的权限');
      }
    }
    final dependencies = manifest['dependencies'];
    if (dependencies != null &&
        (dependencies is! List ||
            dependencies.any((value) => value is! String))) {
      return const SkillValidationResult(
          error: 'manifest.dependencies 必须是字符串数组');
    }
    final signature = manifest['signature'];
    if (signature != null &&
        (signature is! Map ||
            signature['algorithm']?.toString() != 'sha256' ||
            !RegExp(r'^[a-fA-F0-9]{64}$')
                .hasMatch(signature['value']?.toString() ?? ''))) {
      return const SkillValidationResult(error: 'manifest.signature 格式无效');
    }
    if (manifest['entry_type'] != null &&
        manifest['entry_type']?.toString() != 'manifest') {
      return const SkillValidationResult(error: '不支持的 manifest.entry_type');
    }
    if (manifest['tools'] is! List || (manifest['tools'] as List).isEmpty) {
      return const SkillValidationResult(error: 'tools 不能为空');
    }
    final names = <String>{};
    for (final item in manifest['tools'] as List) {
      if (item is! Map) {
        return const SkillValidationResult(error: '工具定义必须是对象');
      }
      final tool = Map<String, dynamic>.from(item);
      final name = tool['name']?.toString().trim() ?? '';
      final executor = tool['executor']?.toString().trim() ?? '';
      if (!RegExp(r'^[a-zA-Z0-9._-]{1,80}$').hasMatch(name) ||
          !names.add(name)) {
        return const SkillValidationResult(error: '工具名称为空、格式无效或重复');
      }
      if (!executors.contains(executor)) {
        return SkillValidationResult(error: '不支持执行器：$executor');
      }
      final requiredPermission = switch (executor) {
        'http' => 'network',
        'mcp_proxy' => 'mcp',
        'prompt' => 'prompt',
        'native' => 'native',
        _ => '',
      };
      final declaredPermissions = permissions is List
          ? permissions.map((value) => value.toString()).toSet()
          : const <String>{};
      if (requiredPermission.isNotEmpty &&
          declaredPermissions.isNotEmpty &&
          !declaredPermissions.contains(requiredPermission)) {
        return SkillValidationResult(
          error: '执行器 $executor 缺少权限声明：$requiredPermission',
        );
      }
      if (executor == 'native') {
        return const SkillValidationResult(error: 'native 执行器不允许第三方 Skill 使用');
      }
      if (tool['input_schema'] != null && tool['input_schema'] is! Map) {
        return const SkillValidationResult(error: 'input_schema 必须是对象');
      }
      if (executor == 'http') {
        final url = tool['url']?.toString() ?? '';
        final parsedUrl = Uri.tryParse(url);
        if (parsedUrl == null ||
            !parsedUrl.hasScheme ||
            (parsedUrl.scheme != 'https' && parsedUrl.scheme != 'http')) {
          return const SkillValidationResult(error: 'HTTP 工具必须提供 HTTP(S) URL');
        }
      }
      if (executor == 'mcp_proxy') {
        final serverId = tool['mcp_server_id']?.toString().trim() ?? '';
        final targetTool = tool['mcp_tool']?.toString().trim() ?? '';
        if (serverId.isEmpty || targetTool.isEmpty) {
          return const SkillValidationResult(
            error: 'mcp_proxy 必须提供 mcp_server_id 和 mcp_tool',
          );
        }
      }
      if (executor == 'prompt') {
        final template = tool['prompt']?.toString().trim() ?? '';
        if (template.isEmpty) {
          return const SkillValidationResult(error: 'prompt 工具必须提供 prompt');
        }
      }
    }
    return SkillValidationResult(manifest: manifest);
  }

  static Map<String, dynamic> decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('manifest 必须是 JSON 对象');
    return Map<String, dynamic>.from(decoded);
  }
}

class McpClient {
  static Map<String, dynamic> parseResponseBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) throw const FormatException('MCP 返回为空');
    final dataLines = trimmed
        .split(RegExp(r'\r?\n'))
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final decoded = jsonDecode(dataLines.isEmpty ? trimmed : dataLines.last);
    if (decoded is! Map) throw const FormatException('MCP 响应格式无效');
    final map = Map<String, dynamic>.from(decoded);
    if (map['error'] != null) throw StateError('MCP ${map['error']}');
    return map['result'] is Map
        ? Map<String, dynamic>.from(map['result'] as Map)
        : map;
  }

  final String url;
  final Map<String, String> headers;
  final Duration timeout;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  String? sessionId;
  String? negotiatedProtocolVersion;
  int _nextId = 1;

  McpClient({
    required this.url,
    this.headers = const {},
    this.timeout = const Duration(seconds: 20),
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }

  Future<Map<String, dynamic>> initialize() async {
    final result = await _request('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': const {},
      'clientInfo': {'name': 'TideBot', 'version': '1.0'},
    });
    negotiatedProtocolVersion = result['protocolVersion']?.toString();
    await _notify('notifications/initialized', const {});
    return result;
  }

  Future<List<Map<String, dynamic>>> listTools() async {
    final tools = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final result = await _request(
        'tools/list',
        cursor == null ? const {} : {'cursor': cursor},
      );
      tools.addAll(_listResult(result, 'tools'));
      cursor = result['nextCursor']?.toString().trim();
      if (cursor?.isEmpty == true) cursor = null;
    } while (cursor != null && tools.length < 1000);
    return tools;
  }

  Future<List<Map<String, dynamic>>> listResources() async {
    final result = await _request('resources/list', const {});
    return _listResult(result, 'resources');
  }

  Future<List<Map<String, dynamic>>> listResourcesSafe() async {
    try {
      return await listResources();
    } on StateError {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> listPrompts() async {
    final result = await _request('prompts/list', const {});
    return _listResult(result, 'prompts');
  }

  Future<List<Map<String, dynamic>>> listPromptsSafe() async {
    try {
      return await listPrompts();
    } on StateError {
      return const [];
    }
  }

  List<Map<String, dynamic>> _listResult(
    Map<String, dynamic> result,
    String key,
  ) {
    final values = result[key];
    return values is List
        ? values.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const [];
  }

  Future<Map<String, dynamic>> getServerCapabilities() async {
    return _request('ping', const {});
  }

  Future<void> close() async {
    final currentSession = sessionId;
    if (currentSession == null) return;
    try {
      await _httpClient.delete(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json, text/event-stream',
          'Mcp-Session-Id': currentSession,
          ...headers,
        },
      ).timeout(timeout);
    } finally {
      sessionId = null;
      negotiatedProtocolVersion = null;
    }
  }

  static String describeError(Object error) {
    if (error is TimeoutException) return 'MCP 请求超时';
    if (error is FormatException) return 'MCP 协议响应无效：${error.message}';
    final message = error.toString();
    final http = RegExp(r'MCP HTTP (\d+)').firstMatch(message);
    if (http != null) {
      final status = int.parse(http.group(1)!);
      if (status == 401 || status == 403) return 'MCP 鉴权失败（HTTP $status）';
      if (status >= 500) return 'MCP 服务端错误（HTTP $status）';
      return 'MCP 请求失败（HTTP $status）';
    }
    return message.length > 300 ? message.substring(0, 300) : message;
  }

  Future<dynamic> callTool(String name, Map<String, dynamic> arguments) async {
    final result =
        await _request('tools/call', {'name': name, 'arguments': arguments});
    if (result['isError'] == true) {
      throw StateError('MCP 工具调用失败：${result['content'] ?? result}');
    }
    return {
      'content': result['content'] ?? const [],
      if (result.containsKey('structuredContent'))
        'structuredContent': result['structuredContent'],
      'isError': false,
    };
  }

  Future<void> _notify(String method, Map<String, dynamic> params) async {
    await _httpClient
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            if (sessionId != null) 'Mcp-Session-Id': sessionId!,
            ...headers,
          },
          body: jsonEncode(
              {'jsonrpc': '2.0', 'method': method, 'params': params}),
        )
        .timeout(timeout);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = _nextId++;
    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            if (sessionId != null) 'Mcp-Session-Id': sessionId!,
            ...headers,
          },
          body: jsonEncode(
              {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('MCP HTTP ${response.statusCode}');
    }
    sessionId ??= response.headers['mcp-session-id'];
    final body = response.body.trim();
    return parseResponseBody(body);
  }
}
