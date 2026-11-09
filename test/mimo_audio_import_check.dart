import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tide_bot/mimo_audio_import.dart';
import 'package:tide_bot/mimo_voice_clone.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> rejects(Future<void> Function() action, String message) async {
  try {
    await action();
  } on FormatException {
    return;
  }
  throw StateError(message);
}

Map<String, dynamic> media(String format,
        {double duration = 12, bool video = false}) =>
    {
      'format': {'format_name': format, 'duration': '$duration'},
      'streams': [
        {'codec_type': 'audio', 'codec_name': 'pcm_s16le'},
        if (video) {'codec_type': 'video'},
      ],
    };

Uint8List wavBytes() {
  final bytes = Uint8List(44 + 24000 * 2);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, ascii.encode('RIFF'));
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setAll(8, ascii.encode('WAVEfmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 24000, Endian.little);
  data.setUint32(28, 48000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setAll(36, ascii.encode('data'));
  data.setUint32(40, bytes.length - 44, Endian.little);
  return bytes;
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('mimo_import_check_');
  try {
    // The native probe/transcode adapters are injected; no Flutter build is needed.
    final source = File('${root.path}/录音 \'原始\' #1.flac');
    await source.writeAsBytes([1, 2, 3]);
    final handle = await source.open(mode: FileMode.append);
    await handle.truncate(12000000);
    await handle.close();
    final wav = wavBytes();
    var converted = 0;
    Future<void> convert(List<String> arguments) async {
      check(arguments[arguments.indexOf('-i') + 1] == source.path,
          'Paths containing spaces and quotes must remain one argument');
      check(!arguments.contains('-t'),
          'Import must never silently truncate audio');
      converted++;
      await File(arguments.last).writeAsBytes(wav);
    }

    final folder = Directory('${root.path}/prepared');
    for (final format in [
      'flac',
      'mov,mp4,m4a,3gp,3g2,mj2',
      'aac',
      'ogg',
      'opus',
      'amr',
      'asf',
      'aiff',
      'caf',
      'ape',
      'matroska,webm',
      'mp3',
      'wav'
    ]) {
      final sample = await prepareMimoReferenceAudio(
        sourcePath: source.path,
        sourceName: "录音 '原始' #1.flac",
        directory: folder,
        probe: (path) async =>
            media(path == source.path ? format : 'wav', duration: 1),
        convert: convert,
      );
      check(sample['mime'] == 'audio/wav', 'Only the converted MIME is saved');
      check(
          sample['name'] == "录音 '原始' #1.wav", 'Saved display name matches WAV');
      check(sample['bytes'] == wav.length,
          'Payload limits apply after conversion');
      check((await source.length()) == 12000000, 'Original file is preserved');
      final voice = await mimoReferenceVoice(sample);
      check(voice == 'data:audio/wav;base64,${base64Encode(wav)}',
          'Synthesis uses the converted bytes, never the original FLAC');
    }
    check(converted == 13, 'Every supported import passes through conversion');

    final before = converted;
    for (final metadata in [
      media('flac', video: true),
      media('flac', duration: 200),
      media('flac', duration: 0),
      <String, dynamic>{}
    ]) {
      await rejects(() async {
        await prepareMimoReferenceAudio(
          sourcePath: source.path,
          sourceName: 'recording.flac',
          directory: Directory('${root.path}/rejected'),
          probe: (_) async => metadata,
          convert: convert,
        );
      }, 'Reject video, invalid audio and oversized output before conversion');
    }
    check(converted == before, 'Rejected sources must not invoke FFmpeg');

    final failed = Directory('${root.path}/failed');
    await rejects(() async {
      await prepareMimoReferenceAudio(
        sourcePath: source.path,
        sourceName: 'recording.flac',
        directory: failed,
        probe: (_) async => media('flac'),
        convert: (arguments) async {
          await File(arguments.last).writeAsBytes([1]);
          throw const FormatException('Decoder failed');
        },
      );
    }, 'Conversion failure must propagate');
    check(!await File('${failed.path}/reference.wav').exists(),
        'Partial conversion output must be removed');

    for (final invalidOutput in ['empty', 'oversized', 'wrong-format']) {
      await rejects(() async {
        await prepareMimoReferenceAudio(
          sourcePath: source.path,
          sourceName: 'recording.flac',
          directory: failed,
          probe: (path) async => media(path == source.path ? 'flac' : 'ogg'),
          convert: (arguments) async {
            final output =
                await File(arguments.last).open(mode: FileMode.write);
            await output.truncate(invalidOutput == 'empty'
                ? 0
                : invalidOutput == 'oversized'
                    ? 8000000
                    : 100);
            await output.close();
          },
        );
      }, 'Invalid converted audio must not be saved');
      check(!await File('${failed.path}/reference.wav').exists(),
          'Invalid output must be removed');
    }
    stdout.writeln(
        'Passed: multi-format import workflow, large sources, WAV payloads, '
        'unmodified originals, rejection before conversion and failed-output cleanup.');
  } finally {
    await root.delete(recursive: true);
  }
}
