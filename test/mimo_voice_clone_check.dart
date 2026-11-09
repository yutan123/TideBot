import 'dart:convert';
import 'dart:io';
import 'package:tide_bot/mimo_voice_clone.dart';
import 'package:tide_bot/call_speech.dart';

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
    check(mimoSynthesisModel('other', mimoCloneVoice, clone) == mimoCloneModel,
        'Clone mode uses the workbench model');
    check(
        mimoSynthesisModel(mimoCloneModel, '冰糖', clone) == mimoDefaultTtsModel,
        'Changing voice also leaves the clone-only model');
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
    check(
        mimoSynthesisModel(mimoCloneModel, '茉莉', clone) == mimoDefaultTtsModel,
        'Ordinary voices do not depend on the missing sample');
    stdout.writeln(
        'Passed: MiMo clone routing, sample encoding, limits, style and missing-file handling.');
  } finally {
    await folder.delete(recursive: true);
  }
}
