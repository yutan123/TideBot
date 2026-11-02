import 'package:tide_bot/call_speech.dart';
import 'package:tide_bot/voice_message_speech.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final data = <String, dynamic>{
    'emotion': 'happy',
    'intensity': 0.8,
    'pace': 'slightly_fast',
    'delivery': 'natural',
    'direction': '“太好了”轻快上扬，停顿后自然放缓，保持原有音色。',
  };
  final style = parseVoiceMessageSpeech(data)!;
  check(style.emotion == 'happy' && style.intensity == 0.8, 'Model emotion');
  check(style.speed > 1, 'Per-message pace');
  check(parseVoiceMessageSpeech(null) == null, 'No metadata for text');
  for (final invalid in [
    <String, dynamic>{},
    {...data, 'emotion': 'unknown'},
    {...data, 'intensity': double.nan},
    {...data, 'intensity': 2},
    {...data, 'direction': ''},
    {...data, 'pace': 'invalid'},
  ]) {
    check(parseVoiceMessageSpeech(invalid) == null, 'Reject malformed style');
  }
  final minimax = applyCallSpeechStyle(
    {
      'text': '太好了！',
      'voice_setting': {'voice_id': 'fixed'},
    },
    protocol: 'minimax',
    model: 'speech-02-turbo',
    baseUrl: '',
    style: style,
  );
  check(minimax['text'] == '太好了！', 'Metadata excluded from speech text');
  check(minimax['voice_setting']['emotion'] == 'happy', 'MiniMax emotion');
  check(minimax['voice_setting']['voice_id'] == 'fixed', 'Preserve voice');
  final mimo = applyCallSpeechStyle(
    {
      'messages': [
        {'role': 'assistant', 'content': '太好了！'},
      ],
      'audio': {'voice': 'fixed'},
    },
    protocol: 'mimo',
    model: 'mimo-v2.5-tts',
    baseUrl: '',
    style: style,
  );
  check(mimo['messages'].last['content'] == '太好了！', 'MiMo body unchanged');
  check(
    mimo['messages'].first['content'].contains(data['direction']),
    'MiMo direction',
  );
  final required = voiceMessageSpeechSchema()['required'] as List;
  check(
    required.contains('emotion') && required.contains('direction'),
    'Required model metadata',
  );
  print(
    'PASS: voice-message emotion, validation, MiniMax/MiMo propagation, '
    'voice preservation and metadata separation',
  );
}
