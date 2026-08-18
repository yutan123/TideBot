import 'dart:convert';
import 'dart:typed_data';

import 'plugin_runtime.dart';

class PluginCheckResult {
  const PluginCheckResult({this.errors = const [], this.warnings = const []});
  final List<String> errors;
  final List<String> warnings;
  bool get isSafe => errors.isEmpty;
  String get message => [...errors, ...warnings].join('\n');
}

/// Validates the declarative plugin format before it reaches local storage.
/// This is a risk gate, not a replacement for endpoint reputation scanning.
class PluginSecurityScanner {
  static const _maxManifestBytes = 256 * 1024;
  static const _allowedRoot = {
    'format',
    'id',
    'name',
    'description',
    'version',
    'permissions',
    'skills',
    'mcp_servers',
    'ui',
    'readme',
    'enabled',
  };
  static const _dangerousKeys = {
    'code',
    'script',
    'javascript',
    'dart',
    'shell',
    'command',
    'exec',
    'process',
    'apk',
    'native_library',
    'file_path',
    'background_task',
  };

  static PluginCheckResult scanBytes(Uint8List bytes) {
    if (bytes.length > _maxManifestBytes) {
      return const PluginCheckResult(errors: ['插件文件超过 256 KB 限制']);
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        return const PluginCheckResult(errors: ['插件清单必须是 JSON 对象']);
      }
      return scanManifest(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return const PluginCheckResult(errors: ['插件文件不是 UTF-8 JSON']);
    } catch (_) {
      return const PluginCheckResult(errors: ['插件文件无法解析']);
    }
  }

  static PluginCheckResult scanManifest(Map<String, dynamic> manifest) {
    final errors = <String>[];
    final warnings = <String>[];
    final unknown = manifest.keys.where((key) => !_allowedRoot.contains(key));
    if (unknown.isNotEmpty) errors.add('包含未支持字段：${unknown.join(', ')}');
    if (_containsDangerousKey(manifest)) errors.add('包含代码执行、文件或后台任务字段');
    if (manifest['format'] != 'tidebot.plugin/v1')
      errors.add('不是 TideBot 插件清单');
    final id = manifest['id']?.toString().trim() ?? '';
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$').hasMatch(id)) {
      errors.add('插件 id 无效');
    }
    if ((manifest['name']?.toString().trim().length ?? 0) > 80 ||
        (manifest['name']?.toString().trim().isEmpty ?? true)) {
      errors.add('插件名称无效');
    }
    _checkText(manifest['description'], 'description', 500, errors);
    _checkText(manifest['readme'], 'readme', 4000, errors);
    final permissions = manifest['permissions'];
    if (permissions != null &&
        (permissions is! List ||
            permissions
                .any((p) => p.toString() != PluginRuntime.permissionNetwork))) {
      errors.add('只允许声明 network 权限');
    }
    _checkSkills(manifest['skills'], errors);
    _checkServers(manifest['mcp_servers'], errors, warnings);
    _checkUi(manifest['ui'], manifest['mcp_servers'], errors);
    return PluginCheckResult(errors: errors, warnings: warnings);
  }

  static bool _containsDangerousKey(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (_dangerousKeys.contains(entry.key.toString().toLowerCase()) ||
            _containsDangerousKey(entry.value)) return true;
      }
    } else if (value is List) {
      return value.any(_containsDangerousKey);
    }
    return false;
  }

  static void _checkText(
      dynamic value, String name, int max, List<String> errors) {
    if (value != null && (value is! String || value.length > max)) {
      errors.add('$name 必须是最多 $max 个字符的文本');
    }
  }

  static void _checkSkills(dynamic value, List<String> errors) {
    if (value == null) return;
    if (value is! List || value.length > 20) {
      errors.add('skills 必须是不超过 20 项的列表');
      return;
    }
    for (final skill in value) {
      if (skill is! Map || (skill['name']?.toString().trim().isEmpty ?? true)) {
        errors.add('Skill 缺少名称');
        continue;
      }
      _checkText(skill['instructions'], 'Skill instructions', 4000, errors);
      if (skill['instructions']?.toString().trim().isEmpty ?? true)
        errors.add('Skill 缺少 instructions');
      if (skill['bot_ids'] != null && skill['bot_ids'] is! List)
        errors.add('Skill bot_ids 必须是列表');
    }
  }

  static void _checkServers(
      dynamic value, List<String> errors, List<String> warnings) {
    if (value == null) return;
    if (value is! List || value.length > 5) {
      errors.add('mcp_servers 必须是不超过 5 项的列表');
      return;
    }
    for (final server in value) {
      if (server is! Map) {
        errors.add('MCP 服务配置无效');
        continue;
      }
      final uri =
          Uri.tryParse((server['url'] ?? server['endpoint'] ?? '').toString());
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          !(uri.scheme == 'https' || uri.scheme == 'http') ||
          _isPrivateHost(uri.host)) {
        errors.add('MCP 地址必须是公网 HTTP/HTTPS URL');
      }
      if (uri?.scheme == 'http') warnings.add('MCP 使用 HTTP，传输内容可能被篡改');
      final headers = server['headers'];
      if (headers != null &&
          (headers is! Map ||
              headers.length > 16 ||
              headers.entries.any((e) =>
                  e.key.toString().length > 80 ||
                  e.value.toString().length > 2048 ||
                  e.key.toString().toLowerCase() == 'host'))) {
        errors.add('MCP headers 配置无效');
      }
    }
  }

  static bool _isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local')) return true;
    final parts = h.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((n) => n == null || n < 0 || n > 255)) return false;
    final a = octets[0]!;
    final b = octets[1]!;
    return a == 10 ||
        a == 127 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31) ||
        a == 0 ||
        (a == 169 && b == 254);
  }

  static void _checkUi(dynamic value, dynamic servers, List<String> errors) {
    if (value == null) return;
    if (value is! Map) {
      errors.add('ui 必须是对象');
      return;
    }
    final fields = value['fields'];
    final actions = value['actions'];
    if (fields != null && (fields is! List || fields.length > 20))
      errors.add('UI fields 不能超过 20 项');
    if (fields is List)
      for (final field in fields) {
        final id = field is Map ? field['id']?.toString() ?? '' : '';
        if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(id))
          errors.add('UI field id 无效');
      }
    if (actions != null && (actions is! List || actions.length > 10))
      errors.add('UI actions 不能超过 10 项');
    if (actions is List)
      for (final action in actions) {
        final index = int.tryParse(
            (action is Map ? action['mcp_server'] : '').toString());
        final tool = action is Map ? action['tool']?.toString() ?? '' : '';
        if (index == null ||
            servers is! List ||
            index < 0 ||
            index >= servers.length ||
            !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(tool))
          errors.add('UI action 必须指向声明的 MCP 工具');
      }
  }
}

class PluginHealthChecker {
  static Future<PluginCheckResult> check(Map<String, dynamic> plugin) async {
    final staticResult = PluginSecurityScanner.scanManifest(plugin);
    if (!staticResult.isSafe) return staticResult;
    final errors = <String>[];
    final warnings = List<String>.from(staticResult.warnings);
    final servers = plugin['mcp_servers'];
    if (servers is List && servers.isNotEmpty) {
      if (!PluginRuntime.instance
          .hasPermission(plugin, PluginRuntime.permissionNetwork)) {
        errors.add('请先授予网络权限，再执行 MCP 可用性检测');
      } else {
        for (final raw in servers.whereType<Map>()) {
          try {
            await PluginRuntime.instance
                .listServerTools(plugin, Map<String, dynamic>.from(raw));
          } catch (e) {
            errors.add('MCP 检测失败：$e');
          }
        }
      }
    }
    return PluginCheckResult(errors: errors, warnings: warnings);
  }
}
