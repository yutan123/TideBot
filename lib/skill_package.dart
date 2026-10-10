import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import 'skill_runtime.dart';

String skillToolName(Object? id, Object? name) =>
    'skill_${sha256.convert(utf8.encode('$id/$name')).toString().substring(0, 48)}';

class SkillPackage {
  final Map<String, dynamic> manifest;
  final Map<String, List<int>> files;
  SkillPackage(this.manifest, this.files);

  static String safePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        normalized.contains(':') ||
        normalized.split('/').any((part) => part == '..' || part.isEmpty)) {
      throw FormatException('技能包路径无效：$path');
    }
    return normalized;
  }

  static dynamic _yaml(String text) => jsonDecode(jsonEncode(loadYaml(text)));

  static SkillPackage parse(String name, List<int> bytes, {String? entry}) {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('文件为空或超过 10 MB');
    }
    final lower = name.toLowerCase();
    final files = <String, List<int>>{};
    if (lower.endsWith('.zip') ||
        lower.endsWith('.tideskill') ||
        lower.endsWith('.skill')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      if (archive.length > 500) throw const FormatException('压缩包超过 500 个文件');
      var total = 0;
      for (final file in archive) {
        if (!file.isFile) continue;
        final path = safePath(file.name);
        total += file.size;
        if (total > 30 * 1024 * 1024)
          throw const FormatException('解压内容超过 30 MB');
        if (files.containsKey(path)) throw FormatException('重复文件：$path');
        files[path] = file.content as List<int>;
      }
    } else {
      files[safePath(name)] = bytes;
    }
    final entries = files.keys
        .where((path) => path.split('/').last.toLowerCase() == 'skill.md')
        .toList();
    String selected;
    if (entry != null) {
      selected = entry;
    } else if (entries.length == 1) {
      selected = entries.single;
    } else if (entries.length > 1) {
      throw SkillEntryChoice(entries);
    } else {
      final manifests = files.keys
          .where((p) => p.split('/').last.toLowerCase() == 'manifest.json')
          .toList();
      if (manifests.length > 1) throw SkillEntryChoice(manifests);
      if (manifests.length == 1) {
        selected = manifests.single;
      } else if (files.length == 1 &&
          !lower.endsWith('.zip') &&
          !lower.endsWith('.skill') &&
          !lower.endsWith('.tideskill')) {
        selected = files.keys.single;
      } else {
        throw const FormatException('压缩包中未找到 SKILL.md 或 manifest.json');
      }
    }
    if (!files.containsKey(selected)) throw const FormatException('技能入口不存在');
    final root = selected.contains('/')
        ? selected.substring(0, selected.lastIndexOf('/') + 1)
        : '';
    final scoped = <String, List<int>>{
      for (final item in files.entries)
        if (item.key.startsWith(root))
          item.key.substring(root.length): item.value
    };
    final source = utf8.decode(files[selected]!).replaceFirst('\uFEFF', '');
    final extension = selected.split('.').last.toLowerCase();
    Map<String, dynamic> manifest;
    if ((extension == 'md' || extension == 'txt') &&
        !source.trimLeft().startsWith('{')) {
      var body = source.trim();
      var metadata = <String, dynamic>{};
      final header =
          RegExp(r'^---\s*\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)\s*(?:\r?\n|$)')
              .firstMatch(body);
      if (header != null) {
        final decoded = _yaml(header.group(1)!);
        if (decoded is! Map)
          throw const FormatException('SKILL.md 头信息必须是 YAML 对象');
        metadata = Map<String, dynamic>.from(decoded);
        body = body.substring(header.end).trim();
      }
      if (body.isEmpty) throw const FormatException('技能指引不能为空');
      final companion = scoped['manifest.json'];
      manifest = companion == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              jsonDecode(utf8.decode(companion)) as Map);
      final title = metadata['name']?.toString().trim();
      final fallback =
          selected.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), '');
      manifest = {
        'id':
            'doc-${sha256.convert(utf8.encode(title == null || title.isEmpty ? source : title)).toString().substring(0, 24)}',
        'name': title == null || title.isEmpty ? fallback : title,
        'version': metadata['version']?.toString() ?? '1.0.0',
        'description':
            metadata['description']?.toString() ?? body.split('\n').first,
        'tools': <dynamic>[],
        ...manifest,
        'instructions': body,
        'metadata': metadata,
        'entry_file': selected.substring(root.length),
      };
    } else {
      final decoded = extension == 'yaml' || extension == 'yml'
          ? _yaml(source)
          : jsonDecode(source);
      if (decoded is! Map) throw const FormatException('技能清单必须是对象');
      manifest = Map<String, dynamic>.from(decoded);
    }
    manifest['files'] = scoped.keys.toList()..sort();
    manifest['script_files'] = scoped.keys
        .where((p) => RegExp(r'\.(py|js|ts|sh|bash|rb)$', caseSensitive: false)
            .hasMatch(p))
        .toList();
    final validated = TideSkillValidator.validate(manifest);
    if (!validated.isValid) throw FormatException(validated.error!);
    return SkillPackage(validated.manifest!, scoped);
  }
}

class SkillEntryChoice implements Exception {
  final List<String> entries;
  SkillEntryChoice(this.entries);
}
