import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Maps media references inside records and JSON encoded sharing payloads.
Future<dynamic> mapTransferValue(
  dynamic value,
  Future<String> Function(String) mapPath,
) async {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): await mapTransferValue(entry.value, mapPath),
    };
  }
  if (value is List) {
    return [for (final item in value) await mapTransferValue(item, mapPath)];
  }
  if (value is String) {
    final text = value.trimLeft();
    if (text.startsWith('{') || text.startsWith('[')) {
      dynamic decoded;
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        return mapPath(value);
      }
      final mapped = await mapTransferValue(decoded, mapPath);
      return jsonEncode(mapped) == jsonEncode(decoded)
          ? value
          : jsonEncode(mapped);
    }
    return mapPath(value);
  }
  return value;
}

/// Resolves only files actually present in an extracted media directory.
/// Relative subdirectories are retained; remote URLs and missing files survive.
class ImportedMedia {
  final Directory root;
  final String prefix;
  final bool allowLegacyBasename;

  ImportedMedia(
    this.root, {
    this.prefix = 'media',
    this.allowLegacyBasename = false,
  });

  Future<String> mapPath(String original) async {
    if (original.isEmpty) return original;
    final uri = Uri.tryParse(original);
    if (uri != null && uri.hasScheme && uri.scheme != 'file') return original;
    String path;
    try {
      path = uri?.scheme == 'file' ? uri!.toFilePath() : original;
    } on ArgumentError {
      return original;
    }
    path = path.replaceAll('\\', '/');
    if (path.split('/').contains('..')) return original;
    final marker = '/$prefix/';
    final index = path.indexOf(marker);
    String? relative;
    if (path.startsWith('$prefix/')) {
      relative = path.substring(prefix.length + 1);
    } else if (index >= 0) {
      relative = path.substring(index + marker.length);
    } else if (!p.posix.isAbsolute(path)) {
      relative = path;
    } else if (allowLegacyBasename) {
      relative = p.posix.basename(path);
    }
    if (relative == null) return original;
    final target = p.normalize(p.join(root.path, relative));
    if (!p.isWithin(root.path, target)) return original;
    return await File(target).exists() ? target : original;
  }
}

/// Relocates old application document paths using files in the staged backup.
class RestoredDocuments {
  final Directory staged;
  final Directory destination;

  RestoredDocuments(this.staged, this.destination);

  Future<String> mapPath(String original) async {
    final resolver = ImportedMedia(staged, prefix: 'app_flutter');
    var mapped = await resolver.mapPath(original);
    if (mapped == original) {
      mapped = await ImportedMedia(
        staged,
        prefix: 'documents',
      ).mapPath(original);
    }
    if (mapped == original || !p.isWithin(staged.path, mapped)) return original;
    return p.join(destination.path, p.relative(mapped, from: staged.path));
  }
}

/// Keeps all chat records exportable even when Android has cleared old media.
/// Existing files from an earlier package sandbox are resolved by relative path.
class TransferMedia {
  final Directory documents;
  final Directory temporary;
  final Map<String, String> files;
  final Map<String, String> _names = {};
  int missingReferences = 0;

  TransferMedia(this.documents, this.temporary, this.files);

  Future<String> mapPath(String original) async {
    if (original.isEmpty) return original;
    final uri = Uri.tryParse(original);
    if (uri != null && uri.hasScheme && uri.scheme != 'file') return original;
    final path = uri?.scheme == 'file' ? uri!.toFilePath() : original;
    if (!p.isAbsolute(path)) return original;
    final candidates = <String>[path];
    for (final entry in {
      '/app_flutter/': documents.path,
      '/cache/': temporary.path,
    }.entries) {
      final index = path.indexOf(entry.key);
      if (index < 0) continue;
      final candidate = p.normalize(
        p.join(entry.value, path.substring(index + entry.key.length)),
      );
      if (p.isWithin(entry.value, candidate)) candidates.add(candidate);
    }
    for (final candidate in candidates) {
      if (!await File(candidate).exists()) continue;
      return _names.putIfAbsent(candidate, () {
        final name = '${_names.length}_${p.basename(candidate)}';
        files['media/$name'] = candidate;
        return name;
      });
    }
    // Preserve the original reference and message instead of inventing content
    // or making a single stale attachment block the entire chat export.
    missingReferences++;
    return original;
  }
}
