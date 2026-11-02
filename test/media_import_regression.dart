// Dart VM regression; no Flutter or Android compilation.
import 'dart:convert';
import 'dart:io';
import 'package:tide_bot/transfer_media.dart';
import 'package:tide_bot/transfer_archive.dart';
import 'package:tide_bot/json_records.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

Future<void> main() async {
  final work = await Directory(
    '${Directory.current.path}/.dart_tool',
  ).createTemp('media_import_');
  try {
    final docs = await Directory(
      '${work.path}/old/app_flutter',
    ).create(recursive: true);
    final cache = await Directory(
      '${work.path}/old/cache',
    ).create(recursive: true);
    final paths = <String, String>{};
    for (final type in ['image', 'video', 'audio', 'sticker']) {
      final file = File(
        '${type == 'audio' ? cache.path : docs.path}/$type.bin',
      );
      await file.writeAsBytes(utf8.encode('$type bytes'));
      paths[type] = file.path;
    }
    final files = <String, String>{};
    final exporter = TransferMedia(docs, cache, files);
    final payload = {
      'format': 'tidebot.chat',
      'version': 2,
      'messages': [
        for (final type in paths.keys)
          {'type': type, 'file_path': paths[type], 'content': 'unchanged text'},
        {
          'type': 'shared_post',
          'content': jsonEncode({
            'images': [paths['image']],
            'audio': paths['audio'],
          }),
          'sources_json': jsonEncode([
            {'cover': paths['image']},
          ]),
        },
        {
          'type': 'image',
          'file_path': '${docs.path}/missing.png',
          'content': 'keep message',
        },
      ],
      'video_history': [
        {
          'original_video_path': paths['video'],
          'audio_path': paths['audio'],
          'frame_paths': [paths['image']],
        },
      ],
    };
    final exported = await mapTransferValue(payload, exporter.mapPath) as Map;
    check(files.length == 4, 'Collect and deduplicate all media types');
    check(
      exporter.missingReferences == 1,
      'Only missing local references count',
    );
    final json = File('${work.path}/chat_history.json');
    await json.writeAsString(jsonEncode(exported));
    files['chat_history.json'] = json.path;
    final zip = '${work.path}/chat.zip';
    await writeTransferZip(zip, files);
    final extracted = Directory('${work.path}/extract');
    await extractTransferZip(zip, extracted.path);
    // As in importBotChat, install files before rewriting their references.
    final installed = await Directory(
      '${extracted.path}/media',
    ).rename('${work.path}/installed_media');
    final mapper = ImportedMedia(installed, allowLegacyBasename: true);
    final records = <String, List<dynamic>>{};
    await for (final record in JsonRecords.read(
      File('${extracted.path}/chat_history.json'),
    )) {
      if (record.element) {
        records
            .putIfAbsent(record.key, () => [])
            .add(await mapTransferValue(record.value, mapper.mapPath));
      }
    }
    final messages = records['messages']!;
    for (var i = 0; i < paths.length; i++) {
      final item = messages[i] as Map;
      final file = File(item['file_path'] as String);
      check(
        file.path.startsWith(installed.path),
        'Installed path for ${item['type']}',
      );
      check(
        await file.readAsString() == '${item['type']} bytes',
        'Exact media bytes after import',
      );
    }
    final shared = jsonDecode(messages[4]['content'] as String) as Map;
    check(
      await File(shared['images'][0] as String).exists(),
      'Nested shared image mapped',
    );
    check(
      await File(shared['audio'] as String).exists(),
      'Nested shared audio mapped',
    );
    final sources = jsonDecode(messages[4]['sources_json'] as String) as List;
    check(
      await File(sources.first['cover'] as String).exists(),
      'Nested source cover mapped',
    );
    check(
      messages.last['content'] == 'keep message',
      'Missing media preserves record',
    );
    final video = records['video_history']!.single as Map;
    check(
      await File(video['original_video_path'] as String).exists(),
      'Video history video mapped',
    );
    check(
      await File(video['audio_path'] as String).exists(),
      'Video history audio mapped',
    );
    check(
      await File(video['frame_paths'][0] as String).exists(),
      'Video frames mapped',
    );
    for (final folder in ['a', 'b']) {
      final file = File('${installed.path}/$folder/same.jpg');
      await file.parent.create(recursive: true);
      await file.writeAsString(folder);
      final mapped = await mapper.mapPath('media/$folder/same.jpg');
      check(
        await File(mapped).readAsString() == folder,
        'Retain nested paths without basename collisions',
      );
    }
    final name = exported['messages'][0]['file_path'] as String;
    check(
      await mapper.mapPath('media/$name') == await mapper.mapPath(name),
      'Archive prefix compatibility',
    );
    check(
      await mapper.mapPath(Uri.file('/old/media/$name').toString()) ==
          await mapper.mapPath(name),
      'File URI import',
    );
    check(
      await mapper.mapPath('/old/app_flutter/$name') ==
          await mapper.mapPath(name),
      'Legacy flat absolute reference',
    );
    for (final path in [
      '../outside.jpg',
      'media/../outside.jpg',
      'https://example.com/$name',
      'missing.jpg',
    ]) {
      check(
        await mapper.mapPath(path) == path,
        'Preserve missing, remote and unsafe reference: $path',
      );
    }
    const ordinary = '{ "example": [ 1, 2 ] }';
    check(
      await mapTransferValue(ordinary, mapper.mapPath) == ordinary,
      'Preserve ordinary JSON formatting',
    );

    final restoredDocs = Directory('${work.path}/new/app_flutter');
    final restore = RestoredDocuments(docs, restoredDocs);
    final settings =
        await mapTransferValue({
              'avatar': '/data/user/0/old.package/app_flutter/image.bin',
              'video_history': [
                jsonEncode({
                  'original_video_path':
                      '/data/user/0/old.package/app_flutter/video.bin',
                }),
              ],
              'missing': '/data/user/0/old.package/app_flutter/missing.png',
            }, restore.mapPath)
            as Map;
    check(
      settings['avatar'] == '${restoredDocs.path}/image.bin',
      'Full backup avatar relocates to final documents',
    );
    final history = jsonDecode(settings['video_history'][0] as String) as Map;
    check(
      history['original_video_path'] == '${restoredDocs.path}/video.bin',
      'Full backup JSON preferences relocate',
    );
    check(
      settings['missing'] == '/data/user/0/old.package/app_flutter/missing.png',
      'Full backup missing files remain nonfatal',
    );
    check(
      await restore.mapPath('documents/video.bin') ==
          '${restoredDocs.path}/video.bin',
      'Relative document archive reference',
    );
    print(
      'PASS: image/video/audio/sticker export and import, nested JSON, video history, same filenames, legacy paths, full restore path relocation and missing attachments',
    );
  } finally {
    await work.delete(recursive: true);
  }
}
