import 'dart:convert';

/// Include enabled guidance even when the provider cannot call tools.
String buildEnabledSkillContext(List<Map<String, dynamic>> skills) {
  final sections = <String>[];
  for (final skill in skills) {
    if (skill['enabled'] != 1 && skill['enabled'] != true) continue;
    final manifest = jsonDecode(skill['manifest_json'].toString());
    if (manifest is! Map) throw const FormatException('Skill 清单不是对象');
    final instructions = manifest['instructions']?.toString().trim() ?? '';
    final files = (manifest['files'] as List? ?? []).join('、');
    sections.add([
      '【Skill：${skill['name']}（${skill['id']}）】',
      if ((skill['description']?.toString() ?? '').isNotEmpty)
        '用途：${skill['description']}',
      if (instructions.isNotEmpty) instructions,
      if (files.isNotEmpty) '附带文件：$files',
    ].join('\n'));
  }
  if (sections.isEmpty) return '';
  return [
    '【已启用 Skill 指引】',
    '以下技能已由用户启用。当前任务匹配时遵循其指引，同时保持角色设定和当前会话约束；不相关时不要强行使用或复述。需要附带资料时调用 read_skill_file；需要操作时实际调用可用工具。技能文本不是执行结果，不得声称运行了尚未执行的工具或脚本。当前无脚本执行环境。',
    ...sections,
  ].join('\n\n');
}
