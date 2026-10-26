// Standalone regression checks: dart --packages=.dart_tool/package_config.json test/minimax_tts_check.dart
import 'package:tide_bot/minimax_tts.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  for (final root in [
    'https://api.minimax.cn',
    'https://api.minimax.cn/v1',
    'https://api.minimax.cn/v1/',
    'https://api.minimax.cn/v1/t2a_v2',
  ]) {
    check(miniMaxTtsEndpoint(root) == 'https://api.minimax.cn/v1/t2a_v2',
        'Incorrect endpoint for $root');
  }
  check(
      miniMaxTtsEndpoint('https://api.minimax.chat/v1?GroupId=123') ==
          'https://api.minimax.chat/v1/t2a_v2?GroupId=123',
      'Legacy host and query must be preserved');
  final audio = decodeMiniMaxTtsAudio({
    'data': {'audio': 'fffB906400', 'status': 2},
    'base_resp': {'status_code': 0, 'status_msg': 'success'},
  });
  check(audio.join(',') == '255,251,144,100,0', 'Hex audio bytes corrupted');
  for (final data in [
    null,
    {'audio': ''},
    {'audio': 'fff'},
    {'audio': 'not hex'}
  ]) {
    try {
      decodeMiniMaxTtsAudio({
        'data': data,
        'base_resp': {'status_code': 0}
      });
      throw StateError('Invalid audio accepted: $data');
    } on FormatException {
      // Expected: never save error JSON as an audio file.
    }
  }
  try {
    decodeMiniMaxTtsAudio({
      'data': null,
      'base_resp': {'status_code': 1004, 'status_msg': '鉴权失败'},
      'trace_id': 'test-trace',
    });
    throw StateError('Business error accepted as successful audio');
  } on FormatException catch (error) {
    check(
        error.message.contains('1004') &&
            error.message.contains('鉴权失败') &&
            error.message.contains('test-trace'),
        'Missing API error details');
  }
  print('MiniMax TTS regression checks passed.');
}
