import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'skill_runtime.dart';
import 'theme.dart';
import 'ui_components.dart';

enum ToolManagerKind { skill, mcp }

class ToolManagerPage extends StatefulWidget {
  final ToolManagerKind kind;
  const ToolManagerPage({super.key, required this.kind});

  @override
  State<ToolManagerPage> createState() => _ToolManagerPageState();
}

class _ToolManagerPageState extends State<ToolManagerPage> {
  final _db = DBManager();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  bool get _isSkill => widget.kind == ToolManagerKind.skill;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows =
        _isSkill ? await _db.querySkills() : await _db.queryMcpServers();
    if (mounted)
      setState(() {
        _items = rows;
        _loading = false;
      });
  }

  Future<Map<String, dynamic>> _readSkillManifest(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('文件为空或超过 10 MB');
    }
    final lower = file.name.toLowerCase();
    if (lower.endsWith('.json')) return jsonDecode(utf8.decode(bytes));
    if (!lower.endsWith('.zip') && !lower.endsWith('.tideskill')) {
      throw const FormatException('仅支持 JSON、ZIP 或 TIDESKILL');
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.length > 100) throw const FormatException('压缩包文件数量超过限制');
    ArchiveFile? manifestFile;
    for (final entry in archive) {
      final normalized = entry.name.replaceAll('\\', '/');
      if (normalized.startsWith('/') || normalized.split('/').contains('..')) {
        throw const FormatException('压缩包包含不安全路径');
      }
      if (normalized == 'manifest.json') manifestFile = entry;
    }
    if (manifestFile == null)
      throw const FormatException('压缩包缺少 manifest.json');
    return jsonDecode(utf8.decode(manifestFile.content as List<int>));
  }

  Future<void> _storeSkillPackage(String id, PlatformFile file) async {
    final dir = await getApplicationDocumentsDirectory();
    final skillDir = Directory('${dir.path}/skills/$id');
    await skillDir.create(recursive: true);
    final bytes = file.bytes!;
    final lower = file.name.toLowerCase();
    if (lower.endsWith('.json')) {
      await File('${skillDir.path}/manifest.json')
          .writeAsBytes(bytes, flush: true);
      return;
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      final normalized = entry.name.replaceAll('\\', '/');
      if (entry.isFile) {
        final target = File('${skillDir.path}/$normalized');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.content as List<int>, flush: true);
      }
    }
  }

  Future<void> _addSkill() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['json', 'zip', 'tideskill'],
    );
    if (result == null) return;
    try {
      final file = result.files.single;
      final manifest =
          TideSkillValidator.validate(await _readSkillManifest(file));
      if (!manifest.isValid) {
        throw FormatException(manifest.error ?? 'manifest 无效');
      }
      final validatedManifest = manifest.manifest!;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = validatedManifest['id'].toString();
      await _storeSkillPackage(id, file);
      final tools =
          (validatedManifest['tools'] as List).map<Map<String, dynamic>>((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        return {
          'id': 'skill_tool_${id}_${item['name']}',
          'skill_id': id,
          'name': item['name'].toString(),
          'description': item['description']?.toString() ?? '',
          'executor': item['executor'].toString(),
          'schema_json': jsonEncode(item['input_schema'] ?? {'type': 'object'}),
          'risk_level': item['risk_level']?.toString() ?? 'normal',
          'authorized': 0,
          'enabled': item['risk_level']?.toString() == 'sensitive' ? 0 : 1,
        };
      }).toList();
      await _db.saveSkill({
        'id': id,
        'name': validatedManifest['name'].toString(),
        'version': validatedManifest['version'].toString(),
        'description': validatedManifest['description']?.toString() ?? '',
        'manifest_json': jsonEncode(validatedManifest),
        'enabled': 1,
        'status': 'ready',
        'updated_at': now,
      }, tools);
      await _reload();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
  }

  Future<void> _discoverMcp(
    String id,
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await _db.updateMcpStatus(id, 'connecting');
    final client = McpClient(url: url, headers: headers, timeout: timeout);
    try {
      await client.initialize();
      final tools = await client.listTools();
      final resources = await client.listResourcesSafe();
      final prompts = await client.listPromptsSafe();
      await _db.saveMcpTools(id, tools);
      await _db.saveMcpMetadata(id, resources: resources, prompts: prompts);
      await _reload();
    } catch (error) {
      await _db.updateMcpStatus(id, 'error', McpClient.describeError(error));
      await _reload();
    } finally {
      try {
        await client.close();
      } finally {
        client.dispose();
      }
    }
  }

  Future<void> _addMcp() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final token = TextEditingController();
    final timeoutSeconds = TextEditingController(text: '20');
    var autoConnect = false;
    final accepted = await TideDialogs.show<bool>(
      context: context,
      builder: (dialogContext) => TideDialogSurface(
        contentPadding: EdgeInsets.zero,
        content: TideDialogs.glassContent(
          context: dialogContext,
          children: [
            const Text('添加 MCP 服务',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '名称')),
            TextField(
                controller: url,
                decoration:
                    const InputDecoration(labelText: 'Streamable HTTP URL')),
            TextField(
                controller: token,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Bearer Token（可选）')),
            TextField(
                controller: timeoutSeconds,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '超时秒数')),
            StatefulBuilder(
              builder: (context, setDialogState) => Row(
                children: [
                  Expanded(
                      child: Text('保存后自动连接',
                          style: TextStyle(
                              color: TideTheme.of(context).textStrong))),
                  Switch(
                      value: autoConnect,
                      onChanged: (value) =>
                          setDialogState(() => autoConnect = value)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: TideDialogs.glassButton('取消',
                        onTap: () => Navigator.pop(dialogContext, false),
                        color: TideTheme.of(dialogContext).surface,
                        textColor: TideTheme.of(dialogContext).textStrong)),
                const SizedBox(width: 10),
                Expanded(
                    child: TideDialogs.glassButton('保存',
                        onTap: () => Navigator.pop(dialogContext, true))),
              ],
            ),
          ],
        ),
      ),
    );
    if (accepted != true ||
        name.text.trim().isEmpty ||
        Uri.tryParse(url.text.trim())?.hasScheme != true) return;
    final timeoutMs =
        (int.tryParse(timeoutSeconds.text.trim()) ?? 20).clamp(5, 120) * 1000;
    final id = 'mcp_${DateTime.now().millisecondsSinceEpoch}';
    await _db.saveMcpServer({
      'id': id,
      'name': name.text.trim(),
      'url': url.text.trim(),
      'headers_key': null,
      'timeout_ms': timeoutMs,
      'auto_connect': autoConnect ? 1 : 0,
      'resources_json': '[]',
      'prompts_json': '[]',
      'enabled': 1,
      'status': 'disconnected',
      'error': null,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    final headers = <String, String>{
      if (token.text.trim().isNotEmpty)
        'Authorization': 'Bearer ${token.text.trim()}',
    };
    if (headers.isNotEmpty) {
      await const FlutterSecureStorage()
          .write(key: 'mcp_headers_$id', value: jsonEncode(headers));
    }
    await _reload();
    await _discoverMcp(
      id,
      url.text.trim(),
      headers: headers,
      timeout: Duration(milliseconds: timeoutMs),
    );
  }

  Future<void> _showDetails(Map<String, dynamic> item) async {
    final id = item['id'].toString();
    final tools =
        _isSkill ? await _db.querySkillTools(id) : await _db.queryMcpTools(id);
    if (!mounted) return;
    await showTideSheet<void>(
      context: context,
      height: MediaQuery.sizeOf(context).height * .72,
      child: Builder(
        builder: (sheetContext) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text(item['name']?.toString() ?? '',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(_isSkill
                  ? (item['description']?.toString() ?? '')
                  : '${item['url']}\n状态：${item['status']}'),
              const SizedBox(height: 16),
              Text(_isSkill ? '工具' : '已发现工具',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final tool in tools)
                _ToolToggleRow(
                  title: tool['name']?.toString() ?? '',
                  subtitle: [
                    tool['description']?.toString() ?? '',
                    if (_isSkill && tool['risk_level'] == 'sensitive') '需要授权',
                  ].where((value) => value.isNotEmpty).join(' · '),
                  value: tool['enabled'] == 1,
                  onChanged: (enabled) async {
                    if (_isSkill &&
                        enabled &&
                        tool['risk_level'] == 'sensitive' &&
                        tool['authorized'] != 1) {
                      final approved = await TideDialogs.show<bool>(
                        context: sheetContext,
                        builder: (dialogContext) => TideDialogSurface(
                          content: TideDialogs.glassContent(
                            context: dialogContext,
                            children: [
                              const Text('授权敏感工具',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 10),
                              Text('允许 ${tool['name']} 访问其声明的外部能力。可随时在此处撤销授权。'),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TideDialogs.glassButton('取消',
                                        onTap: () =>
                                            Navigator.pop(dialogContext, false),
                                        color:
                                            TideTheme.of(dialogContext).surface,
                                        textColor: TideTheme.of(dialogContext)
                                            .textStrong),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TideDialogs.glassButton('授权',
                                        onTap: () =>
                                            Navigator.pop(dialogContext, true)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                      if (approved != true) return;
                      await _db.setSkillToolAuthorized(
                          tool['id'].toString(), true);
                    }
                    if (_isSkill) {
                      await _db.setSkillToolEnabled(
                          tool['id'].toString(), enabled);
                    } else {
                      await _db.setMcpToolEnabled(
                          tool['id'].toString(), enabled);
                    }
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    await _reload();
                    if (mounted) _showDetails(item);
                  },
                ),
              if (!_isSkill) ...[
                const SizedBox(height: 12),
                _McpCachedMetadata(
                  label: '资源',
                  rawJson: item['resources_json']?.toString() ?? '[]',
                  nameKey: 'name',
                ),
                const SizedBox(height: 12),
                _McpCachedMetadata(
                  label: '提示词',
                  rawJson: item['prompts_json']?.toString() ?? '[]',
                  nameKey: 'name',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_isSkill ? 'Skill 管理' : 'MCP 管理'),
        actions: [
          IconButton(
            tooltip: '添加',
            icon: const Icon(Icons.add_rounded),
            onPressed: _isSkill ? _addSkill : _addMcp,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(_isSkill ? '暂无 Skill' : '暂无 MCP 服务'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: theme.surface.withValues(alpha: .62),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.border),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showDetails(item),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['name']?.toString() ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isSkill
                                          ? 'v${item['version']} · ${item['status']}'
                                          : '${item['url']} · ${item['status']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: theme.textFaint, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: item['enabled'] == 1,
                                onChanged: (enabled) async {
                                  if (_isSkill) {
                                    await _db.setSkillEnabled(
                                        item['id'].toString(), enabled);
                                  } else {
                                    await _db.setMcpServerEnabled(
                                        item['id'].toString(), enabled);
                                    if (enabled) await _connectMcpItem(item);
                                  }
                                  await _reload();
                                },
                              ),
                              IconButton(
                                tooltip: '刷新连接',
                                icon: const Icon(Icons.refresh_rounded),
                                onPressed: _isSkill || item['enabled'] != 1
                                    ? null
                                    : () => _connectMcpItem(item),
                              ),
                              IconButton(
                                tooltip: '删除',
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => _deleteItem(item),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _connectMcpItem(Map<String, dynamic> item) async {
    final stored = await const FlutterSecureStorage()
        .read(key: 'mcp_headers_${item['id']}');
    final headers = stored == null
        ? const <String, String>{}
        : Map<String, String>.from(jsonDecode(stored) as Map);
    await _discoverMcp(
      item['id'].toString(),
      item['url'].toString(),
      headers: headers,
      timeout: Duration(
          milliseconds: (item['timeout_ms'] as num?)?.toInt() ?? 20000),
    );
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final confirmed = await TideDialogs.show<bool>(
      context: context,
      builder: (dialogContext) => TideDialogSurface(
        content: TideDialogs.glassContent(
          context: dialogContext,
          children: [
            const Text('确认删除',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('删除“${item['name']}”后，其配置和工具状态将被移除。'),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: TideDialogs.glassButton('取消',
                      onTap: () => Navigator.pop(dialogContext, false),
                      color: TideTheme.of(dialogContext).surface,
                      textColor: TideTheme.of(dialogContext).textStrong)),
              const SizedBox(width: 10),
              Expanded(
                  child: TideDialogs.glassButton('删除',
                      onTap: () => Navigator.pop(dialogContext, true))),
            ]),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final id = item['id'].toString();
    if (_isSkill) {
      await _db.deleteSkill(id);
    } else {
      await _db.deleteMcpServer(id);
      await const FlutterSecureStorage().delete(key: 'mcp_headers_$id');
    }
    await _reload();
  }
}

class _ToolToggleRow extends StatelessWidget {
  const _ToolToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.border.withValues(alpha: .7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textFaint, fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _McpCachedMetadata extends StatelessWidget {
  const _McpCachedMetadata({
    required this.label,
    required this.rawJson,
    required this.nameKey,
  });

  final String label;
  final String rawJson;
  final String nameKey;

  @override
  Widget build(BuildContext context) {
    List<dynamic> entries;
    try {
      final decoded = jsonDecode(rawJson);
      entries = decoded is List ? decoded : const [];
    } catch (_) {
      entries = const [];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('暂无缓存内容', style: TextStyle(color: Colors.grey)),
          ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TideTheme.of(context).surface.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry is Map
                      ? entry[nameKey]?.toString() ?? '未命名'
                      : entry.toString()),
                  if (entry is Map && entry['description'] != null) ...[
                    const SizedBox(height: 3),
                    Text(entry['description'].toString(),
                        style: TextStyle(
                            color: TideTheme.of(context).textFaint,
                            fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
