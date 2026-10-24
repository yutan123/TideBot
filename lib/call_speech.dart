import 'dart:convert';

import 'chat_content.dart';

/// Voice direction is local to a call; it never changes the bot's mood state.
class CallSpeechStyle {
  const CallSpeechStyle(
      {this.emotion = 'neutral',
      this.intensity = .4,
      this.pace = 'normal',
      this.delivery = 'natural'});

  final String emotion;
  final double intensity;
  final String pace;
  final String delivery;
  static const emotions = {
    'neutral': '自然',
    'happy': '开心',
    'sad': '难过',
    'comforting': '安抚',
    'worried': '担心',
    'surprised': '惊讶',
    'serious': '认真',
  };

  factory CallSpeechStyle.fromJson(dynamic value) {
    if (value is! Map) return const CallSpeechStyle();
    final level = value['intensity'];
    return CallSpeechStyle(
      emotion: emotions.containsKey(value['emotion'])
          ? value['emotion'] as String
          : 'neutral',
      intensity:
          level is num && level.isFinite ? level.toDouble().clamp(0, 1) : .4,
      pace: const ['slightly_slow', 'normal', 'slightly_fast']
              .contains(value['pace'])
          ? value['pace'] as String
          : 'normal',
      delivery: value['delivery'] == 'gentle' ? 'gentle' : 'natural',
    );
  }

  CallSpeechStyle moderated(
      {CallSpeechStyle? previous, String strength = 'natural'}) {
    final scale =
        switch (strength) { 'restrained' => .6, 'expressive' => 1.2, _ => 1.0 };
    var level = (intensity * scale).clamp(0.0, .85);
    if (previous != null)
      level = level.clamp((previous.intensity - .25).clamp(0, 1),
          (previous.intensity + .25).clamp(0, 1));
    return CallSpeechStyle(
        emotion: emotion, intensity: level, pace: pace, delivery: delivery);
  }

  double get speed => switch (pace) {
        'slightly_slow' => 1 - .12 * intensity,
        'slightly_fast' => 1 + .12 * intensity,
        _ => 1,
      };

  String get instruction {
    final rhythm = switch (pace) {
      'slightly_slow' => '节奏稍慢',
      'slightly_fast' => '节奏稍快',
      _ => '正常节奏'
    };
    return '保持所选音色与原有身份，只朗读目标正文。用${emotions[emotion] ?? '自然'}的语气，'
        '情绪${intensity < .35 ? '克制' : intensity < .65 ? '适中' : '较丰富'}，$rhythm，'
        '${delivery == 'gentle' ? '轻柔发声' : '自然发声'}；不要夸张表演，不朗读指令。';
  }
}

const callSpeechPrompt = '''本轮是通话回复。最终回复只输出一个 JSON 对象，不要代码围栏、独白或协议标签：
{"text":"实际要说的简短自然口语","speech":{"emotion":"neutral","intensity":0.4,"pace":"normal","delivery":"natural"}}
text 只含对用户说的话。speech 只指导朗读，不能写入 text。
emotion 只能为 neutral/happy/sad/comforting/worried/surprised/serious；intensity 为 0 到 1，默认克制自然；pace 为 slightly_slow/normal/slightly_fast；delivery 为 natural/gentle。
依据角色、用户语义及本轮正文选择情绪，不生硬套用当前心情，不改变音色。先完成必要工具调用，最终再输出该对象。''';

class CallSpeechReply {
  const CallSpeechReply(this.text, this.style);
  final String text;
  final CallSpeechStyle style;

  factory CallSpeechReply.parse(String raw) {
    var source = cleanChatContent(raw).trim();
    source = source
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    final envelope = source.indexOf('{');
    if (envelope > 0 &&
        (source.contains('"speech"') || source.contains('"text"'))) {
      source = source.substring(envelope);
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return CallSpeechReply(
            decoded['text'] is String
                ? cleanChatContent(decoded['text'] as String).trim()
                : '',
            CallSpeechStyle.fromJson(decoded['speech']));
      }
      if (decoded is num || decoded is bool)
        return CallSpeechReply(source, const CallSpeechStyle());
      // A JSON string is safe to read, but metadata arrays are not.
      if (decoded is String)
        return CallSpeechReply(
            cleanChatContent(decoded), const CallSpeechStyle());
      return const CallSpeechReply('', CallSpeechStyle());
    } catch (_) {
      // Recover a complete escaped text field even when the metadata is broken.
      if (source.startsWith('{') || source.startsWith('[')) {
        final text =
            RegExp(r'"text"\s*:\s*("(?:\\.|[^"\\])*")').firstMatch(source);
        if (text != null) {
          try {
            return CallSpeechReply(
                cleanChatContent(jsonDecode(text.group(1)!) as String),
                const CallSpeechStyle());
          } catch (_) {}
        }
        return const CallSpeechReply('', CallSpeechStyle());
      }
      // Older/custom models may ignore the JSON format; retain plain speech.
      return CallSpeechReply(source, const CallSpeechStyle());
    }
  }
}

/// Apply only documented capabilities. Unknown OpenAI-compatible models keep
/// standard fields and never receive provider-specific instruction text.
Map<String, dynamic> applyCallSpeechStyle(
  Map<String, dynamic> base, {
  required String protocol,
  required String model,
  required String baseUrl,
  required CallSpeechStyle style,
  bool supportsInstructions = false,
}) {
  final payload = Map<String, dynamic>.from(base);
  if (protocol == 'minimax') {
    final voice = Map<String, dynamic>.from(base['voice_setting'] as Map);
    voice['speed'] = style.speed;
    voice['pitch'] = 0;
    // MiniMax has no numeric emotion-strength parameter. Do not invent one.
    final emotion = switch (style.emotion) {
      'happy' => 'happy',
      'sad' => 'sad',
      'surprised' => 'surprised',
      'neutral' || 'comforting' || 'serious' => 'calm',
      _ => null,
    };
    if (emotion != null &&
        const {
          'speech-01-hd',
          'speech-01-turbo',
          'speech-02-hd',
          'speech-02-turbo',
          'speech-2.6-hd',
          'speech-2.6-turbo',
          'speech-2.8-hd',
          'speech-2.8-turbo',
        }.contains(model)) voice['emotion'] = emotion;
    payload['voice_setting'] = voice;
  } else if (protocol == 'mimo') {
    payload['messages'] = [
      {'role': 'user', 'content': style.instruction},
      ...List<Map<String, dynamic>>.from(base['messages'] as List),
    ];
  } else {
    payload['speed'] = style.speed;
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    final silicon =
        host == 'api.siliconflow.cn' || host == 'api.siliconflow.com';
    if (silicon &&
        RegExp(r'^(?:FunAudioLLM|Pro/FunAudioLLM)/CosyVoice2-0\.5B$')
            .hasMatch(model)) {
      payload['input'] = '${style.instruction}<|endofprompt|>${base['input']}';
    } else if (supportsInstructions) {
      payload['instructions'] = style.instruction;
    }
  }
  return payload;
}

/// Some services return parameter errors inside HTTP 200 JSON envelopes.
bool shouldRetryBasicSpeech(int status, String body) {
  if (status != 400 && status != 422 && status != 200) return false;
  if (status == 200) {
    try {
      final value = jsonDecode(body);
      if (value is! Map ||
          value['base_resp'] is! Map ||
          (value['base_resp'] as Map)['status_code'] == 0) return false;
      body = (value['base_resp'] as Map)['status_msg']?.toString() ?? '';
    } catch (_) {
      return false;
    }
  }
  return RegExp(
          r'emotion|instructions|speed|pitch|parameter|unsupported|invalid.*(?:field|argument)|情绪|语速|参数',
          caseSensitive: false)
      .hasMatch(body);
}

String callSpeechCapability(Map<String, dynamic> provider) {
  if (provider['protocol'] == 'minimax') return '原生情绪与语速；强度由模型演绎，不支持数值强度';
  if (provider['protocol'] == 'mimo') return '支持独立的情绪、语气与节奏指令';
  final host =
      Uri.tryParse((provider['base_url'] ?? provider['url'] ?? '').toString())
              ?.host ??
          '';
  if ((host == 'api.siliconflow.cn' || host == 'api.siliconflow.com') &&
      RegExp(r'^(?:FunAudioLLM|Pro/FunAudioLLM)/CosyVoice2-0\.5B$')
          .hasMatch(provider['model']?.toString() ?? ''))
    return 'CosyVoice2 支持情绪与节奏指令';
  return provider['supports_instructions'] == true
      ? '已启用语气指令，需接口支持 instructions'
      : '标准兼容模式，仅调整语速，情绪由模型按正文演绎';
}
