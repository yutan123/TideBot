import 'dart:io';
import 'package:path/path.dart' as p;

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
