import 'dart:io';

import 'package:path/path.dart' as p;

/// Releases the file picker's copy after its final reader has finished.
/// Import workspaces and rollback data have a separate lifetime.
Future<T> consumePickedImport<T>(
  String sourcePath,
  Directory temporary,
  Future<T> Function() read,
) async {
  try {
    return await read();
  } finally {
    await removePickedImportCopy(sourcePath, temporary);
  }
}

/// Deletes only the selected copy in Android's file_picker cache. In particular,
/// never delete the user's original or unrelated picker/media cache files.
Future<bool> removePickedImportCopy(
  String sourcePath,
  Directory temporary,
) async {
  final root = Directory(p.join(temporary.path, 'file_picker'));
  final source = File(p.normalize(p.absolute(sourcePath)));
  try {
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final cachePath = await temporary.resolveSymbolicLinks();
    final rootPath = await root.resolveSymbolicLinks();
    final filePath = await source.resolveSymbolicLinks();
    if (!p.isWithin(cachePath, rootPath) || !p.isWithin(rootPath, filePath)) {
      return false;
    }
    await source.delete();
    var parent = Directory(p.dirname(filePath));
    while (p.isWithin(rootPath, parent.path)) {
      if (!await parent.list(followLinks: false).isEmpty) break;
      await parent.delete();
      parent = parent.parent;
    }
    return true;
  } on FileSystemException {
    // A cleanup failure must not replace a successful import or its real error.
    return false;
  }
}
