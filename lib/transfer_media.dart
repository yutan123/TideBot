import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Walks JSON stored inside database strings as well as ordinary maps/lists.
/// Only local file references are rewritten; URLs and conversational text stay intact.
Future<dynamic> mapTransferValue(
  dynamic value,
  Future<String> Function(String) mapPath,
) async {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key: await mapTransferValue(entry.value, mapPath),
    };
  }
  if (value is List) {
    return [for (final item in value) await mapTransferValue(item, mapPath)];
  }
  if (value is! String || value.isEmpty) return value;
  final trimmed = value.trim();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    dynamic decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      // A normal message can begin with a bracket.
    }
    if (decoded is Map || decoded is List) {
      final mapped = await mapTransferValue(decoded, mapPath);
      final encoded = jsonEncode(mapped);
      return encoded == jsonEncode(decoded) ? value : encoded;
    }
  }
  return mapPath(value);
}

bool isTransferPath(String value) =>
    value.startsWith('file:') ||
    value.startsWith('/data/') ||
    value.startsWith('/storage/') ||
    value.startsWith('/sdcard/') ||
    value.startsWith('/private/var/') ||
    value.startsWith('/var/mobile/');

class TransferMedia {
  TransferMedia({
    required this.documents,
    required this.temporary,
    required this.files,
  });
  final Directory documents;
  final Directory temporary;
  final Map<String, String> files;
  final Map<String, String> references = {};
  final Map<String, String> _names = {};

  Future<String> collect(String original) async {
    if (original.isEmpty || !isTransferPath(original)) return original;
    if (references.containsKey(original)) return references[original]!;
    final uri = Uri.tryParse(original);
    final path = uri?.scheme == 'file' ? uri!.toFilePath() : original;
    if (await Directory(path).exists()) return original;
    File source = File(path);
    if (!await source.exists()) {
      // Older installations can have a different application id or sandbox root.
      for (final root in {
        '/app_flutter/': documents,
        '/cache/': temporary,
      }.entries) {
        final index = path.indexOf(root.key);
        if (index < 0) continue;
        final relative = path.substring(index + root.key.length);
        final candidate = p.normalize(p.join(root.value.path, relative));
        if (!p.isWithin(root.value.path, candidate)) continue;
        final restored = File(candidate);
        if (await restored.exists()) {
          source = restored;
          break;
        }
      }
    }
    if (!await source.exists()) {
      // Keep the record even when its attachment has already been deleted.
      // Do not register an archive entry for a file that cannot be recovered.
      return original;
    }
    final canonical = await source.resolveSymbolicLinks();
    final name = _names.putIfAbsent(canonical, () {
      final documentEntry =
          'documents/${p.relative(source.path, from: documents.path)}';
      if (files[documentEntry] == source.path) return documentEntry;
      final name = 'media/${_names.length}_${p.basename(source.path)}';
      files[name] = source.path;
      return name;
    });
    references[original] = name;
    return name;
  }
}

/// Resolves references before any live database or documents are replaced.
class BackupMediaRestore {
  BackupMediaRestore._(this.documents, this.oldDocuments, this.references);
  final Directory documents;
  final String? oldDocuments;
  final Map<String, String> references;

  static Future<BackupMediaRestore> load({
    required Directory archive,
    required Directory documents,
    required Directory media,
  }) async {
    final manifestFile = File('${archive.path}/media_manifest.json');
    final references = <String, String>{};
    String? oldDocuments;
    if (await manifestFile.exists()) {
      final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
      if (manifest['version'] != 1) throw const FormatException('不支持的媒体清单版本');
      oldDocuments = manifest['documents_root'] as String?;
      for (final entry in (manifest['references'] as Map).entries) {
        final name = entry.value as String;
        final source = p.normalize(p.join(archive.path, name));
        if ((!name.startsWith('media/') && !name.startsWith('documents/')) ||
            name.contains('\\') ||
            !p.isWithin(archive.path, source)) {
          throw const FormatException('备份媒体路径无效');
        }
        if (!await File(source).exists())
          throw FormatException('备份缺少媒体文件：$name');
        final targetRoot = name.startsWith('documents/')
            ? documents.path
            : media.path;
        final relative = name.substring(name.indexOf('/') + 1);
        final target = p.normalize(p.join(targetRoot, relative));
        if (!p.isWithin(targetRoot, target))
          throw const FormatException('备份媒体路径无效');
        references[entry.key as String] = target;
      }
    }
    return BackupMediaRestore._(documents, oldDocuments, references);
  }

  Future<String> mapPath(String path) async {
    final mapped = references[path];
    if (mapped != null) return mapped;
    if (!isTransferPath(path)) return path;
    final local = path.startsWith('file:')
        ? Uri.parse(path).toFilePath()
        : path;
    String? relative;
    final oldRoot = oldDocuments;
    if (oldRoot != null && p.isWithin(oldRoot, local)) {
      relative = p.relative(local, from: oldRoot);
    } else {
      // Compatibility with full backups created before the media manifest.
      final marker = local.indexOf('/app_flutter/');
      if (marker >= 0)
        relative = local.substring(marker + '/app_flutter/'.length);
    }
    if (relative == null) return path;
    final target = p.normalize(p.join(documents.path, relative));
    if (!p.isWithin(documents.path, target))
      throw const FormatException('备份文件路径无效');
    return target;
  }
}
