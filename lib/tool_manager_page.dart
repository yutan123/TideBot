import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'skill_runtime.dart';

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
          'enabled': 1,
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

  Future<void> _discoverMcp(String id, String url,
      {Map<String, String> headers = const {}}) async {
    await _db.updateMcpStatus(id, 'connecting');
    try {
      final client = McpClient(url: url, headers: headers);
      await client.initialize();
      final tools = await client.listTools();
      await _db.saveMcpTools(id, tools);
      await _reload();
    } catch (error) {
      await _db.updateMcpStatus(id, 'error', error.toString());
      await _reload();
    }
  }

  Future<void> _addMcp() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final token = TextEditingController();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('添加 MCP 服务'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '名称')),
                TextField(
                    controller: url,
                    decoration: const InputDecoration(
                        labelText: 'Streamable HTTP URL')),
                TextField(
                    controller: token,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Bearer Token（可选）')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('保存'))
              ],
            ));
    if (accepted != true ||
        name.text.trim().isEmpty ||
        Uri.tryParse(url.text.trim())?.hasScheme != true) return;
    final id = 'mcp_${DateTime.now().millisecondsSinceEpoch}';
    await _db.saveMcpServer({
      'id': id,
      'name': name.text.trim(),
      'url': url.text.trim(),
      'headers_key': null,
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
    await _discoverMcp(id, url.text.trim(), headers: headers);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isSkill ? 'Skill 管理' : 'MCP 管理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(_isSkill ? '暂无 Skill' : '暂无 MCP 服务'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      title: Text(item['name']?.toString() ?? ''),
                      subtitle: Text(_isSkill
                          ? 'v${item['version']} · ${item['status']}'
                          : '${item['url']} · ${item['status']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: item['enabled'] == 1,
                            onChanged: (enabled) async {
                              if (_isSkill) {
                                await _db.setSkillEnabled(
                                    item['id'].toString(), enabled);
                              } else {
                                await _db.setMcpServerEnabled(
                                    item['id'].toString(), enabled);
                                if (enabled) {
                                  final stored =
                                      await const FlutterSecureStorage().read(
                                          key: 'mcp_headers_${item['id']}');
                                  final headers = stored == null
                                      ? const <String, String>{}
                                      : Map<String, String>.from(
                                          jsonDecode(stored) as Map);
                                  await _discoverMcp(item['id'].toString(),
                                      item['url'].toString(),
                                      headers: headers);
                                }
                              }
                              await _reload();
                            },
                          ),
                          IconButton(
                            tooltip: '刷新连接',
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: _isSkill || item['enabled'] != 1
                                ? null
                                : () async {
                                    final stored =
                                        await const FlutterSecureStorage().read(
                                            key: 'mcp_headers_${item['id']}');
                                    final headers = stored == null
                                        ? const <String, String>{}
                                        : Map<String, String>.from(
                                            jsonDecode(stored) as Map);
                                    await _discoverMcp(item['id'].toString(),
                                        item['url'].toString(),
                                        headers: headers);
                                  },
                          ),
                          IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final id = item['id'].toString();
                              if (_isSkill) {
                                await _db.deleteSkill(id);
                              } else {
                                await _db.deleteMcpServer(id);
                                await const FlutterSecureStorage()
                                    .delete(key: 'mcp_headers_$id');
                              }
                              await _reload();
                            },
                          ),
                        ],
                      ),
                    );
                  }),
      floatingActionButton: FloatingActionButton(
          onPressed: _isSkill ? _addSkill : _addMcp,
          child: const Icon(Icons.add)),
    );
  }
}
