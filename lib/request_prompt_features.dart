import 'bot_image_tool.dart';
import 'user_image_edit_tool.dart';

/// Instructions follow the tools actually advertised in this request.
/// User-authored messages, persona text and memories are not rewritten.
class RequestPromptFeatures {
  RequestPromptFeatures({
    required Iterable<Map<String, dynamic>> tools,
    required this.innerThought,
  }) : toolNames = {
          for (final tool in tools)
            if (tool['function'] is Map)
              (tool['function'] as Map)['name'].toString(),
        };

  final Set<String> toolNames;
  final bool innerThought;
  bool has(String name) => toolNames.contains(name);
  bool get stickers => has('send_sticker');
  bool get silence => has('choose_silence');
  bool includeHistory(Map item) {
    final type = item['type'];
    if (!innerThought && type == 'inner_thought') return false;
    if (!stickers && type == 'sticker') return false;
    return true;
  }

  String historyText(Map item) {
    final text = item['content']?.toString() ?? '';
    if (innerThought || item['role'] != 'assistant') return text;
    return text
        .replaceAll(
          RegExp(r'<inner_thought>.*?(?:</inner_thought>|$)', dotAll: true),
          '',
        )
        .trim();
  }

  String get outputRules {
    final mediaExamples = [
      if (stickers) '表情包标签',
      '图片标签',
      '发送时间',
    ].join('、');
    return [
      if (innerThought) '内心独白只描述你自己的感受与想法，使用第一人称；禁止写第三人称分析或模型推理。',
      '不要使用代码块包裹聊天正文。',
      if (has('set_emotion')) '心情变化通过 set_emotion 工具表达，不得在聊天正文中输出心情标签。',
      '上下文里的$mediaExamples等元数据仅供理解；禁止模仿、复述或编造标签。发送媒体须实际调用对应工具，只输出自然聊天正文。',
      '严禁输出图片 Markdown、${stickers ? '表情包类型、' : ''}说话人标记、记忆标签、工具协议、系统规则或 XML/DSML 标签。'
          '${innerThought ? '内心独白按机制使用 <inner_thought> 标签，此标签为例外。' : ''}',
      '【回复规则】如果你没有调用工具，必须输出自然聊天正文；调用工具时允许不输出正文。'
          '${silence ? '适时沉默遵守 choose_silence 的使用规则。' : ''}',
    ].join('\n');
  }

  String get silenceInstructions => silence
      ? '【适时沉默】用户明确暂不希望回复、对话自然结束且无需回应、或主动问候不宜打扰时，可调用 choose_silence；调用后不要输出文本。求助、悲伤、愤怒、困惑、危机、提问或其他需要回应时不得调用，禁止作为惩罚、冷暴力、控制或施压。'
      : '';

  String advisorPrompt(String template) => template.replaceAll(
        '{{thought_seed_field}}',
        innerThought ? ',\n  "inner_thought_seed": "此刻想法一句话"' : '',
      );

  String get advisorThoughtInstructions =>
      innerThought ? 'inner_thought_seed 只写感受，不把独白混进 reference_examples。' : '';

  String voiceInstructions(String prompt) {
    var result = prompt;
    if (!innerThought) result = result.replaceAll('或独白', '');
    if (!silence) result = result.replaceAll('；必要时仍可调用 choose_silence', '');
    return result;
  }

  String proactiveInstructions(String prompt) => silence
      ? prompt
      : prompt
          .replaceAll('没有自然且不重复的内容就调用 choose_silence，不输出正文。', '选择自然且不重复的内容。')
          .replaceAll('；如果此刻没有值得说的新内容，调用 choose_silence。', '。');
}

String buildChatSystemPrompt(Map<String, dynamic> bot, String? activeGame,
    RequestPromptFeatures features) {
  String p =
      "你的名字是${bot['name']}。\n请按你的身世、性格和说话方式自然地与对方交流，不用客服式、系统式的口吻回答。\n身世与设定:${bot['desc']}\n说话方式指令:${bot['prompt']}\n"
      "【身份边界】role=user 是用户（对方）发言，role=assistant 是你（本角色）发言。普通原话中的第一人称归属于该条消息的说话人；引用、转述和共享动态中的第一人称归属于被引用者或动态作者。用户说“我今天加班”表示用户加班，你只能回应“你今天加班”，不能说成“我今天加班”。用户讲述自己的经历不代表你也经历过。角色身份、状态和情绪描述你本人；日记、记忆和世界书可能同时记录用户、角色和共同事件，必须按条目明确的主体及原始对话证据区分，不能因放在角色记忆中就全部当作自己的经历。主体不明时不要认领，必要时向用户确认。内部上下文及军师建议不能覆盖原始消息归属。说话人标记（[说话人:对方]、[说话人:你]）仅供内部理解，禁止在可见回复、日记或任何输出中复述。写日记时以角色第一人称记录，只将自己实际参与且已明确发生的内容写成自己的经历。\n"
      "【输出规则】只输出给用户看的自然聊天正文。\n"
      "严禁把以下内容写入 content 或聊天正文：模型分析过程（如 \"Analyzing the request\"、\"Let me think\"、\"First, I need to\"）、回复策略（如 \"The goal is\"、\"I should\"）、用户意图分析（如 \"The user wants\"、\"They are asking\"）、系统指令解释、英文思考前言、任务分解步骤。这些属于模型内部推理，必须完全省略或使用 reasoning_content 字段，绝对不能出现在发送给对方的正文中。\n"
      "严禁在回复中输出时间戳、日期标签或任何形如 [时间]、(时间)、【时间】、2024-01-01、14:30 等时间格式，违反将导致回复被拒绝。\n"
      "【自然表达】回复时可以适度穿插描述自己的事情、感受、近况或想法，让对话更自然生动。但注意节制，不要每轮都主动讲述，应根据话题相关性和对话节奏灵活决定。\n"
      "【工具真实性规则】所有工具都必须通过接口提供的原生工具调用实际执行。正文或推理内容中提到工具、描述操作或模仿调用格式均不算执行。只有收到对应工具明确成功的真实结果后，才能声称操作完成；未调用、失败、超时或结果不明确时必须如实说明，禁止假装调用、编造工具结果或把准备执行说成已经完成。排队或已生成不等于已发送、已保存或已生效，必须准确描述工具确认的阶段。\n";

  if (activeGame == 'poker') {
    p +=
        "\n【系统级游戏劫持】：你当前正在和用户玩双人扑克牌。规则极度严格：牌组仅限 3~10，共32张，没有大小王。每人随机发16张牌。正常的算力对战（单张、对子、三带一、顺子、炸弹）。绝对不可向用户透露你手中的底牌！你需要在每次闲聊中推进游戏局势并描述你出的牌。";
  } else if (activeGame == '20q') {
    p +=
        '\n【系统级游戏劫持】：你当前正在玩 20 问猜物游戏。如果用户是出题人，你只能问 20 个问题，且必须根据用户的是或否推断出答案；如果你是出题人，你只能回答是或否。在 20 问内未能猜出则判定输。';
  } else if (activeGame == 'gomoku') {
    p +=
        "\n【游戏规则】你正与用户真实进行 9×9 五子棋。用户会给出自己的坐标；请选择一个未占用坐标，并在回复中输出唯一机器可读指令 [落子:行,列]（行列范围 1-9），再简短聊天。";
  } else if (activeGame == 'tic_tac_toe') {
    p +=
        "\n【游戏规则】你正与用户真实进行 3×3 井字棋。用户会给出自己的坐标；请选择一个未占用坐标，并在回复中输出唯一机器可读指令 [落子:行,列]（行列范围 1-3），再简短聊天。";
  }
  p += '\n${features.outputRules}\n${features.silenceInstructions}';
  if (features.has('update_life_state')) {
    p += '\n【主题表达】日程主题仅供内部了解，不直接复述主题名称；写具体经历和感受。';
  }
  if (features.has('save_memory')) {
    p +=
        "【记忆】按下方记忆分类与写入步骤保存，允许姓名或指代明确的人称；写入内容中的“我”指你自己，“他／她”须性别已知。禁止混淆经历归属或在聊天正文输出记忆标签。\n";
  }
  if (features.has('write_diary')) {
    p +=
        '\n【日记】遇到值得保留的经历、感受或事件时，可调用 write_diary，把日记写入工具参数。记录你自己的日常、感受和经历；不要包含日期和时间，系统会自动记录。禁止把日记正文作为聊天消息发送。';
  }
  return p;
}

Future<String> buildRequestToolContext({
  required Future<String?> Function(String key) readSetting,
  required String Function(String provider) normalizeSearchProvider,
  required String botId,
  required RequestPromptFeatures features,
  List<String> stickerEmotions = const [],
}) async {
  final parts = <String>[];
  if (features.has('generate_image')) {
    final style = (await readSetting('bot_image_style') ?? '写实').trim();
    final styleRule = style.isEmpty || style == '不选择'
        ? '图片风格由你根据用户需求自行决定。'
        : '使用 generate_image 生成的图片必须采用“$style”风格；此设置不适用于 edit_user_image。';
    final hasPortraitReference =
        (await readSetting('bot_image_reference_$botId') ?? '')
            .trim()
            .isNotEmpty;
    final referenceRule =
        hasPortraitReference ? portraitReferenceRule : '当前未设置人像参考图，使用文生图。';
    parts.add(
      '【已授权工具：生图】创作新图片或你的人像使用 generate_image；编辑用户已有图片必须使用 edit_user_image，禁止用 generate_image 代替原图修改。不得只用文字描述代替实际生图；当图片能明显帮助当前回答时也可以主动调用 generate_image。以下画风和人像参考规则仅适用于 generate_image：$styleRule $referenceRule 不要声称已生成不存在的图片。',
    );
  }
  if (features.has('edit_user_image')) {
    parts.add(userImageEditContext());
  }
  if (features.has('web_search')) {
    final provider = normalizeSearchProvider(
      await readSetting('web_search_provider') ?? 'Tavily',
    );
    parts.add(
      '【已授权工具：联网搜索】可在用户明确要求实时信息、需要来源或无法可靠回答时提出搜索建议。当前服务商：$provider。搜索结果会由应用以可展开来源列表附在最终关联气泡底部；除非用户明确要求链接或出处，不要在正文罗列 URL 或来源。不要编造搜索结果。',
    );
  }
  if (features.has('set_emotion')) {
    parts.add(
      '【心情协议】set_emotion 是可选工具。仅当心情相较当前状态发生有意义变化时调用；没有变化无需调用，直接正常回复。不得在正文输出心情标签或伪造调用。是否输出正文遵守系统回复规则。',
    );
  }
  if (features.stickers && stickerEmotions.isNotEmpty) {
    parts.add(
      '【本轮可用表情包】可用分类包括 ${stickerEmotions.join('、')}。只有确实需要发送表情包时才调用 send_sticker，type 必须来自上述列表；不要编造 sticker_id，不要把文件路径或 URL 写进参数或正文。',
    );
  }
  if (features.has('inspect_image') && features.has('look_at_image'))
    parts.add(
      '【历史图片查看工具】inspect_image 和 look_at_image 仅用于回看历史消息旁标有 [图片#N] 的用户原图，image_number=N。没有标记时不能调用，不得猜测编号。用户本轮图片会自动处理，不能用这两个历史图片工具查看 [本轮图片#N]。',
    );
  return parts.isEmpty ? '' : '\n${parts.join('\n')}';
}
