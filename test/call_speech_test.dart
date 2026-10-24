import 'package:flutter_test/flutter_test.dart';
import '../lib/call_speech.dart';
import '../lib/assistant_output_guard.dart';

void main() {
  test('call JSON survives chat guard and metadata stays out of spoken text',
      () {
    const raw =
        '{"text":"慢慢说，我听着呢。","speech":{"emotion":"comforting","intensity":0.6,"pace":"slightly_slow","delivery":"gentle"}}';
    final reply = CallSpeechReply.parse(stripInternalToolPayloads(raw));
    expect(reply.text, '慢慢说，我听着呢。');
    expect(reply.style.emotion, 'comforting');
    expect(reply.style.speed, lessThan(1));
  });
  test('fenced JSON, escaped quotation and plain custom-model replies', () {
    final reply = CallSpeechReply.parse(
        '```json\n{"text":"他说\\"你好\\"。","speech":{}}\n```');
    expect(reply.text, '他说"你好"。');
    expect(CallSpeechReply.parse('我在这里。').text, '我在这里。');
  });
  test('invalid metadata defaults safely, malformed envelopes are never spoken',
      () {
    final reply = CallSpeechReply.parse(
        '{"text":"你好","speech":{"emotion":"unknown","intensity":99,"pace":"race","delivery":"shout"}}');
    expect(reply.style.emotion, 'neutral');
    expect(reply.style.intensity, 1);
    expect(reply.style.pace, 'normal');
    expect(reply.style.delivery, 'natural');
    expect(CallSpeechReply.parse('{"text":"你好","speech":broken').text, '你好');
    expect(CallSpeechReply.parse('{"speech":{"emotion":"sad"}}').text, isEmpty);
    expect(CallSpeechReply.parse('{"text":"unfinished').text, isEmpty);
    expect(CallSpeechReply.parse('[{"emotion":"sad"}]').text, isEmpty);
    expect(CallSpeechStyle.fromJson({'intensity': double.nan}).intensity, .4);
  });
  test('strength and per-turn smoothing keep intensity bounded', () {
    const style = CallSpeechStyle(intensity: 1, pace: 'slightly_fast');
    final value = style.moderated(
        previous: const CallSpeechStyle(intensity: .1), strength: 'expressive');
    expect(value.intensity, closeTo(.35, .001));
    expect(style.moderated(strength: 'restrained').intensity, .6);
    expect(style.moderated(strength: 'expressive').intensity, .85);
  });
  const style =
      CallSpeechStyle(emotion: 'happy', intensity: .6, pace: 'slightly_fast');
  test(
      'MiniMax uses documented emotion and preserves voice without mutating fallback',
      () {
    final base = <String, dynamic>{
      'text': '你好',
      'voice_setting': {'voice_id': 'same-voice', 'speed': 1.0, 'pitch': 0}
    };
    final result = applyCallSpeechStyle(base,
        protocol: 'minimax',
        model: 'speech-02-turbo',
        baseUrl: '',
        style: style);
    expect(result['voice_setting']['emotion'], 'happy');
    expect(result['voice_setting']['voice_id'], 'same-voice');
    expect(result['voice_setting']['pitch'], 0);
    expect(base['voice_setting'].containsKey('emotion'), isFalse);
    expect(result.containsKey('intensity'), isFalse);
    final calm = applyCallSpeechStyle(base,
        protocol: 'minimax',
        model: 'speech-2.6-hd',
        baseUrl: '',
        style: const CallSpeechStyle(emotion: 'comforting'));
    expect(calm['voice_setting']['emotion'], 'calm');
  });
  test('MiMo isolates directions in user message and preserves assistant text',
      () {
    final base = <String, dynamic>{
      'messages': [
        {'role': 'assistant', 'content': '你好'}
      ],
      'audio': {'voice': '冰糖'}
    };
    final result = applyCallSpeechStyle(base,
        protocol: 'mimo', model: 'mimo-v2.5-tts', baseUrl: '', style: style);
    expect(result['messages'].length, 2);
    expect(result['messages'][0]['role'], 'user');
    expect(result['messages'][1]['content'], '你好');
    expect(result['audio']['voice'], '冰糖');
    expect(base['messages'].length, 1);
  });
  test(
      'CosyVoice directions are restricted to known SiliconFlow host and model',
      () {
    final base = <String, dynamic>{'input': '你好', 'voice': 'fixed'};
    Map<String, dynamic> build(String url, String model) =>
        applyCallSpeechStyle(base,
            protocol: 'openai', model: model, baseUrl: url, style: style);
    expect(
        build('https://api.siliconflow.cn/v1', 'FunAudioLLM/CosyVoice2-0.5B')[
            'input'],
        endsWith('<|endofprompt|>你好'));
    expect(build('https://api.siliconflow.cn/v1', 'unknown')['input'], '你好');
    expect(
        build('https://custom.example/v1', 'FunAudioLLM/CosyVoice2-0.5B')[
            'input'],
        '你好');
    expect(
        build('https://api.siliconflow.cn.evil.example/v1',
            'FunAudioLLM/CosyVoice2-0.5B')['input'],
        '你好');
  });
  test('custom OpenAI remains standard unless instructions explicitly enabled',
      () {
    final base = <String, dynamic>{
      'model': 'custom',
      'input': '你好',
      'voice': 'fixed'
    };
    final result = applyCallSpeechStyle(base,
        protocol: 'openai',
        model: 'custom',
        baseUrl: 'https://custom.example/v1',
        style: style);
    expect(result.keys.toSet(), {'model', 'input', 'voice', 'speed'});
    expect(result['input'], '你好');
    final enabled = applyCallSpeechStyle(base,
        protocol: 'openai',
        model: 'custom',
        baseUrl: 'https://custom.example/v1',
        style: style,
        supportsInstructions: true);
    expect(enabled['instructions'], contains('开心'));
    expect(enabled['input'], '你好');
  });
  test('parameter rejection is eligible for basic speech retry only', () {
    expect(shouldRetryBasicSpeech(400, 'unsupported emotion'), isTrue);
    expect(shouldRetryBasicSpeech(422, '{"error":"invalid speed"}'), isTrue);
    expect(shouldRetryBasicSpeech(401, 'invalid emotion'), isFalse);
    expect(shouldRetryBasicSpeech(429, 'parameter error'), isFalse);
    expect(
        shouldRetryBasicSpeech(200,
            '{"base_resp":{"status_code":1004,"status_msg":"invalid emotion"}}'),
        isTrue);
  });
  test(
      'parser accepts a prefixed JSON envelope and preserves numeric or boolean JSON',
      () {
    expect(CallSpeechReply.parse('前置说明 {"text":"你好","speech":{}}').text, '你好');
    expect(CallSpeechReply.parse('123').text, '123');
    expect(CallSpeechReply.parse('true').text, 'true');
  });
}
