// Dart VM regression: no Flutter engine or APK compilation.
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:tide_bot/transfer_media.dart';
import 'package:tide_bot/transfer_archive.dart';
import 'package:tide_bot/json_records.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final root = await Directory(
    '${Directory.current.path}/.dart_tool',
  ).createTemp('complete_media_test_');
  try {
    final docs = await Directory('${root.path}/app_flutter').create();
    final cache = await Directory('${root.path}/cache').create();
    final external = await Directory('${root.path}/external').create();
    final paths = <String, String>{};
    for (final entry in {
      'avatar': '${docs.path}/头像.png',
      'reference': '${docs.path}/reference.png',
      'image': '${docs.path}/chat.png',
      'sticker': '${docs.path}/sticker.gif',
      'audio': '${cache.path}/voice.mp3',
      'video': '${external.path}/video.mp4',
      'frame': '${cache.path}/frame.png',
      'background': '${docs.path}/background.jpg',
    }.entries) {
      await File(entry.value).writeAsBytes(utf8.encode('media:${entry.key}'));
      paths[entry.key] = entry.value;
    }
    final files = <String, String>{};
    final collector = TransferMedia(
      documents: docs,
      temporary: cache,
      files: files,
    );
    final payload = {
      'avatar': paths['avatar'],
      'reference': paths['reference'],
      'background': paths['background'],
      'messages': [
        {'type': 'image', 'file_path': paths['image']},
        {'type': 'sticker', 'file_path': paths['sticker']},
        {'type': 'audio', 'file_path': paths['audio']},
        {'type': 'video', 'file_path': paths['video']},
        {
          'type': 'shared_post',
          'content': jsonEncode({'image_path': paths['image']}),
        },
      ],
      'video_history': [
        jsonEncode({
          'original_video_path': paths['video'],
          'audio_path': paths['audio'],
          'frame_paths': [paths['frame']],
        }),
      ],
      'url': 'https://example.com/image.png',
      'text': '[普通文字，不是 JSON]',
    };
    final mapped = await mapTransferValue(payload, collector.collect) as Map;
    check(
      files.length == paths.length,
      'Every media category must be collected',
    );
    check(
      mapped['url'] == payload['url'] && mapped['text'] == payload['text'],
      'Keep URLs and text',
    );
    const ordinaryJson =
        '{ "example": [ 1, 2 ], "url": "https://example.com" }';
    check(
      await mapTransferValue(ordinaryJson, collector.collect) == ordinaryJson,
      'Keep ordinary JSON message formatting byte-for-byte',
    );
    final uri = Uri.file(paths['image']!).toString();
    check(
      await collector.collect(uri) == collector.references[paths['image']],
      'URI deduplication',
    );
    const old = '/data/user/0/old.package/app_flutter/头像.png';
    check(
      await collector.collect(old) == mapped['avatar'],
      'Old sandbox document recovery',
    );
    const oldCache = '/data/user/0/old.package/cache/voice.mp3';
    check(
      await collector.collect(oldCache) == collector.references[paths['audio']],
      'Old cache recovery',
    );
    final sameName = File('${external.path}/chat.png');
    await sameName.writeAsString('different');
    check(
      await collector.collect(sameName.path) !=
          collector.references[paths['image']],
      'Same basename must not collide',
    );
    final missing = '${docs.path}/missing.png';
    final countBeforeMissing = files.length;
    final missingPayload =
        await mapTransferValue({
              'messages': [
                {'type': 'image', 'file_path': missing, 'content': '保留消息'},
                {'type': 'audio', 'file_path': paths['audio']},
              ],
            }, collector.collect)
            as Map;
    check(
      missingPayload['messages'][0]['file_path'] == missing &&
          missingPayload['messages'][0]['content'] == '保留消息',
      'Missing attachments keep their message and original reference',
    );
    check(
      files.length == countBeforeMissing &&
          !collector.references.containsKey(missing),
      'Missing attachments are excluded from archive and manifest',
    );
    check(
      missingPayload['messages'][1]['file_path'] ==
          collector.references[paths['audio']],
      'Available media still exports after a missing attachment',
    );
    final zip = '${root.path}/media.zip';
    await writeTransferZip(zip, files);
    final restored = Directory('${root.path}/restored');
    await restored.create();
    await extractTransferZip(zip, restored.path);
    for (final entry in files.entries) {
      check(
        base64Encode(await File(entry.value).readAsBytes()) ==
            base64Encode(
              await File('${restored.path}/${entry.key}').readAsBytes(),
            ),
        'Archive byte integrity',
      );
    }
    final imported =
        await mapTransferValue(
              mapped,
              (value) async => value.startsWith('media/')
                  ? '${restored.path}/$value'
                  : value,
            )
            as Map;
    final shared = jsonDecode(imported['messages'][4]['content'] as String);
    check(
      await File(shared['image_path'] as String).exists(),
      'Nested shared-post media restoration',
    );
    final video = jsonDecode(imported['video_history'][0] as String);
    check(
      await File(video['frame_paths'][0] as String).exists(),
      'Nested preference JSON restoration',
    );
    // Full backup reuses documents entries, rather than archiving media twice.
    final fullFiles = <String, String>{
      for (final entry in paths.entries)
        if (p.isWithin(docs.path, entry.value))
          'documents/${p.relative(entry.value, from: docs.path)}': entry.value,
    };
    final full = TransferMedia(
      documents: docs,
      temporary: cache,
      files: fullFiles,
    );
    final before = fullFiles.length;
    check(
      (await full.collect(paths['avatar']!)).startsWith('documents/'),
      'Reuse documents archive entry',
    );
    check(fullFiles.length == before, 'No duplicate documents');
    await full.collect(paths['audio']!);
    check(
      fullFiles.length == before + 1,
      'Referenced cache belongs in full backup',
    );
    final records = File('${root.path}/chat_history.json');
    await records.writeAsString(
      jsonEncode({
        'messages': [],
        'video_history': [],
        'media_settings': {'avatar': mapped['avatar']},
        'call_sessions': [
          {'id': 'call'},
        ],
        'call_messages': [
          {'session_id': 'call'},
        ],
      }),
    );
    var sessions = 0;
    var messages = 0;
    var settings = false;
    await for (final record in JsonRecords.read(records)) {
      if (record.key == 'call_sessions' && record.element) sessions++;
      if (record.key == 'call_messages' && record.element) messages++;
      if (record.key == 'media_settings')
        settings = record.value['avatar'] == mapped['avatar'];
    }
    check(
      sessions == 1 && messages == 1 && settings,
      'Stream call details and media settings',
    );
    final fullArchive = await Directory('${root.path}/full_archive').create();
    for (final entry in fullFiles.entries) {
      final target = File('${fullArchive.path}/${entry.key}');
      await target.parent.create(recursive: true);
      await File(entry.value).copy(target.path);
    }
    final manifestFile = File('${fullArchive.path}/media_manifest.json');
    final manifest = {
      'version': 1,
      'documents_root': docs.path,
      'references': full.references,
    };
    await manifestFile.writeAsString(jsonEncode(manifest));
    final newDocs = Directory('${root.path}/new_app/app_flutter');
    final newMedia = Directory('${newDocs.path}/restored_media/batch');
    final restorer = await BackupMediaRestore.load(
      archive: fullArchive,
      documents: newDocs,
      media: newMedia,
    );
    check(
      await restorer.mapPath(paths['avatar']!) == '${newDocs.path}/头像.png',
      'Full backup avatar relocation across installations',
    );
    check(
      (await restorer.mapPath(paths['audio']!)).startsWith(newMedia.path),
      'Restore cache audio into persistent documents',
    );
    final prefs =
        await mapTransferValue([
              jsonEncode({
                'audio_path': paths['audio'],
                'avatar': paths['avatar'],
              }),
            ], restorer.mapPath)
            as List;
    final prefVideo = jsonDecode(prefs.single as String);
    check(
      prefVideo['audio_path'] == await restorer.mapPath(paths['audio']!),
      'Restore preference JSON through the production mapper',
    );
    await manifestFile.delete();
    final legacyRestorer = await BackupMediaRestore.load(
      archive: fullArchive,
      documents: newDocs,
      media: newMedia,
    );
    check(
      await legacyRestorer.mapPath(old) == '${newDocs.path}/头像.png',
      'Legacy backups without manifests still relocate documents',
    );
    for (final invalid in ['media/missing.mp3', 'media/../../outside.png']) {
      await manifestFile.writeAsString(
        jsonEncode({
          ...manifest,
          'references': {'/data/old/file': invalid},
        }),
      );
      var rejected = false;
      try {
        await BackupMediaRestore.load(
          archive: fullArchive,
          documents: newDocs,
          media: newMedia,
        );
      } on FormatException {
        rejected = true;
      }
      check(
        rejected,
        'Reject incomplete or unsafe full backups before replacement',
      );
    }
    print(
      'PASS: all media categories, nested JSON, legacy roots, deduplication, missing files, byte-exact ZIP and call arrays; full backup relocation and validation',
    );
  } finally {
    await root.delete(recursive: true);
  }
}
