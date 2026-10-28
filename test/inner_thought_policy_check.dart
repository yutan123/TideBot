import 'dart:io';

import 'package:tide_bot/ai_request_task.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  for (final task in AIRequestTask.values) {
    for (final setting in [false, true]) {
      for (final call in [false, true]) {
        final enabled = shouldIncludeInnerThought(
          task: task,
          settingEnabled: setting,
          isVoiceCall: call,
        );
        final expected = setting &&
            !call &&
            (task == AIRequestTask.chat || task == AIRequestTask.proactiveChat);
        check(enabled == expected, 'Unexpected policy: $task/$setting/$call');
      }
    }
  }
  // A voice request must not change policy for the next ordinary chat request.
  check(
      !shouldIncludeInnerThought(
          task: AIRequestTask.chat, settingEnabled: true, isVoiceCall: true),
      'Voice call enabled thoughts');
  check(
      shouldIncludeInnerThought(task: AIRequestTask.chat, settingEnabled: true),
      'Normal chat did not resume thoughts');

  // Guard the original cross-layer regression: extra context must not be used
  // as the request-mode flag, and retries must keep the explicit call flag.
  final root = File.fromUri(Platform.script).parent.parent;
  final ai = File('${root.path}/lib/ai.dart').readAsStringSync();
  final call = File('${root.path}/lib/ui_call.dart').readAsStringSync();
  check(ai.contains('isVoiceCall: isVoiceCall,'), 'Retries lost call mode');
  final gateStart = ai.indexOf('final innerThoughtEnabled =');
  final gateEnd = ai.indexOf('String recentThoughtsContext', gateStart);
  final gate = ai.substring(gateStart, gateEnd);
  check(
      gate.contains('shouldIncludeInnerThought(') &&
          !gate.contains('extraSystemPrompt'),
      'Extra prompt still controls thoughts');
  check(
      ai.contains(
          "extraSystemPrompt = '\$vitalContext\\n\$extraSystemPrompt';"),
      'Life-state context was removed');
  check(call.contains('isVoiceCall: true,'), 'Call entry lost voice mode');
  check(!call.contains('不要输出内心独白'), 'Call still mentions thoughts');
  check(RegExp(r'!isVoiceCall\s*&&\s*useJarvis').hasMatch(ai),
      'Voice mode can inject advisor thought seeds');
  check(
      'final innerThoughtEnabled = shouldIncludeInnerThought('
              .allMatches(ai)
              .length ==
          2,
      'Persistence overrides request policy');
  print('Inner-thought checks passed: all task/setting/call combinations, '
      'chat after call, retry wiring, life context, voice prompt isolation.');
}
