import 'dart:convert';
import 'dart:io';

const mimoCloneVoice = '克隆音色';
const mimoAudioLimit = 10 * 1000 * 1000;

bool isMimoClone(String protocol, String voice) =>
    protocol == 'mimo' && voice.trim() == mimoCloneVoice;

void validateMimoSampleSize(int bytes) {
  if (bytes <= 0 || bytes > mimoAudioLimit) {
    throw const FormatException('请选择 10 MB 以内的非空音频');
  }
  if (((bytes + 2) ~/ 3) * 4 + 32 > mimoAudioLimit) {
    throw const FormatException('音频编码后超过 MiMo 的 10 MB 限制，请压缩音频后重试');
  }
}

/// Reference uploads are MP3/WAV; local imports may use any decodable audio.
Map<String, dynamic> inspectMimoAudio(Map<dynamic, dynamic> info,
    {bool requireCompatible = true}) {
  final format = info['format'] is Map ? info['format'] as Map : const {};
  final formats = (format['format_name']?.toString() ?? '')
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .toSet();
  final streams = info['streams'] is List ? info['streams'] as List : const [];
  final audio =
      streams.whereType<Map>().where((s) => s['codec_type'] == 'audio');
  final hasVideo = streams.whereType<Map>().any((stream) {
    if (stream['codec_type'] != 'video') return false;
    final disposition = stream['disposition'];
    return disposition is! Map || '${disposition['attached_pic']}' != '1';
  });
  if (audio.isEmpty || hasVideo) {
    throw const FormatException('请选择包含有效音轨的音频文件，不支持视频');
  }
  if (requireCompatible &&
      !(formats.contains('mp3') || formats.contains('wav'))) {
    throw const FormatException('参考音频须为 MP3 / WAV，请在工作台重新导入');
  }
  final duration = double.tryParse('${format['duration']}') ??
      double.tryParse('${audio.first['duration']}') ??
      0;
  if (!duration.isFinite || duration <= 0) {
    throw const FormatException('无法读取有效音频时长，请重新选择');
  }
  return {
    if (formats.contains('mp3')) 'mime': 'audio/mpeg',
    if (formats.contains('wav')) 'mime': 'audio/wav',
    'duration': duration,
  };
}

/// The provider model remains editable, including for future clone models.
String mimoSynthesisModel(
    String configured, String voice, Map<String, dynamic>? clone) {
  if (voice.trim() == mimoCloneVoice) {
    if (clone == null) {
      throw const FormatException('请先在 MiMo 音色克隆工作台配置参考音频');
    }
    if (configured.trim().isEmpty) {
      throw const FormatException('请填写支持音色克隆的模型名');
    }
  }
  return configured.trim();
}

Future<String> mimoReferenceVoice(Map<String, dynamic>? clone) async {
  final path = clone?['path']?.toString() ?? '';
  final mime = clone?['mime']?.toString() ?? '';
  if (path.isEmpty || !const ['audio/mpeg', 'audio/wav'].contains(mime)) {
    throw const FormatException('克隆音色未配置，请重新应用工作台设置');
  }
  final file = File(path);
  if (!await file.exists()) {
    throw const FormatException('克隆参考音频不存在，请在工作台重新选择');
  }
  validateMimoSampleSize(await file.length());
  final bytes = await file.readAsBytes();
  validateMimoSampleSize(bytes.length);
  return 'data:$mime;base64,${base64Encode(bytes)}';
}
