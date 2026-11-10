import 'dart:io';

import 'mimo_voice_clone.dart';

const mimoAudioExtensions = [
  'mp3',
  'wav',
  'm4a',
  'm4b',
  'aac',
  'flac',
  'ogg',
  'oga',
  'opus',
  'amr',
  'wma',
  'aif',
  'aiff',
  'caf',
  'ape',
  'webm',
  'mp4',
  'mov',
  'mkv',
  'avi',
  '3gp',
  'm4v',
  'mpeg',
  'mpg',
  'ts',
];

/// Export only the first audio track, without other media or metadata.
/// WAV keeps the reference lossless after decoding and needs no optional encoder.
List<String> mimoReferenceAudioArguments(String input, String output) => [
      '-nostdin',
      '-y',
      '-i',
      input,
      '-map',
      '0:a:0',
      '-vn',
      '-sn',
      '-dn',
      '-map_metadata',
      '-1',
      '-map_chapters',
      '-1',
      '-ac',
      '1',
      '-ar',
      '24000',
      '-c:a',
      'pcm_s16le',
      '-f',
      'wav',
      output,
    ];

/// The caller owns [directory] and removes it when replacing or discarding a sample.
Future<Map<String, dynamic>> prepareMimoReferenceAudio({
  required String sourcePath,
  required String sourceName,
  required Directory directory,
  required Future<Map<dynamic, dynamic>> Function(String) probe,
  required Future<void> Function(List<String>) convert,
}) async {
  final source = File(sourcePath);
  if (!await source.exists() || await source.length() == 0) {
    throw const FormatException('无法读取音频，请重新选择非空音频文件');
  }
  final original = inspectMimoAudio(await probe(sourcePath),
      requireCompatible: false, allowVideo: true);
  // Bound the converted payload, not the original lossless/high-bitrate file.
  // Leave room for the WAV header and Base64 data URI prefix. Do not truncate.
  final pcmBytes = ((original['duration'] as double) * 24000).ceil() * 2 + 4096;
  try {
    validateMimoSampleSize(pcmBytes);
  } on FormatException {
    throw const FormatException('音频过长，转换后编码会超过 10 MB，请选择较短的录音');
  }
  await directory.create(recursive: true);
  final output = File('${directory.path}/reference.wav');
  try {
    await convert(mimoReferenceAudioArguments(sourcePath, output.path));
    if (!await output.exists()) {
      throw const FormatException('音频转换失败，请更换录音文件');
    }
    final length = await output.length();
    validateMimoSampleSize(length);
    final metadata = inspectMimoAudio(await probe(output.path));
    if (metadata['mime'] != 'audio/wav') {
      throw const FormatException('转换后的音频格式异常，请重新选择');
    }
    final stem = sourceName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return {
      'path': output.path,
      'name': '${stem.isEmpty ? '参考音频' : stem}.wav',
      'source_name': sourceName,
      ...metadata,
      'bytes': length,
    };
  } catch (_) {
    if (await output.exists()) await output.delete();
    rethrow;
  }
}
