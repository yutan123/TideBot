import 'dart:convert';

import 'chat_content.dart';

/// Voice direction is local to a call; it never changes the bot's mood state.
class CallSpeechStyle {
  const CallSpeechStyle(
      {this.emotion = 'neutral',
      this.intensity = .4,
      this.pace = 'normal',
      this.delivery = 'natural',
      this.direction = ''});

  final String emotion;
  final double intensity;
  final String pace;
  final String delivery;
  final String direction;
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
      direction: value['direction'] is String
          ? (value['direction'] as String).trim().substring(
              0, (value['direction'] as String).trim().length.clamp(0, 600))
          : '',
    );
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
        '${delivery == 'gentle' ? '轻柔发声' : '自然发声'}。'
        '${direction.isEmpty ? '' : '本轮具体演绎：$direction。'}'
        '在保持音色的前提下让重音、停顿、语调与句间情绪转折清晰可辨，贴近日常通话，不夸张表演。'
        '以上仅为朗读指导，不朗读指导内容，不增删目标正文。';
  }
}

const callSpeechPrompt = '''本轮是通话回复。最终回复只输出一个 JSON 对象，不要代码围栏或协议标签：
{"text":"实际要说的简短自然口语","speech":{"emotion":"neutral","intensity":0.4,"pace":"normal","delivery":"natural","direction":"针对本轮实际正文的具体朗读指导"}}
text 只含对用户说的话。speech 只指导朗读，不能写入 text，也不要向用户解释语音参数。
每轮根据角色性格、对话上下文、用户语义和本轮实际正文独立生成 speech，由你决定情绪与强度；不要沿用固定模板或默认每次都是平静安抚，也不要为了不同而随机改变情绪。情绪转折应符合当前语义，不受上一轮强度限制。
emotion 只能为 neutral/happy/sad/comforting/worried/surprised/serious；intensity 为 0 到 1，按本轮真实表达需要选择；pace 为 slightly_slow/normal/slightly_fast；delivery 为 natural/gentle。这些兼容参数须与 direction 一致。
direction 用 80～180 字中文，给语音模型可执行的细致演绎指导：说明情绪及其强弱、发声的轻重与松紧、语速和节奏、关键停顿、具体词句的重音、句尾语调，以及开头到结尾的情绪变化。结合 text 中的具体词句说明怎么读，不要只写“温柔、开心、自然”等抽象标签。短句只描述实际存在的变化，不强行添加笑声、叹气或戏剧化表演。
例如安抚时可描述：“开头‘我在’放轻但咬字清楚，语速放慢，之后留一个短停顿；‘慢慢说’重音落在‘慢慢’，声音柔和而稳定；末句‘我听着呢’稍微放暖，句尾轻轻下落，传达认真倾听而非敷衍。”示例仅说明细致程度，不要照搬到无关正文。
保持所选音色与角色身份，不生硬套用当前心情。先完成必要工具调用，最终再输出该对象。''';

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
