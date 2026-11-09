import 'dart:convert';
import 'dart:io';

const mimoCloneVoice = '克隆音色';
const mimoCloneModel = 'mimo-v2.5-tts-voiceclone';
const mimoDefaultTtsModel = 'mimo-v2.5-tts';
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

/// Only the exact display marker opts into reference-audio synthesis.
String mimoSynthesisModel(
    String configured, String voice, Map<String, dynamic>? clone) {
  if (voice.trim() == mimoCloneVoice) {
    if (clone == null || clone['model'] != mimoCloneModel) {
      throw const FormatException('请先在 MiMo 音色克隆工作台配置参考音频');
    }
    return mimoCloneModel;
  }
  return configured == mimoCloneModel ? mimoDefaultTtsModel : configured;
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
