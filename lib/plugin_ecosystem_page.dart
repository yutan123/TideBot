import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'db.dart';
import 'global_notice.dart';
import 'plugin_development_guide.dart';
import 'plugin_detail_page.dart';
import 'plugin_security.dart';
import 'theme.dart';

class PluginRegistry {
  static const _key = 'local_plugin_registry';

  static PluginCheckResult validateManifest(Map<String, dynamic> manifest) {
    final normalized = _normalizeManifest(manifest);
    return PluginSecurityScanner.scanBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(normalized))),
    );
  }

  static String _categoryLabel(String category) => switch (category) {
        'skill' => 'Skills',
        'mcp' => 'MCP',
        _ => '插件',
      };

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
  static Future<void> importManifest({String? expectedCategory}) async {
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
    final file = picked?.files.single;
    if (file == null) throw const FormatException('未读取到插件文件');
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) throw const FormatException('未读取到插件文件');
    await installManifestBytes(bytes, expectedCategory: expectedCategory);
  }

  static String categoryOf(Map<String, dynamic> manifest) {
    final explicit = manifest['category']?.toString() ?? '';
    if (explicit == 'skill' || explicit == 'mcp' || explicit == 'plugin') {
      return explicit;
    }
    if (manifest['mcp_servers'] is List &&
        (manifest['mcp_servers'] as List).isNotEmpty) return 'mcp';
    if (manifest['skills'] is List && (manifest['skills'] as List).isNotEmpty) {
      return 'skill';
    }
    return 'plugin';
  }

  static Map<String, dynamic> _normalizeManifest(
      Map<String, dynamic> manifest) {
    if (manifest['format'] != 'tidebot.plugin/v2') return manifest;
    final capabilities = manifest['capabilities'];
    if (capabilities is! Map) return manifest;
    return <String, dynamic>{
      ...manifest,
      'format': 'tidebot.plugin/v1',
      'skills': capabilities['assistant_rules'] ?? const [],
      'mcp_servers': capabilities['tools'] ?? const [],
      'ui': capabilities['views'] is List &&
              (capabilities['views'] as List).isNotEmpty
          ? (capabilities['views'] as List).first
          : null,
    }..remove('capabilities');
  }

  static Future<void> installManifestBytes(Uint8List bytes,
      {String? expectedCategory}) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('插件清单必须是 JSON 对象');
    final normalized = _normalizeManifest(Map<String, dynamic>.from(decoded));
    final category = categoryOf(normalized);
    if (expectedCategory != null && expectedCategory != category) {
      throw FormatException('该清单属于${_categoryLabel(category)}，请选择对应类别导入');
    }
    final normalizedBytes =
        Uint8List.fromList(utf8.encode(jsonEncode(normalized)));
    final report = PluginSecurityScanner.scanBytes(normalizedBytes);
    if (!report.isSafe) throw FormatException(report.message);
    final manifest = normalized;
    final id = manifest['id'].toString().trim();
    final plugins = await load();
    final index = plugins.indexWhere((plugin) => plugin['id'] == id);
    final entry = Map<String, dynamic>.from(manifest)
      ..['category'] = category
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

class _PluginCenterPageState extends State<PluginCenterPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _plugins = [];
  late final TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
      labels.add('助手规则');
    if (plugin['mcp_servers'] is List &&
        (plugin['mcp_servers'] as List).isNotEmpty) labels.add('远程工具');
    if (plugin['ui'] is Map) labels.add('插件页面');
    return labels.isEmpty ? '基础插件' : labels.join(' · ');
  }

  List<Map<String, dynamic>> _forCategory(String category) => _plugins
      .where((plugin) => PluginRegistry.categoryOf(plugin) == category)
      .toList();

  Widget _categoryList(String category, String emptyText, IconData icon) {
    final theme = TideTheme.of(context);
    final entries = _forCategory(category);
    if (entries.isEmpty) {
      return Center(
        child: Text(emptyText,
            style: TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final plugin = entries[index];
        final storedIndex = _plugins.indexOf(plugin);
        final permissions = (plugin['granted_permissions'] as List? ?? const [])
            .map((value) => value.toString())
            .join(', ');
        final health = plugin['needs_health_check'] == true
            ? '待检测'
            : (plugin['enabled'] == true ? '正常' : '已停用');
        final source =
            plugin['source']?.toString() ?? _capabilitySummary(plugin);
        final version = plugin['version']?.toString() ?? '未标注版本';
        return ListTile(
          onTap: () => _openPlugin(plugin),
          tileColor: theme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: Icon(icon, color: theme.primary),
          title: Text(plugin['name']?.toString() ?? '未命名',
              style: const TextStyle(fontFamily: 'TideFont')),
          subtitle: Text(
              '$source  |  $version\n$health${permissions.isEmpty ? '' : '  |  权限：$permissions'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
          trailing: Switch(
            value: plugin['enabled'] == true,
            onChanged: (value) => _toggle(storedIndex, value),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
        title: const Text('插件中心'),
        backgroundColor: theme.bgColor,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Skills'), Tab(text: 'MCP'), Tab(text: '插件')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _categoryList(
              'skill', '还没有已安装的 Skills', Icons.psychology_alt_rounded),
          _categoryList('mcp', '还没有已安装的 MCP 服务', Icons.hub_rounded),
          _categoryList('plugin', '还没有已安装的插件', Icons.extension_rounded),
        ],
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
                        '你是 TideBot 插件开发助手。只输出一个严格 JSON 对象，不要 markdown。\\n$tideBotPluginGuide',
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
    Map<String, dynamic> manifest;
    try {
      final parsed = jsonDecode(_output);
      if (parsed is! Map) throw const FormatException('AI 输出不是 JSON');
      manifest = Map<String, dynamic>.from(parsed);
    } catch (_) {
      if (mounted) {
        GlobalNotice.show('请先生成有效插件清单', color: const Color(0xFFE74C3C));
      }
      return;
    }
    final report = PluginRegistry.validateManifest(manifest);
    if (!report.isSafe) {
      if (mounted) {
        GlobalNotice.show('校验失败：${report.message}',
            color: const Color(0xFFE74C3C));
      }
      return;
    }
    final category = PluginRegistry.categoryOf(manifest);
    final permissions = (manifest['permissions'] as List? ?? const [])
        .map((value) => value.toString())
        .join('、');
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认安装插件'),
        content: Text(
          '类型：${category == 'skill' ? 'Skills' : category == 'mcp' ? 'MCP' : '插件'}\n'
          '名称：${manifest['name'] ?? '未命名'}\n'
          '版本：${manifest['version'] ?? '未标注'}\n'
          '权限：${permissions.isEmpty ? '无' : permissions}\n\n'
          '${report.warnings.isEmpty ? '静态校验通过。' : '提示：${report.warnings.join('；')}'}\n\n'
          '安装后默认保持停用，需在详情页授权并完成健康检查后再启用。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('安装')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await PluginRegistry.installManifestBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
        expectedCategory: category,
      );
      if (mounted) {
        GlobalNotice.show(
            '插件已安装到${category == 'skill' ? 'Skills' : category == 'mcp' ? 'MCP' : '插件'}列表，请先授权并检测');
      }
    } catch (error) {
      if (mounted) {
        GlobalNotice.show('安装失败：$error', color: const Color(0xFFE74C3C));
      }
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
        appBar: AppBar(
          title: const Text('开发插件'),
          backgroundColor: theme.bgColor,
          actions: [
            IconButton(
              tooltip: '插件开发文档',
              icon: const Icon(Icons.menu_book_rounded),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PluginDevelopmentGuidePage())),
            ),
          ],
        ),
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
                        _output.isEmpty ? tideBotPluginGuide : _output,
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
