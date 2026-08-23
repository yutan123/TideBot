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
      if (tool['input_schema'] != null && tool['input_schema'] is! Map) {
        return const SkillValidationResult(error: 'input_schema 必须是对象');
      }
      if (executor == 'http') {
        final url = tool['url']?.toString() ?? '';
        final parsedUrl = Uri.tryParse(url);
        if (parsedUrl == null || !parsedUrl.hasScheme) {
          return const SkillValidationResult(error: 'HTTP 工具必须提供有效 url');
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
  final String url;
  final Map<String, String> headers;
  final Duration timeout;
  String? sessionId;
  int _nextId = 1;

  McpClient({
    required this.url,
    this.headers = const {},
    this.timeout = const Duration(seconds: 20),
  });

  Future<Map<String, dynamic>> initialize() async {
    final result = await _request('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': const {},
      'clientInfo': {'name': 'TideBot', 'version': '1.0'},
    });
    await _notify('notifications/initialized', const {});
    return result;
  }

  Future<List<Map<String, dynamic>>> listTools() async {
    final result = await _request('tools/list', const {});
    final tools = result['tools'];
    return tools is List
        ? tools
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : const [];
  }

  Future<dynamic> callTool(String name, Map<String, dynamic> arguments) async {
    final result =
        await _request('tools/call', {'name': name, 'arguments': arguments});
    return result['content'] ?? result;
  }

  Future<void> _notify(String method, Map<String, dynamic> params) async {
    await http
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json', ...headers},
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
    final response = await http
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
    if (body.isEmpty) throw const FormatException('MCP 返回为空');
    final jsonText = body.startsWith('data:')
        ? body
            .split('\n')
            .firstWhere((line) => line.startsWith('data:'))
            .substring(5)
            .trim()
        : body;
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) throw const FormatException('MCP 响应格式无效');
    final map = Map<String, dynamic>.from(decoded);
    if (map['error'] != null) throw StateError('MCP ${map['error']}');
    return map['result'] is Map
        ? Map<String, dynamic>.from(map['result'] as Map)
        : map;
  }
}
