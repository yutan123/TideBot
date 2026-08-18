import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log_service.dart';
import 'db.dart';

/// The executable, declarative part of a TideBot plugin. Plugins never load
/// Dart or JavaScript: skills are prompt fragments and MCP is JSON-RPC over
/// explicitly authorised HTTP endpoints.
class PluginRuntime {
  PluginRuntime._();

  static final PluginRuntime instance = PluginRuntime._();

  static const permissionNetwork = 'network';

  Future<List<Map<String, dynamic>>> _enabledPlugins() async {
    final raw = await DBManager().getKV('local_plugin_registry');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => item['enabled'] != false)
          .toList();
    } catch (_) {
      return [];
    }
  }

  bool hasPermission(Map<String, dynamic> plugin, String permission) {
    final granted = plugin['granted_permissions'];
    return granted is List &&
        granted.map((e) => e.toString()).contains(permission);
  }

  Future<String> skillPrompt(String botId) async {
    final parts = <String>[];
    for (final plugin in await _enabledPlugins()) {
      final skills = plugin['skills'];
      if (skills is! List) continue;
      for (final raw in skills.whereType<Map>()) {
        final skill = Map<String, dynamic>.from(raw);
        if (skill['enabled'] == false) continue;
        final targets = skill['bot_ids'];
        if (targets is List &&
            targets.isNotEmpty &&
            !targets.map((e) => e.toString()).contains(botId)) {
          continue;
        }
        final instruction = skill['instructions']?.toString().trim() ?? '';
        if (instruction.isEmpty) continue;
        final name = skill['name']?.toString().trim() ??
            plugin['name']?.toString() ??
            '插件技能';
        parts.add('【插件 Skill：$name】$instruction');
      }
    }
    return parts.isEmpty ? '' : '\n${parts.join('\n')}';
  }

  Future<List<Map<String, dynamic>>> toolSchemas() async {
    final tools = <Map<String, dynamic>>[];
    for (final plugin in await _enabledPlugins()) {
      if (!hasPermission(plugin, permissionNetwork)) continue;
      final servers = plugin['mcp_servers'];
      if (servers is! List) continue;
      for (var serverIndex = 0; serverIndex < servers.length; serverIndex++) {
        final rawServer = servers[serverIndex];
        if (rawServer is! Map) continue;
        final server = Map<String, dynamic>.from(rawServer);
        if (server['enabled'] == false) continue;
        try {
          final remoteTools = await _listTools(plugin, server);
          for (final rawTool in remoteTools) {
            final tool = Map<String, dynamic>.from(rawTool);
            final remoteName = tool['name']?.toString().trim() ?? '';
            if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(remoteName))
              continue;
            tools.add({
              'type': 'function',
              'function': {
                'name':
                    _toolName(plugin['id'].toString(), serverIndex, remoteName),
                'description':
                    '[${plugin['name'] ?? plugin['id']}] ${tool['description']?.toString() ?? remoteName}',
                'parameters': tool['inputSchema'] is Map
                    ? Map<String, dynamic>.from(tool['inputSchema'])
                    : (tool['parameters'] is Map
                        ? Map<String, dynamic>.from(tool['parameters'])
                        : <String, dynamic>{
                            'type': 'object',
                            'properties': <String, dynamic>{}
                          }),
              },
            });
          }
        } catch (error) {
          AppLogService.instance
              .add('PLUGIN_MCP', '无法读取 ${plugin['id']} 的 MCP 工具：$error');
        }
      }
    }
    return tools;
  }

  Future<Map<String, dynamic>> executeToolCall({
    required Map<String, dynamic> call,
  }) async {
    final function = call['function'];
    if (function is! Map) return _error('无效插件工具调用');
    final name = function['name']?.toString() ?? '';
    final match =
        RegExp(r'^plugin__([a-z0-9_]+)__(\d+)__(.+)$').firstMatch(name);
    if (match == null) return _error('未知插件工具：$name');
    Map<String, dynamic> args;
    try {
      final parsed = jsonDecode(function['arguments']?.toString() ?? '{}');
      args = parsed is Map
          ? Map<String, dynamic>.from(parsed)
          : <String, dynamic>{};
    } catch (_) {
      return _error('插件工具参数不是合法 JSON');
    }
    final pluginToken = match.group(1)!;
    final plugins = await _enabledPlugins();
    final pluginId = plugins
        .where((item) =>
            item['id']?.toString().replaceAll('-', '_').replaceAll('.', '_') ==
            pluginToken)
        .map((item) => item['id']?.toString() ?? '')
        .firstOrNull;
    if (pluginId == null || pluginId.isEmpty) return _error('插件未安装或已停用');
    final serverIndex = int.parse(match.group(2)!);
    final remoteName = match.group(3)!;
    final plugin =
        plugins.where((p) => p['id']?.toString() == pluginId).firstOrNull;
    if (plugin == null) return _error('插件未安装或已停用');
    if (!hasPermission(plugin, permissionNetwork)) return _error('插件未获网络权限');
    final servers = plugin['mcp_servers'];
    if (servers is! List ||
        serverIndex >= servers.length ||
        servers[serverIndex] is! Map) {
      return _error('插件 MCP 配置无效');
    }
    final server = Map<String, dynamic>.from(servers[serverIndex] as Map);
    if (server['enabled'] == false) return _error('插件 MCP 已停用');
    try {
      final tools = await _listTools(plugin, server);
      final remoteTool = tools
          .where((tool) =>
              _toolName(
                  pluginId, serverIndex, tool['name']?.toString() ?? '') ==
              name)
          .firstOrNull;
      final actualName = remoteTool?['name']?.toString().trim() ?? '';
      if (actualName.isEmpty) return _error('插件 MCP 未声明工具：$remoteName');
      final result = await _rpc(plugin, server, 'tools/call', {
        'name': actualName,
        'arguments': args,
      });
      return {
        'result': {
          'ok': true,
          'plugin_id': pluginId,
          'tool': remoteName,
          'data': result
        }
      };
    } catch (error) {
      AppLogService.instance
          .add('PLUGIN_MCP', '调用 $pluginId/$remoteName 失败：$error');
      return _error('插件 MCP 调用失败：$error');
    }
  }

  Future<List<Map<String, dynamic>>> listServerTools(
      Map<String, dynamic> plugin, Map<String, dynamic> server) async {
    if (!hasPermission(plugin, permissionNetwork)) {
      throw StateError('该插件未获网络权限');
    }
    return _listTools(plugin, server);
  }

  Future<List<Map<String, dynamic>>> _listTools(
      Map<String, dynamic> plugin, Map<String, dynamic> server) async {
    final result =
        await _rpc(plugin, server, 'tools/list', const <String, dynamic>{});
    final tools = result['tools'];
    return tools is List
        ? tools
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : [];
  }

  Future<dynamic> _rpc(Map<String, dynamic> plugin, Map<String, dynamic> server,
      String method, Map<String, dynamic> params) async {
    final endpoint =
        (server['url'] ?? server['endpoint'])?.toString().trim() ?? '';
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty) {
      throw StateError('MCP endpoint 必须是 http 或 https URL');
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    final configuredHeaders = server['headers'];
    if (configuredHeaders is Map) {
      configuredHeaders
          .forEach((key, value) => headers[key.toString()] = value.toString());
    }
    final response = await http
        .post(uri,
            headers: headers,
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': DateTime.now().microsecondsSinceEpoch,
              'method': method,
              'params': params,
            }))
        .timeout(const Duration(seconds: 25));
    if (response.contentLength != null &&
        response.contentLength! > 1024 * 1024) {
      throw StateError('MCP 响应超过 1 MB 限制');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map) throw StateError('MCP 返回不是 JSON 对象');
    if (body['error'] != null) throw StateError(body['error'].toString());
    return body['result'] ?? <String, dynamic>{};
  }

  String _toolName(String pluginId, int serverIndex, String remoteName) =>
      'plugin__${pluginId.replaceAll('-', '_').replaceAll('.', '_')}__${serverIndex}__${remoteName.replaceAll('-', '_')}';

  Map<String, dynamic> _error(String error) => {
        'result': {'ok': false, 'error': error}
      };
}
