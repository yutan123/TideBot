import 'dart:convert';

/// Model-facing catalog. Only public metadata and enabled tool schemas leave
/// this boundary; executor definitions, URLs and credentials stay in the app.
class ToolPackageCatalog {
  ToolPackageCatalog(
      {required List<Map<String, dynamic>> skills,
      required List<Map<String, dynamic>> servers,
      required List<Map<String, dynamic>> skillTools,
      required List<Map<String, dynamic>> mcpTools}) {
    for (final source in ['skill', 'mcp']) {
      for (final row in source == 'skill' ? skills : servers) {
        if (row['enabled'] != 1) continue;
        final id = row['id'].toString();
        try {
          final rows = (source == 'skill' ? skillTools : mcpTools)
              .where((t) =>
                  t[source == 'skill' ? 'skill_id' : 'server_id'] == id &&
                  t['enabled'] == 1 &&
                  (source != 'skill' ||
                      t['risk_level'] != 'sensitive' ||
                      t['authorized'] == 1))
              .toList()
            ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
          final tools = rows
              .map((t) => <String, dynamic>{
                    'name': t['name'],
                    'description': t['description'] ?? '',
                    'parameters':
                        jsonDecode(t['schema_json']?.toString() ?? '{}'),
                  })
              .toList();
          final manifest = source == 'skill'
              ? jsonDecode(row['manifest_json']?.toString() ?? '{}') as Map
              : const <String, dynamic>{};
          final files = manifest['files'] as List? ?? const [];
          if (source == 'skill' && files.isNotEmpty) {
            var readerName = 'read_skill_file';
            while (tools.any((t) => t['name'] == readerName)) {
              readerName = '_$readerName';
            }
            tools.add({
              'name': readerName,
              'reference_reader': true,
              'description': '读取本技能的文本参考资料、模板或脚本；脚本只能阅读，不能执行。',
              'parameters': {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                  'offset': {'type': 'integer', 'minimum': 0},
                },
                'required': ['path'],
                'additionalProperties': false
              }
            });
          }
          var description = row['description']?.toString().trim() ?? '';
          if (description.isEmpty && source == 'mcp') {
            description = row['service_description']?.toString().trim() ?? '';
          }
          if (description.isEmpty) {
            description = rows
                .take(3)
                .map((t) =>
                    (t['description']?.toString().trim().isNotEmpty ?? false)
                        ? t['description'].toString()
                        : t['name'].toString())
                .join('；');
          }
          if (description.isEmpty)
            description =
                source == 'skill' ? '读取技能指引并按指引完成任务。' : '提供 MCP 工具；查看包以了解可用能力。';
          _packages['$source:$id'] = {
            'package_id': '$source:$id',
            'name': row['name'] ?? id,
            'source': source,
            'description': description.length > 500
                ? '${description.substring(0, 500)}…'
                : description,
            'tool_count': tools.length,
            'tools': tools,
            if (source == 'skill') ...{
              'instructions': manifest['instructions'] ?? '',
              'files': files,
              'script_execution': '当前无脚本执行环境；不要声称已运行脚本。',
            },
          };
        } catch (_) {
          // A damaged imported package must not disable all other tools.
          print('[tool package] 无法读取 $source:$id，请重新导入或刷新工具');
        }
      }
    }
  }
  final _packages = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? get(String id) => _packages[id];
  List<Map<String, dynamic>> get summaries => (_packages.keys.toList()..sort())
      .map((id) => {
            for (final e in _packages[id]!.entries)
              if (const {
                'package_id',
                'name',
                'source',
                'description',
                'tool_count'
              }.contains(e.key))
                e.key: e.value
          })
      .toList();

  List<Map<String, dynamic>> schemas() {
    if (_packages.isEmpty) return [];
    Map<String, dynamic> tool(String name, String description,
            Map<String, dynamic> properties, List<String> required) =>
        {
          'type': 'function',
          'function': {
            'name': name,
            'description': description,
            'parameters': {
              'type': 'object',
              'properties': properties,
              'required': required,
              'additionalProperties': false
            }
          }
        };
    return [
      tool(
          'get_tool_package',
          '按任务选择工具包，查看包内工具的完整参数和技能指引；先查看再调用。目录只含摘要，不含工具定义。可用工具包：\n${jsonEncode(summaries)}',
          {
            'package_id': {'type': 'string'}
          },
          [
            'package_id'
          ]),
      tool(
          'call_package_tool',
          '按已查看工具包的参数结构调用包内工具。arguments 必须是 JSON 对象；失败时按错误修正。查看工具包不会启用工具或授予权限。',
          {
            'package_id': {'type': 'string'},
            'tool_name': {'type': 'string'},
            'arguments': {'type': 'object', 'additionalProperties': true}
          },
          [
            'package_id',
            'tool_name',
            'arguments'
          ])
    ];
  }
}
