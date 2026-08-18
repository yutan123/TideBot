import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'db.dart';
import 'global_notice.dart';
import 'plugin_detail_page.dart';
import 'plugin_security.dart';
import 'theme.dart';

class PluginRegistry {
  static const _key = 'local_plugin_registry';

  static Future<List<Map<String, dynamic>>> load() async {
    final raw = await DBManager().getKV(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Map<String, dynamic>> plugins) =>
      DBManager().setKV(_key, jsonEncode(plugins));

  static Future<void> importManifest() async {
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
    final file = picked?.files.single;
    if (file == null) throw const FormatException('未读取到插件文件');
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) throw const FormatException('未读取到插件文件');
    await installManifestBytes(bytes);
  }

  static Future<void> installManifestBytes(Uint8List bytes) async {
    final report = PluginSecurityScanner.scanBytes(bytes);
    if (!report.isSafe) throw FormatException(report.message);
    final manifest =
        Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    final id = manifest['id'].toString().trim();
    final plugins = await load();
    final index = plugins.indexWhere((plugin) => plugin['id'] == id);
    final entry = Map<String, dynamic>.from(manifest)
      ..['enabled'] = false
      ..['needs_health_check'] = true
      ..['granted_permissions'] = index >= 0 &&
              plugins[index]['granted_permissions'] is List
          ? List<dynamic>.from(plugins[index]['granted_permissions'] as List)
          : <String>[]
      ..['installed_at'] = DateTime.now().millisecondsSinceEpoch;
    if (index >= 0) {
      plugins[index] = entry;
    } else {
      plugins.add(entry);
    }
    await save(plugins);
  }
}

class PluginCenterPage extends StatefulWidget {
  const PluginCenterPage({super.key});
  @override
  State<PluginCenterPage> createState() => _PluginCenterPageState();
}

class _PluginCenterPageState extends State<PluginCenterPage> {
  List<Map<String, dynamic>> _plugins = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plugins = await PluginRegistry.load();
    if (mounted) setState(() => _plugins = plugins);
  }

  Future<void> _toggle(int index, bool enabled) async {
    final next = List<Map<String, dynamic>>.from(_plugins);
    if (enabled) {
      await _openPlugin(next[index]);
      return;
    }
    next[index] = Map<String, dynamic>.from(next[index])..['enabled'] = false;
    await PluginRegistry.save(next);
    if (mounted) setState(() => _plugins = next);
  }

  Future<void> _openPlugin(Map<String, dynamic> plugin) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PluginDetailPage(plugin: plugin)),
    );
    _load();
  }

  String _capabilitySummary(Map<String, dynamic> plugin) {
    final labels = <String>[];
    if (plugin['skills'] is List && (plugin['skills'] as List).isNotEmpty)
      labels.add('Skill');
    if (plugin['mcp_servers'] is List &&
        (plugin['mcp_servers'] as List).isNotEmpty) labels.add('MCP');
    if (plugin['ui'] is Map) labels.add('UI');
    return labels.isEmpty ? '清单' : labels.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(title: const Text('插件'), backgroundColor: theme.bgColor),
      body: _plugins.isEmpty
          ? Center(
              child: Text('还没有本地插件',
                  style:
                      TextStyle(color: theme.textWeak, fontFamily: 'TideFont')))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _plugins.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final plugin = _plugins[index];
                return ListTile(
                  onTap: () => _openPlugin(plugin),
                  tileColor: theme.surface,
                  leading: Icon(Icons.extension_rounded, color: theme.primary),
                  title: Text(plugin['name']?.toString() ?? '未命名插件',
                      style: const TextStyle(fontFamily: 'TideFont')),
                  subtitle: Text(
                      plugin['description']?.toString() ??
                          plugin['id']?.toString() ??
                          '',
                      style: const TextStyle(fontFamily: 'TideFont')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_capabilitySummary(plugin),
                          style:
                              TextStyle(color: theme.textWeak, fontSize: 12)),
                      const SizedBox(width: 6),
                      Switch(
                        value: plugin['enabled'] != false,
                        onChanged: (value) => _toggle(index, value),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class PluginDeveloperPage extends StatefulWidget {
  const PluginDeveloperPage({super.key});
  @override
  State<PluginDeveloperPage> createState() => _PluginDeveloperPageState();
}

class _PluginDeveloperPageState extends State<PluginDeveloperPage> {
  final _request = TextEditingController();
  List<Map<String, dynamic>> _providers = [];
  String? _providerId;
  String _output = '';
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    final providers = await DBManager().queryChatProviders();
    if (mounted)
      setState(() {
        _providers = providers;
        _providerId =
            providers.isEmpty ? null : providers.first['id']?.toString();
      });
  }

  Future<void> _develop() async {
    final idea = _request.text.trim();
    final provider = _providers
        .where((item) => item['id']?.toString() == _providerId)
        .firstOrNull;
    if (idea.isEmpty || provider == null) return;
    setState(() => _loading = true);
    try {
      final base =
          provider['base_url'].toString().replaceFirst(RegExp(r'/+$'), '');
      final response = await http
          .post(Uri.parse('$base/chat/completions'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${provider['api_key']}'
              },
              body: jsonEncode({
                'model': provider['model'],
                'messages': [
                  {
                    'role': 'system',
                    'content':
                        '你是 TideBot 插件开发助手。插件是受控的声明式运行时，不执行任意 Dart 或 JavaScript。只输出严格 JSON，不要 markdown。格式：{"format":"tidebot.plugin/v1","id":"lowercase-id","name":"名称","description":"说明","version":"0.1.0","permissions":["network"],"skills":[{"name":"技能名","instructions":"注入机器人系统提示的具体规则，可选 bot_ids"}],"mcp_servers":[{"name":"服务名","url":"https://example.com/mcp","headers":{}}],"ui":{"title":"页面标题","description":"说明","fields":[{"id":"query","label":"输入","multiline":false}],"actions":[{"label":"执行","mcp_server":0,"tool":"MCP tools/list 声明的工具名"}]},"readme":"开发说明"}。仅在需要联网 MCP 时声明 network；MCP 必须提供 HTTP JSON-RPC 的 tools/list 和 tools/call。'
                  },
                  {'role': 'user', 'content': idea}
                ]
              }))
          .timeout(const Duration(seconds: 60));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final text =
          decoded['choices']?[0]?['message']?['content']?.toString() ?? '';
      if (text.isEmpty) throw StateError('模型未返回插件清单');
      setState(() => _output = text);
    } catch (error) {
      if (mounted)
        GlobalNotice.show('开发请求失败：$error', color: const Color(0xFFE74C3C));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _installOutput() async {
    try {
      final manifest = jsonDecode(_output);
      if (manifest is! Map) throw const FormatException('AI 输出不是 JSON');
      await PluginRegistry.installManifestBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(manifest))));
      if (mounted) {
        GlobalNotice.show('插件已安装，可在插件列表中授权并打开');
      }
    } catch (_) {
      GlobalNotice.show('请先生成有效插件清单', color: const Color(0xFFE74C3C));
    }
  }

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
        backgroundColor: theme.bgColor,
        appBar:
            AppBar(title: const Text('开发插件'), backgroundColor: theme.bgColor),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            DropdownButtonFormField<String>(
                initialValue: _providerId,
                items: _providers
                    .map((p) => DropdownMenuItem(
                        value: p['id']?.toString(),
                        child: Text(p['name']?.toString() ?? '模型')))
                    .toList(),
                onChanged: (value) => setState(() => _providerId = value),
                decoration: const InputDecoration(labelText: '模型提供商')),
            const SizedBox(height: 12),
            TextField(
                controller: _request,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(hintText: '描述要开发的插件')),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: _loading ? null : _develop,
                icon: const Icon(Icons.send_rounded),
                label: Text(_loading ? '生成中' : '生成插件清单')),
            const SizedBox(height: 12),
            Expanded(
                child: SingleChildScrollView(
                    child: SelectableText(
                        _output.isEmpty
                            ? '插件开发规范：Skill 的 instructions 会随启用插件注入机器人提示；MCP 通过 HTTP JSON-RPC 的 tools/list 和 tools/call 注册给聊天模型；UI 由 fields 和 actions 渲染为实际页面。插件不会执行任意 Dart 或 JavaScript；网络 MCP 必须声明 network 权限，并由用户在插件详情中授权。'
                            : _output,
                        style: const TextStyle(fontFamily: 'monospace')))),
            if (_output.isNotEmpty)
              IconButton(
                  tooltip: '安装生成的插件',
                  onPressed: _installOutput,
                  icon: const Icon(Icons.download_for_offline_rounded)),
          ]),
        ));
  }
}
