import 'call_speech.dart';

/// Speech direction is request-local and does not change persistent mood.
Map<String, dynamic> voiceMessageSpeechSchema() => {
  'type': 'object',
  'properties': {
    'emotion': {
      'type': 'string',
      'enum': CallSpeechStyle.emotions.keys.toList(),
    },
    'intensity': {'type': 'number', 'minimum': 0, 'maximum': 1},
    'pace': {
      'type': 'string',
      'enum': ['slightly_slow', 'normal', 'slightly_fast'],
    },
    'delivery': {
      'type': 'string',
      'enum': ['natural', 'gentle'],
    },
    'direction': {
      'type': 'string',
      'description': '结合本轮准备说的内容，说明情绪强弱、语速、停顿、重音及句尾语调；保持角色音色，不朗读指导本身。',
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

const voiceMessageSpeechPrompt =
    '【本轮语音消息】本轮已选中语音回复。先调用 request_voice_reply，'
    '在 speech 参数里根据本轮语义和角色表达填写情绪、强度、节奏、发声方式及具体演绎指导。'
    '然后按正常聊天规则输出正文；语音参数只写入工具，不写进正文或独白。'
    'speech 只控制本条语音，不要求修改长期心情；必要时仍可调用 choose_silence。';
