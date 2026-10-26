import 'dart:convert';
import 'package:flutter/services.dart';
import 'db.dart';
import 'skill_package.dart';

class BuiltInSkillLoader {
  static Future<void> ensureBuiltInSkills() async {
    final db = DBManager();
    // 旧版本误把内置视频工具的说明安装成了 Skill。
    await db.removeLegacyVideoSkill();
    final builtInSkills = ['talk'];

    for (final skillId in builtInSkills) {
      try {
        final existing = await db.querySkills();
        final matches = existing.where((s) => s['id'] == skillId);
        final installed = matches.isEmpty ? null : matches.first;
        // A user-installed skill with the same ID is not an app-owned asset.
        if (installed != null && installed['built_in'] != 1) continue;

        // 从assets加载
        final content =
            await rootBundle.loadString('assets/skills/$skillId.md');
        final package = SkillPackage.parse('$skillId.md', utf8.encode(content));
        final manifest = package.manifest;
        final manifestJson = jsonEncode(manifest);
        if (installed != null) {
          if (installed['manifest_json'] == manifestJson) continue;
          // Refresh bundled instructions without resetting the user's switches.
          await (await db.database).update(
              'skills',
              {
                'name': manifest['name'].toString(),
                'version': manifest['version']?.toString() ?? '1.0.0',
                'description': manifest['description']?.toString() ?? '',
                'manifest_json': manifestJson,
                'updated_at': DateTime.now().millisecondsSinceEpoch,
              },
              where: 'id = ? AND built_in = 1',
              whereArgs: [skillId]);
          continue;
        }

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
