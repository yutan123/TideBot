// Dart VM regression; does not build Flutter or Android.
import 'dart:io';
import 'package:tide_bot/transfer_media.dart';
import 'package:tide_bot/transfer_archive.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final work = await Directory(
    '${Directory.current.path}/.dart_tool',
  ).createTemp('transfer_media_test_');
  try {
    final documents = await Directory('${work.path}/app_flutter').create();
    final temporary = await Directory('${work.path}/cache').create();
    final image = File('${documents.path}/images/图片.jpg');
    await image.parent.create();
    await image.writeAsBytes([1, 2, 3]);
    final audio = File('${temporary.path}/audio.aac');
    await audio.writeAsBytes([4, 5]);
    final files = <String, String>{};
    final media = TransferMedia(documents, temporary, files);
    final imageName = await media.mapPath(
      '/data/user/0/com.old.app/app_flutter/images/图片.jpg',
    );
    check(
      files['media/$imageName'] == image.path,
      'Resolve old document sandbox',
    );
    check(
      await media.mapPath(image.uri.toString()) == imageName,
      'Deduplicate file URI and resolved path',
    );
    final audioName = await media.mapPath(
      '/data/user/0/com.old.app/cache/audio.aac',
    );
    check(files['media/$audioName'] == audio.path, 'Resolve old cache sandbox');
    const missing = '/data/user/0/com.old.app/app_flutter/deleted.jpg';
    check(
      await media.mapPath(missing) == missing,
      'Preserve missing reference',
    );
    check(media.missingReferences == 1, 'Report missing reference');
    const remote = 'https://example.com/image.jpg';
    check(await media.mapPath(remote) == remote, 'Preserve remote URL');
    check(await media.mapPath('') == '', 'Preserve empty reference');
    check(media.missingReferences == 1, 'Only missing local files count');
    final outside = File('${work.path}/outside.jpg');
    await outside.writeAsBytes([9]);
    await media.mapPath('/nonexistent/app_flutter/../outside.jpg');
    check(
      !files.containsValue(outside.path),
      'Reject sandbox traversal fallback',
    );
    final zip = '${work.path}/chat.zip';
    await writeTransferZip(zip, files);
    final restored = '${work.path}/restored';
    await extractTransferZip(zip, restored);
    check(
      await File('$restored/media/$imageName').length() == 3,
      'Recovered image survives ZIP round trip',
    );
    check(
      await File('$restored/media/$audioName').length() == 2,
      'Recovered audio survives ZIP round trip',
    );
    print(
      'PASS: old sandbox paths, file URIs, deduplication, missing media, '
      'remote references, traversal rejection and media ZIP round trip',
    );
  } finally {
    await work.delete(recursive: true);
  }
}
