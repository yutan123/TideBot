import 'dart:convert';
import 'package:flutter/services.dart';
import 'db.dart';
import 'skill_package.dart';

class BuiltInSkillLoader {
  static Future<void> ensureBuiltInSkills() async {
    final db = DBManager();
    final builtInSkills = ['talk'];

    for (final skillId in builtInSkills) {
      try {
        // 检查是否已存在
        final existing = await db.querySkills();
        final found =
            existing.any((s) => s['id'] == skillId && s['built_in'] == 1);
        if (found) continue;

        // 从assets加载
        final content =
            await rootBundle.loadString('assets/skills/$skillId.md');
        final package = SkillPackage.parse('$skillId.md', utf8.encode(content));
        final manifest = package.manifest;

        // 保存内置skill
        await db.saveSkill({
          'id': skillId,
          'name': manifest['name'].toString(),
          'version': manifest['version']?.toString() ?? '1.0.0',
          'description': manifest['description']?.toString() ?? '',
          'manifest_json': jsonEncode(manifest),
          'enabled': 1,
          'built_in': 1,
          'recommended': 1,
          'status': 'ready',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, const []);
      } catch (error) {
        print('[built_in_skill] 加载 $skillId 失败: $error');
      }
    }
  }
}
