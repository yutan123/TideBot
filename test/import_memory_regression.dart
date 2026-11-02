// Dart VM regression; no Flutter/Android build.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart' hide ZLibEncoder;
import 'package:tide_bot/json_records.dart';
import 'package:tide_bot/transfer_archive.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    final baseline = ProcessInfo.maxRss;
    await extractTransferZip(args[0], args[1]);
    final file = File('${args[1]}/large.bin');
    check(await file.length() == 256 * 1024 * 1024, 'Expanded size');
    await for (final chunk in file.openRead()) {
      check(chunk.every((byte) => byte == 65), 'Expanded content');
    }
    final growth = ProcessInfo.maxRss - baseline;
    check(growth < 96 * 1024 * 1024, 'Import peak grew by $growth bytes');
    print(
      'PASS: 256 MiB deflated import; max RSS growth ${growth ~/ (1024 * 1024)} MiB',
    );
    return;
  }
  final work = await Directory(
    '${Directory.current.path}/.dart_tool',
  ).createTemp('import_memory_test_');
  try {
    final payload = File('${work.path}/deflated');
    final block = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 65);
    var crc = 0;
    final sink = payload.openWrite();
    try {
      await sink.addStream(
        Stream<List<int>>.fromIterable(
          Iterable.generate(4096, (_) {
            crc = getCrc32(block, crc);
            return block;
          }),
        ).transform(ZLibEncoder(raw: true)),
      );
    } finally {
      await sink.close();
    }
    final compressed = await payload.length();
    final name = utf8.encode('large.bin');
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(8, 8, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, compressed, Endian.little)
      ..setUint32(22, 256 * 1024 * 1024, Endian.little)
      ..setUint16(26, name.length, Endian.little);
    final central = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(10, 8, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, compressed, Endian.little)
      ..setUint32(24, 256 * 1024 * 1024, Endian.little)
      ..setUint16(28, name.length, Endian.little);
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, 1, Endian.little)
      ..setUint16(10, 1, Endian.little)
      ..setUint32(12, 46 + name.length, Endian.little)
      ..setUint32(16, 30 + name.length + compressed, Endian.little);
    final zip = File('${work.path}/compressed.zip');
    final zipSink = zip.openWrite();
    try {
      zipSink.add(local.buffer.asUint8List());
      zipSink.add(name);
      await zipSink.addStream(payload.openRead());
      zipSink.add(central.buffer.asUint8List());
      zipSink.add(name);
      zipSink.add(end.buffer.asUint8List());
    } finally {
      await zipSink.close();
    }
    check(transferZipSize(zip.path) == 256 * 1024 * 1024, 'Size preflight');
    final result = await Process.run(Platform.resolvedExecutable, [
      '--old_gen_heap_size=96',
      '--packages=${Directory.current.path}/.dart_tool/package_config.json',
      Platform.script.toFilePath(),
      zip.path,
      '${work.path}/out',
    ]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    check(result.exitCode == 0, 'Compressed import worker failed');

    // CRC mismatch must abort rather than silently install corrupt data.
    check(await zip.length() < 1024 * 1024, 'Expected tiny compressed fixture');
    final corrupted = await zip.readAsBytes();
    corrupted.fillRange(14, 18, 0);
    final centralOffset = 30 + name.length + compressed;
    corrupted.fillRange(centralOffset + 16, centralOffset + 20, 0);
    await zip.writeAsBytes(corrupted);
    var rejected = false;
    try {
      await extractTransferZip(zip.path, '${work.path}/corrupt');
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Corrupt CRC accepted');
    print('PASS: corrupt import rejected');

    // One large value crosses many UTF-8 and escape boundaries.
    final json = File('${work.path}/records.json');
    final text = List.filled(100000, '中文😀\\"\n').join();
    await json.writeAsString(
      jsonEncode({
        'messages': [
          {'content': text},
          {'content': 'tail'},
        ],
      }),
    );
    var count = 0;
    await for (final record in JsonRecords.read(json)) {
      if (!record.element) continue;
      check(
        record.value['content'] == (count == 0 ? text : 'tail'),
        'Large JSON record changed',
      );
      count++;
    }
    check(count == 2, 'Large JSON records missing');
    print('PASS: large JSON record across chunk and Unicode boundaries');
  } finally {
    await work.delete(recursive: true);
  }
}
