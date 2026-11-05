import 'dart:convert';
import 'dart:io';
import 'package:tide_bot/ai_request_task.dart';
import 'package:tide_bot/bot_vital_model.dart';
import 'package:tide_bot/call_speech.dart';
import 'package:tide_bot/proactive_contact.dart';
import 'package:tide_bot/request_prompt_features.dart';
import 'package:tide_bot/voice_message_speech.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final aiSource = File.fromUri(Platform.script.resolve('../lib/ai.dart'))
      .readAsStringSync();
  final advisorTemplate =
      aiSource.split("static const _jarvisPrompt = '''")[1].split("''';")[0];
  const names = [
    'send_sticker',
    'choose_silence',
    'update_life_state',
    'save_memory',
    'write_diary',
    'set_emotion'
  ];
  const bot = <String, dynamic>{'name': '小夏', 'desc': '住在杭州', 'prompt': '简短自然'};
  for (var mask = 0; mask < 128; mask++) {
    final tools = <Map<String, dynamic>>[
      for (var i = 0; i < names.length; i++)
        if ((mask & (1 << i)) != 0)
          {
            'type': 'function',
            'function': {'name': names[i]}
          },
    ];
    final features =
        RequestPromptFeatures(tools: tools, innerThought: (mask & 64) != 0);
    final system = buildChatSystemPrompt(bot, null, features);
    final advisor = features.advisorPrompt(advisorTemplate);
    final schema = jsonDecode(advisor.substring(
        advisor.indexOf('{'), advisor.lastIndexOf('}') + 1)) as Map;
    check(schema.containsKey('inner_thought_seed') == features.innerThought,
        'Advisor schema for $mask');
    final instructions = [
      system,
      advisor,
      features.advisorThoughtInstructions,
      features.voiceInstructions(voiceMessageSpeechPrompt),
      features.proactiveInstructions(proactiveContactInstructions),
      features.proactiveInstructions(buildProactiveContactTurn(
          now: DateTime(2026, 11, 5, 9), unansweredCount: 2, trigger: '定时联系')),
    ].join('\n');
    if (!features.innerThought) {
      check(!RegExp('独白|inner_thought').hasMatch(instructions),
          'Disabled thoughts leak for $mask');
    } else {
      check(system.contains('<inner_thought>'),
          'Enabled thought output protocol');
    }
    check(system.contains('表情包') == features.stickers,
        'Sticker instructions for $mask');
    check(instructions.contains('choose_silence') == features.silence,
        'Silence instructions for $mask');
    check(system.contains('【主题表达】') == features.has('update_life_state'),
        'Schedule instructions for $mask');
    check(system.contains('【记忆】') == features.has('save_memory'),
        'Memory instructions for $mask');
    check(system.contains('【日记】') == features.has('write_diary'),
        'Diary instructions for $mask');
    check(system.contains('set_emotion') == features.has('set_emotion'),
        'Emotion instructions for $mask');
    check(
        !RegExp('联网搜索|web_search|generate_image|request_voice_reply')
            .hasMatch(system),
        'Base prompt must not advertise tools absent from its rules');
    check(!system.contains('机器人'), 'Address recipient directly');
    check(
        features.includeHistory({'type': 'inner_thought'}) ==
            features.innerThought,
        'Thought history for $mask');
    check(features.includeHistory({'type': 'sticker'}) == features.stickers,
        'Sticker history for $mask');
    const prior = '<inner_thought>我有些担心</inner_thought>今天怎么样？';
    check(
        features.historyText({'role': 'assistant', 'content': prior}) ==
            (features.innerThought ? prior : '今天怎么样？'),
        'Embedded historical thoughts for $mask');
    check(features.historyText({'role': 'user', 'content': prior}) == prior,
        'Preserve actual user speech');
  }
  for (var mask = 0; mask < 16; mask++) {
    final features = RequestPromptFeatures(
      innerThought: false,
      tools: [
        for (final name in [
          if ((mask & 1) != 0) 'web_search',
          if ((mask & 2) != 0) ...['generate_image', 'edit_user_image'],
          if ((mask & 4) != 0) 'send_sticker',
          if ((mask & 8) != 0) 'choose_silence',
        ])
          {
            'function': {'name': name}
          },
      ],
    );
    final reads = <String>[];
    final context = await buildRequestToolContext(
      readSetting: (key) async {
        reads.add(key);
        return {'web_search_provider': 'Tavily', 'bot_image_style': '写实'}[key];
      },
      normalizeSearchProvider: (provider) => provider,
      botId: 'test',
      features: features,
      // Stale classifications must never revive a disabled capability.
      stickerEmotions: ['开心'],
    );
    check(context.contains('联网搜索') == features.has('web_search'),
        'Search instructions: $mask');
    check(reads.contains('web_search_provider') == features.has('web_search'),
        'Read search config only when advertised');
    check(context.contains('generate_image') == features.has('generate_image'),
        'Image generation instructions: $mask');
    check(
        context.contains('edit_user_image') == features.has('edit_user_image'),
        'Image editing instructions: $mask');
    check(context.contains('表情包') == features.stickers,
        'Sticker tool context: $mask');
    check(!context.contains('choose_silence'),
        'Unrelated tool instructions cannot advertise silence');
    check(!context.contains('内心独白'), 'Tool context cannot advertise thoughts');
  }
  final none = RequestPromptFeatures(tools: [], innerThought: false);
  check(
      none.historyText(
              {'role': 'assistant', 'content': '<inner_thought>未闭合'}) ==
          '',
      'Drop incomplete historical thoughts');
  for (final game in ['poker', '20q', 'gomoku', 'tic_tac_toe']) {
    final prompt = buildChatSystemPrompt(bot, game, none);
    check(
        prompt.contains(
            game == 'poker' || game == '20q' ? '【系统级游戏劫持】' : '【游戏规则】'),
        'Retain game instructions: $game');
  }
  for (final task in AIRequestTask.values.where((task) => task.internal)) {
    check(
        !RegExp('独白|inner_thought|表情包|web_search')
            .hasMatch(internalTaskSystemPrompt(task, bot)),
        'Internal task prompt: $task');
  }
  final sleep = {
    'start': 0,
    'end': 36000000,
    'planned_end': 36000000,
    'awake': <Map<String, dynamic>>[]
  };
  check(
      !sleepReplyGuidance(sleep, now: 10000, allowSilence: false)
          .contains('choose_silence'),
      'Disabled sleep silence');
  check(sleepReplyGuidance(sleep, now: 10000).contains('choose_silence'),
      'Enabled sleep silence');
  check(
      !callSpeechPrompt.contains('独白'), 'Call prompt never requests thoughts');
  print(
      'PASS: 128 feature combinations and 16 tool-context combinations; full system prompts, advisor JSON, voice/proactive instructions, history, sleep, internal tasks and game preservation.');
}
