import 'dart:convert';
import 'dart:io';
import 'package:tide_bot/mimo_voice_clone.dart';
import 'package:tide_bot/call_speech.dart';

const mimoCloneModel = "test-clone-model";

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> rejects(Future<void> Function() action, String message) async {
  try {
    await action();
  } catch (_) {
    return;
  }
  throw StateError(message);
}

Future<void> main() async {
  check(isMimoClone('mimo', '克隆音色'), 'The exact marker enables cloning');
  check(!isMimoClone('openai', '克隆音色'), 'Other providers remain unchanged');
  check(!isMimoClone('mimo', '克隆音色2'), 'Ordinary voice names are not markers');
  Map<String, dynamic> media(String format, List<Map<String, dynamic>> streams,
          {String duration = '12'}) =>
      {
        'format': {'format_name': format, 'duration': duration},
        'streams': streams,
      };
  const audio = {'codec_type': 'audio'};
  const cover = {
    'codec_type': 'video',
    'disposition': {'attached_pic': 1}
  };
  check(inspectMimoAudio(media('mp3', [audio, cover]))['mime'] == 'audio/mpeg',
      'MP3 album artwork must not be rejected as video');
  check(inspectMimoAudio(media('wav', [audio]))['duration'] == 12,
      'WAV metadata is accepted');
  for (final duration in ['1', '4.9', '5', '30', '30.1']) {
    inspectMimoAudio(media('mp3', [audio], duration: duration));
  }
  for (final invalid in [
    media('mp3', [
      audio,
      {'codec_type': 'video'}
    ]),
    media('mp3', [cover]),
    media('mov,mp4,m4a,3gp,3g2,mj2', [audio]),
    media('wav', [audio], duration: '0'),
    media('wav', [audio], duration: '-1'),
    media('wav', [audio], duration: 'NaN'),
    <String, dynamic>{},
  ]) {
    await rejects(() async {
      inspectMimoAudio(invalid);
    }, 'Invalid formats, videos and durations must be rejected');
  }
  await rejects(() async {
    mimoSynthesisModel(' ', mimoCloneVoice, {'model': 'future-model'});
  }, 'Clone model cannot be blank');
  final folder = await Directory.systemTemp.createTemp('mimo_clone_check_');
  try {
    final file = File('${folder.path}/sample.wav');
    final bytes = [82, 73, 70, 70, 1, 2, 3, 4];
    await file.writeAsBytes(bytes);
    final clone = <String, dynamic>{
      'model': mimoCloneModel,
      'path': file.path,
      'mime': 'audio/wav',
    };
    check(
        mimoSynthesisModel('future-clone-model', mimoCloneVoice, clone) ==
            'future-clone-model',
        'New clone models are used without a hardcoded allowlist');
    check(mimoSynthesisModel('custom-tts', '冰糖', clone) == 'custom-tts',
        'Changing voice preserves the selected model');
    check(mimoSynthesisModel('custom-tts', '冰糖', clone) == 'custom-tts',
        'Ordinary model choices survive');
    final reference = await mimoReferenceVoice(clone);
    check(reference == 'data:audio/wav;base64,${base64Encode(bytes)}',
        'The request includes reference bytes with the required MIME prefix');
    final base = <String, dynamic>{
      'model': mimoCloneModel,
      'messages': [
        {'role': 'assistant', 'content': '你好'}
      ],
      'audio': {'voice': reference, 'format': 'wav'},
    };
    final expressive = applyCallSpeechStyle(base,
        protocol: 'mimo',
        model: mimoCloneModel,
        baseUrl: 'https://api.xiaomimimo.com/v1',
        style: const CallSpeechStyle(direction: '温柔地说'));
    check((expressive['audio'] as Map)['voice'] == reference,
        'Call style preserves cloning on the expressive request');
    check((base['audio'] as Map)['voice'] == reference,
        'Basic retry preserves the reference sample');
    await rejects(() async {
      validateMimoSampleSize(0);
    }, 'Empty input rejected');
    await rejects(() async {
      validateMimoSampleSize(8000000);
    }, 'Base64 oversize rejected');
    await rejects(() async {
      validateMimoSampleSize(10000001);
    }, 'Raw oversize rejected');
    validateMimoSampleSize(7000000);
    await rejects(() async {
      mimoSynthesisModel('', mimoCloneVoice, null);
    }, 'Unconfigured cloning must not silently become a default voice');
    await file.delete();
    await rejects(() async {
      await mimoReferenceVoice(clone);
    }, 'Missing sample rejected');
    check(mimoSynthesisModel('custom-tts', '茉莉', clone) == 'custom-tts',
        'Ordinary voices do not depend on the missing sample');
    stdout.writeln(
        'Passed: MiMo clone routing, sample encoding, limits, style and missing-file handling.');
  } finally {
    await folder.delete(recursive: true);
  }
}
