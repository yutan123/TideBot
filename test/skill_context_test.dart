import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/skill_context.dart';

void main() {
  Map<String, dynamic> skill(String id, int enabled, String instructions) => {
        'id': id,
        'name': id,
        'description': '测试用途',
        'enabled': enabled,
        'manifest_json': jsonEncode({
          'instructions': instructions,
          'files': ['references/example.md'],
          'tools': []
        }),
      };
  test(
      'enabled instruction-only skills include complete guidance and resources',
      () {
    final text = buildEnabledSkillContext(
        [skill('enabled', 1, '先执行步骤一\n然后执行步骤二'), skill('disabled', 0, '不能注入')]);
    expect(text, contains('先执行步骤一\n然后执行步骤二'));
    expect(text, contains('references/example.md'));
    expect(text, isNot(contains('不能注入')));
    expect(text, contains('当前无脚本执行环境'));
  });
  test(
      'tool-only skills remain discoverable and no enabled skill adds no context',
      () {
    expect(buildEnabledSkillContext([skill('http_skill', 1, '')]),
        contains('http_skill'));
    expect(buildEnabledSkillContext([skill('off', 0, '说明')]), isEmpty);
  });
}
