import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'db.dart';
import 'global_notice.dart';
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
    final bytes = picked?.files.single.bytes;
    if (bytes == null) throw const FormatException('未读取到插件文件');
    final manifest = jsonDecode(utf8.decode(bytes));
    if (manifest is! Map || manifest['format'] != 'tidebot.plugin/v1') {
      throw const FormatException('不是 TideBot 插件清单');
    }
    final id = manifest['id']?.toString().trim() ?? '';
    final name = manifest['name']?.toString().trim() ?? '';
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$').hasMatch(id) || name.isEmpty) {
      throw const FormatException('插件 id 或名称无效');
    }
    final plugins = await load();
    final entry = Map<String, dynamic>.from(manifest)
      ..['enabled'] = manifest['enabled'] != false
      ..['installed_at'] = DateTime.now().millisecondsSinceEpoch;
    final index = plugins.indexWhere((plugin) => plugin['id'] == id);
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
    next[index] = Map<String, dynamic>.from(next[index])..['enabled'] = enabled;
    await PluginRegistry.save(next);
    if (mounted) setState(() => _plugins = next);
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
                  tileColor: theme.surface,
                  leading: Icon(Icons.extension_rounded, color: theme.primary),
                  title: Text(plugin['name']?.toString() ?? '未命名插件',
                      style: const TextStyle(fontFamily: 'TideFont')),
                  subtitle: Text(
                      plugin['description']?.toString() ??
                          plugin['id']?.toString() ??
                          '',
                      style: const TextStyle(fontFamily: 'TideFont')),
                  trailing: Switch(
                      value: plugin['enabled'] != false,
                      onChanged: (value) => _toggle(index, value)),
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
                        '你是 TideBot 本地插件开发助手。插件当前是声明式清单，不执行任意第三方代码。请输出严格 JSON，不要 markdown。格式：{"format":"tidebot.plugin/v1","id":"lowercase-id","name":"名称","description":"说明","version":"0.1.0","capabilities":["ui"],"instructions":"给 TideBot 的使用说明","readme":"开发与安装说明"}。'
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
      final bytes = utf8.encode(jsonEncode(manifest));
      final result = await FilePicker.platform.saveFile(
          fileName: '${manifest['id'] ?? 'plugin'}.json',
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: const ['json']);
      if (result != null && mounted) GlobalNotice.show('插件清单已导出，可从本地导入安装');
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
                            ? '插件开发规范：清单必须包含 format、id、name、version、capabilities、instructions 和 readme。当前版本只安装声明式插件，后续可在此格式上扩展受限工具能力。'
                            : _output,
                        style: const TextStyle(fontFamily: 'monospace')))),
            if (_output.isNotEmpty)
              IconButton(
                  tooltip: '导出插件清单',
                  onPressed: _installOutput,
                  icon: const Icon(Icons.download_rounded)),
          ]),
        ));
  }
}
