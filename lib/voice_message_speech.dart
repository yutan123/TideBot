import 'call_speech.dart';

/// Speech direction is request-local and does not change persistent mood.
Map<String, dynamic> voiceMessageSpeechSchema() => {
      'type': 'object',
      'properties': {
        'emotion': {
          'type': 'string',
          'enum': CallSpeechStyle.emotions.keys.toList(),
          'description':
              '基础情绪兼容字段，必须使用枚举中的英文值。复杂、混合或自定义情绪写入 direction，并在此填写最接近的基础情绪；不要把中文说明填入本字段。',
        },
        'intensity': {
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
          'description': '本条语音的情绪强度，填写 0 到 1 的 JSON 数字，例如 0.4；不要填写字符串、百分比或文字。',
        },
        'pace': {
          'type': 'string',
          'enum': ['slightly_slow', 'normal', 'slightly_fast'],
          'description':
              '基础语速兼容字段：slightly_slow 表示稍慢，normal 表示正常，slightly_fast 表示稍快。逐句语速变化、停顿和节奏细节自由写入 direction。',
        },
        'delivery': {
          'type': 'string',
          'enum': ['natural', 'gentle'],
          'description':
              '基础发声兼容字段，只填写 natural（自然发声）或 gentle（轻柔发声）。本字段不接受中文演绎段落；自定义发声质感、轻重、松紧及情绪变化统一写入 direction。',
        },
        'direction': {
          'type': 'string',
          'description':
              '自定义演绎指导，填写非空中文文本，建议 80～180 字，最多 600 字。结合本轮实际正文和角色，自由描述复杂或混合情绪、强弱变化、发声质感、语速、停顿、具体词句的重音和句尾语调；表达不限于基础枚举。保持所选音色，不增添正文，不朗读指导本身；短句按实际需要描述，不强行添加笑声或叹气。',
        },
      },
      'required': ['emotion', 'intensity', 'pace', 'delivery', 'direction'],
      'additionalProperties': false,
    };

CallSpeechStyle? parseVoiceMessageSpeech(dynamic value) {
  if (value is! Map ||
      !CallSpeechStyle.emotions.containsKey(value['emotion']) ||
      value['intensity'] is! num ||
      !(value['intensity'] as num).isFinite ||
      (value['intensity'] as num) < 0 ||
      (value['intensity'] as num) > 1 ||
      !const [
        'slightly_slow',
        'normal',
        'slightly_fast',
      ].contains(value['pace']) ||
      !const ['natural', 'gentle'].contains(value['delivery']) ||
      value['direction'] is! String ||
      (value['direction'] as String).trim().isEmpty) {
    return null;
  }
  return CallSpeechStyle.fromJson(value);
}

const voiceMessageSpeechPrompt = '【本轮语音消息】本轮已选中语音回复。先调用 request_voice_reply，'
    '在 speech 参数里根据本轮语义和角色表达填写情绪、强度、节奏、发声方式及具体演绎指导。'
    '五个字段必须齐全：emotion 只能填写 neutral/happy/sad/comforting/worried/surprised/serious；'
    'intensity 填写 0 到 1 的数字；pace 只能填写 slightly_slow/normal/slightly_fast；'
    'delivery 只能填写 natural/gentle，不要在这里填写中文演绎说明。'
    '这些是基础兼容字段；自定义情绪、复杂语气、发声质感及逐句变化自由写入 direction，表达不限于枚举。'
    'direction 使用非空中文，建议 80～180 字、最多 600 字，结合实际正文说明如何读，保持角色音色。'
    '结构示例：{"speech":{"emotion":"happy","intensity":0.4,"pace":"normal","delivery":"natural",'
    '"direction":"开头带一点克制的期待，声音明亮而放松；中间稍作停顿，重点词轻轻加重，末句语调柔和下落。"}}。'
    '示例只说明参数格式，实际情绪和指导必须按本轮内容独立生成，不照搬。'
    '然后按正常聊天规则输出正文；语音参数只写入工具，不写进正文或独白。'
    'speech 只控制本条语音，不要求修改长期心情；必要时仍可调用 choose_silence。';
