// Dart VM regression; does not compile Flutter or Android.
import 'dart:io';
import 'package:tide_bot/transfer_import_cache.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final work = await Directory(
    '${Directory.current.path}/.dart_tool',
  ).createTemp('import_cache_test_');
  Future<File> write(String path, [String value = 'backup']) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsString(value);
  }

  try {
    final cache = await Directory('${work.path}/cache').create();
    final source = await write('${cache.path}/file_picker/100/backup.zip');
    final other = await write('${cache.path}/file_picker/200/chat.jpg');
    final media = await write(
      '${work.path}/documents/imported_media/image.jpg',
    );
    final rollback = await write(
      '${cache.path}/tidebot_transfer_recovery/rollback/tidebot.db',
    );
    final result = await consumePickedImport(source.path, cache, () async {
      check(await source.exists(), 'Input exists during import');
      check(await source.readAsString() == 'backup', 'Importer can read input');
      return 17;
    });
    check(result == 17, 'Preserve import result');
    check(!await source.exists(), 'Remove cached ZIP after success');
    check(!await source.parent.exists(), 'Remove empty picker batch directory');
    check(await other.exists(), 'Keep unrelated picked media');
    check(await media.exists(), 'Keep installed media');
    check(await rollback.exists(), 'Keep recovery data');

    for (final name in ['chat.json', 'world_book.json', 'broken.zip']) {
      final failed = await write('${cache.path}/file_picker/300/$name');
      final expected = FormatException('invalid $name');
      Object? error;
      try {
        await consumePickedImport<void>(failed.path, cache, () async {
          throw expected;
        });
      } catch (caught) {
        error = caught;
      }
      check(identical(error, expected), 'Keep original import failure');
      check(!await failed.exists(), 'Release cached input after failed import');
    }

    final original = await write('${work.path}/Downloads/backup.zip');
    await consumePickedImport(original.path, cache, () async => 1);
    check(await original.exists(), 'Never delete original in Downloads');
    final unrelated = await write('${cache.path}/audio.aac');
    check(
      !await removePickedImportCopy(unrelated.path, cache),
      'Only picker copies qualify',
    );
    check(await unrelated.exists(), 'Keep unrelated application cache');
    check(
      !await removePickedImportCopy(
        '${cache.path}/file_picker/none.zip',
        cache,
      ),
      'Missing copy is harmless',
    );

    final shared = await write('${cache.path}/file_picker/400/backup.zip');
    final sibling = await write('${shared.parent.path}/other.jpg');
    await consumePickedImport(shared.path, cache, () async => true);
    check(
      await sibling.exists(),
      'Never recursively delete a nonempty picker batch',
    );
    final link = Link('${cache.path}/file_picker/linked.zip');
    await link.create(original.path);
    check(
      !await removePickedImportCopy(link.path, cache),
      'Do not follow source symlinks',
    );
    check(await original.exists(), 'Symlink target survives');

    final alias = Link('${work.path}/cache_alias');
    await alias.create(cache.path);
    final aliasedSource = await write(
      '${cache.path}/file_picker/500/backup.zip',
    );
    check(
      await removePickedImportCopy(
        '${alias.path}/file_picker/500/backup.zip',
        cache,
      ),
      'Resolve sandbox aliases',
    );
    check(!await aliasedSource.exists(), 'Aliased copy released');
    print(
      'PASS: success/failure cleanup, ZIP/JSON inputs, empty directories, original files, installed media, rollback data, unrelated cache and sandbox aliases',
    );
  } finally {
    await work.delete(recursive: true);
  }
}
