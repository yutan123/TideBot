import 'dart:convert';

import 'package:flutter/material.dart';

import 'plugin_ecosystem_page.dart';
import 'plugin_runtime.dart';
import 'plugin_security.dart';
import 'theme.dart';

class PluginDetailPage extends StatefulWidget {
  const PluginDetailPage({super.key, required this.plugin});
  final Map<String, dynamic> plugin;

  @override
  State<PluginDetailPage> createState() => _PluginDetailPageState();
}

class _PluginDetailPageState extends State<PluginDetailPage> {
  late Map<String, dynamic> _plugin;
  String _status = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _plugin = Map<String, dynamic>.from(widget.plugin);
  }

  Set<String> get _granted =>
      ((_plugin['granted_permissions'] as List?) ?? const [])
          .map((value) => value.toString())
          .toSet();

  List<String> get _permissions =>
      ((_plugin['permissions'] as List?) ?? const [])
          .map((value) => value.toString())
          .where((value) => value == PluginRuntime.permissionNetwork)
          .toList();

  Future<void> _save() async {
    final plugins = await PluginRegistry.load();
    final index = plugins.indexWhere((item) => item['id'] == _plugin['id']);
    if (index < 0) return;
    plugins[index] = _plugin;
    await PluginRegistry.save(plugins);
  }

  Future<void> _grant(String permission, bool enabled) async {
    final values = _granted;
    enabled ? values.add(permission) : values.remove(permission);
    setState(() => _plugin['granted_permissions'] = values.toList());
    await _save();
  }

  Future<void> _enableAfterHealthCheck() async {
    setState(() {
      _checking = true;
      _status = '正在进行首次可用性检测...';
    });
    try {
      final report = await PluginHealthChecker.check(_plugin);
      if (!report.isSafe) {
        if (mounted) setState(() => _status = '未通过检测：${report.message}');
        return;
      }
      _plugin['enabled'] = true;
      _plugin['needs_health_check'] = false;
      _plugin['health_checked_at'] = DateTime.now().millisecondsSinceEpoch;
      await _save();
      if (mounted)
        setState(() => _status =
            report.warnings.isEmpty ? '检测通过，插件已启用' : '检测通过。${report.message}');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _disable() async {
    _plugin['enabled'] = false;
    await _save();
    if (mounted) setState(() => _status = '插件已停用');
  }

  Future<void> _checkMcp() async {
    final servers = _plugin['mcp_servers'];
    if (servers is! List) return;
    setState(() {
      _checking = true;
      _status = '';
    });
    try {
      var count = 0;
      for (final raw in servers.whereType<Map>()) {
        count += await PluginRuntime.instance
            .listServerTools(_plugin, Map<String, dynamic>.from(raw))
            .then((tools) => tools.length);
      }
      if (mounted) setState(() => _status = 'MCP 已连接，发现 $count 个工具');
    } catch (error) {
      if (mounted) setState(() => _status = 'MCP 不可用：$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final skills = (_plugin['skills'] as List?)?.whereType<Map>().toList() ??
        const <Map>[];
    final servers =
        (_plugin['mcp_servers'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
          title: Text(_plugin['name']?.toString() ?? '插件'),
          backgroundColor: theme.bgColor),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(_plugin['description']?.toString() ?? '',
            style: TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _checking
              ? null
              : (_plugin['enabled'] == true
                  ? _disable
                  : _enableAfterHealthCheck),
          icon: Icon(_plugin['enabled'] == true
              ? Icons.pause_circle_outline_rounded
              : Icons.health_and_safety_rounded),
          label: Text(_plugin['enabled'] == true ? '停用插件' : '检测并启用'),
        ),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status,
                style:
                    TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
          ),
        if (skills.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Skills',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'TideFont')),
          for (final skill in skills)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.psychology_alt_rounded, color: theme.primary),
              title: Text(skill['name']?.toString() ?? 'Skill',
                  style: const TextStyle(fontFamily: 'TideFont')),
              subtitle: Text(skill['instructions']?.toString() ?? '',
                  style: const TextStyle(fontFamily: 'TideFont')),
            ),
        ],
        if (_permissions.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('权限',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'TideFont')),
          for (final permission in _permissions)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('网络访问（连接声明的 MCP 服务）',
                  style: TextStyle(fontFamily: 'TideFont')),
              value: _granted.contains(permission),
              onChanged: (value) => _grant(permission, value),
            ),
        ],
        if (servers.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('MCP 工具',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'TideFont')),
          for (final server in servers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.hub_rounded, color: theme.primary),
              title: Text(server['name']?.toString() ?? 'MCP Server',
                  style: const TextStyle(fontFamily: 'TideFont')),
              subtitle: Text(
                  server['url']?.toString() ??
                      server['endpoint']?.toString() ??
                      '',
                  style: const TextStyle(fontFamily: 'TideFont')),
            ),
          FilledButton.icon(
            onPressed:
                _checking || !_granted.contains(PluginRuntime.permissionNetwork)
                    ? null
                    : _checkMcp,
            icon: const Icon(Icons.link_rounded),
            label: Text(_checking ? '连接中' : '检查 MCP 工具'),
          ),
          if (_status.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status,
                    style: TextStyle(
                        color: theme.textWeak, fontFamily: 'TideFont'))),
        ],
        if (_plugin['ui'] is Map) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PluginUiPage(plugin: _plugin))),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('打开插件界面'),
          ),
        ],
      ]),
    );
  }
}

class PluginUiPage extends StatefulWidget {
  const PluginUiPage({super.key, required this.plugin});
  final Map<String, dynamic> plugin;

  @override
  State<PluginUiPage> createState() => _PluginUiPageState();
}

class _PluginUiPageState extends State<PluginUiPage> {
  final Map<String, TextEditingController> _controllers = {};
  String _result = '';
  bool _loading = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Map action) async {
    final servers = widget.plugin['mcp_servers'];
    final index = int.tryParse(action['mcp_server']?.toString() ?? '') ?? 0;
    final tool = action['tool']?.toString().trim() ?? '';
    if (servers is! List ||
        index < 0 ||
        index >= servers.length ||
        tool.isEmpty) {
      setState(() => _result = 'UI 动作配置无效');
      return;
    }
    if (!PluginRuntime.instance
        .hasPermission(widget.plugin, PluginRuntime.permissionNetwork)) {
      setState(() => _result = '请先在插件详情授予网络权限');
      return;
    }
    setState(() => _loading = true);
    try {
      final name =
          'plugin__${widget.plugin['id'].toString().replaceAll('-', '_').replaceAll('.', '_')}__${index}__${tool.replaceAll('-', '_')}';
      final response = await PluginRuntime.instance.executeToolCall(call: {
        'function': {
          'name': name,
          'arguments': jsonEncode({
            for (final entry in _controllers.entries)
              entry.key: entry.value.text
          }),
        },
      });
      if (mounted)
        setState(() => _result =
            const JsonEncoder.withIndent('  ').convert(response['result']));
    } catch (error) {
      if (mounted) setState(() => _result = '执行失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final ui = Map<String, dynamic>.from(widget.plugin['ui'] as Map);
    final fields =
        (ui['fields'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final actions =
        (ui['actions'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
          title: Text(ui['title']?.toString() ?? '插件界面'),
          backgroundColor: theme.bgColor),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (ui['description']?.toString().isNotEmpty == true)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(ui['description'].toString(),
                  style: TextStyle(
                      color: theme.textWeak, fontFamily: 'TideFont'))),
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _controllers.putIfAbsent(
                  field['id']?.toString() ?? 'field_${_controllers.length}',
                  () => TextEditingController(
                      text: field['default']?.toString() ?? '')),
              maxLines: field['multiline'] == true ? 4 : 1,
              decoration: InputDecoration(
                  labelText: field['label']?.toString() ??
                      field['id']?.toString() ??
                      '输入'),
            ),
          ),
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilledButton.icon(
              onPressed: _loading ? null : () => _run(action),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(action['label']?.toString() ?? '执行'),
            ),
          ),
        if (_result.isNotEmpty)
          SelectableText(_result,
              style: const TextStyle(fontFamily: 'monospace')),
      ]),
    );
  }
}
