import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/skill_package.dart';

List<int> zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final data = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, data.length, data));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  test('Markdown YAML metadata and body are available without tools', () {
    final package = SkillPackage.parse(
        'SKILL.md',
        utf8.encode(
            '---\nname: 写作\ndescription: |\n  帮助写作\nmetadata:\n  author: test\n---\n先阅读需求，再写作。'));
    expect(package.manifest['name'], '写作');
    expect(package.manifest['description'], contains('帮助写作'));
    expect(package.manifest['instructions'], '先阅读需求，再写作。');
    expect(package.manifest['tools'], isEmpty);
    expect(package.files.keys, contains('SKILL.md'));
  });
  test('plain Markdown imports without metadata', () {
    final package = SkillPackage.parse('写作.md', utf8.encode('# 写作\n认真阅读需求。'));
    expect(package.manifest['name'], '写作');
    expect(package.manifest['instructions'], contains('认真阅读'));
  });
  test('wrapped package combines instructions, tools and resources', () {
    final package = SkillPackage.parse(
        'skill.zip',
        zip({
          'weather/SKILL.md':
              '---\nname: weather\n---\n调用天气工具，参考 references/help.md。',
          'weather/manifest.json': jsonEncode({
            'id': 'weather_skill',
            'name': 'Weather',
            'version': '1',
            'tools': [
              {
                'name': 'get_weather',
                'executor': 'http',
                'url': 'https://example.com'
              }
            ]
          }),
          'weather/references/help.md': '说明',
          'weather/scripts/run.py': 'print(1)',
        }));
    expect(package.manifest['id'], 'weather_skill');
    expect(package.manifest['tools'], hasLength(1));
    expect(package.files['references/help.md'], utf8.encode('说明'));
    expect(package.manifest['script_files'], ['scripts/run.py']);
  });
  test('legacy JSON and real YAML manifests import', () {
    final manifest = {
      'id': 'old',
      'name': 'Old',
      'version': '1',
      'tools': [
        {'name': 'guide', 'executor': 'prompt', 'prompt': 'Help'}
      ]
    };
    expect(
        SkillPackage.parse('manifest.json', utf8.encode(jsonEncode(manifest)))
            .manifest['tools'],
        hasLength(1));
    expect(
        SkillPackage.parse(
                'skill.yaml',
                utf8.encode(
                    'id: yaml\nname: YAML\nversion: "1"\ninstructions: Help'))
            .manifest['instructions'],
        'Help');
  });
  test('multiple entries require explicit selection with isolated files', () {
    final bytes = zip({'a/SKILL.md': 'A', 'b/SKILL.md': 'B'});
    expect(() => SkillPackage.parse('bundle.zip', bytes),
        throwsA(isA<SkillEntryChoice>()));
    final package =
        SkillPackage.parse('bundle.zip', bytes, entry: 'b/SKILL.md');
    expect(package.manifest['instructions'], 'B');
    expect(package.files.keys, ['SKILL.md']);
  });
  test('rejects traversal, empty guide, broken metadata and missing entry', () {
    expect(() => SkillPackage.parse('bad.zip', zip({'../SKILL.md': 'Bad'})),
        throwsFormatException);
    expect(() => SkillPackage.parse('SKILL.md', utf8.encode(' ')),
        throwsFormatException);
    expect(
        () => SkillPackage.parse(
            'SKILL.md', utf8.encode('---\n- list\n---\nBody')),
        throwsFormatException);
    expect(() => SkillPackage.parse('bad.zip', zip({'readme.txt': 'Hello'})),
        throwsFormatException);
  });
  test('legacy disguised JSON and skill extension remain compatible', () {
    final source = jsonEncode({
      'id': 'legacy',
      'name': 'Legacy',
      'version': '1',
      'tools': [
        {'name': 'guide', 'executor': 'prompt', 'prompt': 'Help'}
      ]
    });
    expect(SkillPackage.parse('legacy.md', utf8.encode(source)).manifest['id'],
        'legacy');
    expect(
        SkillPackage.parse(
                'example.skill', zip({'SKILL.md': 'Use existing tools.'}))
            .manifest['instructions'],
        'Use existing tools.');
    expect(
        () => SkillPackage.parse(
            'manifest.json',
            utf8.encode(jsonEncode({
              'id': '..',
              'name': 'Bad',
              'version': '1',
              'instructions': 'Bad'
            }))),
        throwsFormatException);
  });
  test('tool names are provider compatible and unambiguous with underscores',
      () {
    final first = skillToolName('a_b', 'c');
    expect(first, matches(RegExp(r'^[a-zA-Z0-9_-]{1,64}$')));
    expect(first, isNot(skillToolName('a', 'b_c')));
    expect(first, skillToolName('a_b', 'c'));
  });
}
