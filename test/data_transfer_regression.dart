// Run with the Dart VM; does not build Flutter or an APK.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:tide_bot/json_records.dart';
import 'package:tide_bot/transfer_archive.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final work = await Directory(
    '${Directory.current.path}/.dart_tool',
  ).createTemp('transfer_test_');
  try {
    final json = File('${work.path}/chat.json');
    final sink = json.openWrite();
    sink.write('{"format":"tidebot.chat","version":2,"messages":[');
    for (var i = 0; i < 12000; i++) {
      if (i != 0) sink.write(',');
      sink.write(
        jsonEncode({
          'id': '$i',
          'content': '中文😀 " \\ \n ],:{} $i',
          'nested': [
            null,
            true,
            {'v': i},
          ],
        }),
      );
    }
    sink.write('],"video_history":[],"tail":true}');
    await sink.close();
    var count = 0;
    await for (final record in JsonRecords.read(json)) {
      if (record.key == 'messages' && record.element) {
        check(record.value['id'] == '$count', 'JSON order or chunk boundary');
        check(record.value['nested'][2]['v'] == count, 'nested JSON');
        count++;
      }
    }
    check(count == 12000, 'JSON record count');
    for (final invalid in [
      '{"messages":[{"x":1}',
      '{"messages":[1,]}',
      '{"x":true}junk',
    ]) {
      await json.writeAsString(invalid);
      var failed = false;
      try {
        await JsonRecords.read(json).drain<void>();
      } on FormatException {
        failed = true;
      }
      check(failed, 'Invalid JSON accepted: $invalid');
    }
    print(
      'PASS: chunked JSON, Unicode, escapes, nesting, empty arrays and invalid input',
    );

    final media = File('${work.path}/large.bin');
    final output = media.openWrite();
    final random = Random(17);
    final block = List<int>.generate(64 * 1024, (_) => random.nextInt(256));
    for (var i = 0; i < 4096; i++) {
      output.add(block);
      if (i % 16 == 0) await output.flush();
    }
    await output.close();
    final zip = '${work.path}/backup.zip';
    final before = ProcessInfo.currentRss;
    await writeTransferZip(zip, {'documents/large.bin': media.path});
    final extracted = Directory('${work.path}/out');
    await extracted.create();
    await extractTransferZip(zip, extracted.path);
    final originalHash = await sha256.bind(media.openRead()).first;
    final restoredHash = await sha256
        .bind(File('${extracted.path}/documents/large.bin').openRead())
        .first;
    check(originalHash == restoredHash, 'Archive round trip changed media');
    print(
      'PASS: 256 MiB streaming archive round trip; RSS change ${(ProcessInfo.currentRss - before) ~/ (1024 * 1024)} MiB',
    );

    final legacy = Archive()
      ..addFile(
        ArchiveFile.string(
          'chat_history.json',
          jsonEncode({
            'format': 'tidebot.chat',
            'version': 2,
            'messages': [
              {'content': '旧版压缩备份'},
            ],
          }),
        ),
      );
    final legacyFile = File('${work.path}/legacy.zip');
    await legacyFile.writeAsBytes(ZipEncoder().encode(legacy));
    await extractTransferZip(legacyFile.path, extracted.path);
    final legacyJson = jsonDecode(
      await File('${extracted.path}/chat_history.json').readAsString(),
    );
    check(
      legacyJson['messages'][0]['content'] == '旧版压缩备份',
      'Legacy compressed archive',
    );
    print('PASS: legacy compressed ZIP compatibility');

    final unsafe = Archive()
      ..addFile(ArchiveFile.string('../escape.txt', 'bad'));
    final unsafePath = File('${work.path}/unsafe.zip');
    await unsafePath.writeAsBytes(ZipEncoder().encode(unsafe));
    var rejected = false;
    try {
      await extractTransferZip(unsafePath.path, extracted.path);
    } on FormatException {
      rejected = true;
    }
    check(
      rejected && !await File('${work.path}/escape.txt').exists(),
      'ZIP traversal was not blocked',
    );
    print('PASS: unsafe archive rejected');
  } finally {
    await work.delete(recursive: true);
  }
}
