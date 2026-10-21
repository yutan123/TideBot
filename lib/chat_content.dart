class ChatReplyContent {
  const ChatReplyContent(this.text, {this.innerThought});
  final String text;
  final String? innerThought;
}

// Match task-planning openings with response-planning cues, not all English.
const _planningOpenings = [
  'given the ',
  'considering the ',
  'need to ',
  'i need to ',
  'we need to ',
  'let me ',
  'the user',
  'analysis:',
  'reasoning:',
  'thinking:',
  '分析：',
  '思考：',
  '用户的',
  '用户问',
  '我需要',
  '首先需要',
];

bool _isPlanning(String text) {
  final value = text.trimLeft().toLowerCase();
  if (!_planningOpenings.any(value.startsWith)) return false;
  final hasPlanning = RegExp(
    r'\b(?:appropriate|suitable|should|must|need to|how to|craft|generate|formulate|ensure|considering)\b|(?:需要|应该|应当|分析|考虑|如何)',
    caseSensitive: false,
  ).hasMatch(value);
  final hasMeta = RegExp(
    r'\b(?:the user|user.s (?:query|request|message)|persona|character|system prompt|instructions?|(?:appropriate|suitable) response|(?:craft|generate|formulate) (?:a |the )?(?:reply|response))\b|(?:用户.{0,12}(?:问|消息|意图|要求)|角色|系统指令|回复策略|输出格式)',
    caseSensitive: false,
  ).hasMatch(value);
  return hasPlanning && hasMeta;
}

String _replySource(String raw) => raw
    .replaceFirst(
      RegExp(r'^\s*(?:(?:data|event)\s*:\s*)?response\s*[:：]\s*',
          caseSensitive: false),
      '',
    )
    .replaceFirst(
      RegExp(r'^\s*\[心情\s*[:：][^\]\n]*\]\s*'),
      '',
    )
    .trim();

/// Protocol metadata is model context, never visible chat text.
String stripChatMetadata(String raw) {
  var text = raw.replaceAll(
    RegExp(r'\[(?:(?:你|对方)发送了一个表情包，表情包类型|发送时间)\s*[:：][^\]]*\]'),
    '',
  );
  // Hold a split opening anywhere in a cumulative stream, including mid-sentence.
  final start = text.lastIndexOf('[');
  if (start >= 0 && !text.substring(start).contains(']')) {
    final tail = text.substring(start);
    const prefixes = [
      '[你发送了一个表情包，表情包类型',
      '[对方发送了一个表情包，表情包类型',
      '[发送时间',
    ];
    if (prefixes
        .any((prefix) => prefix.startsWith(tail) || tail.startsWith(prefix))) {
      text = text.substring(0, start);
    }
  }
  return text;
}

/// Parse one complete/cumulative reply. No state is shared between requests.
ChatReplyContent parseChatReply(String raw) {
  var text = _replySource(stripChatMetadata(raw));
  // Keep examples of internal tags inside a real source-code block intact.
  if (RegExp(r'^```(?!text\b|plaintext\b)[a-z][\w+-]*\s*\n',
          caseSensitive: false)
      .hasMatch(text)) {
    return ChatReplyContent(text);
  }
  if (_isPlanning(text)) {
    // Require an explicit final boundary instead of guessing where prose ends.
    final boundary = RegExp(
      r'<inner_thought\b|```(?:text|plaintext)?\s*\n|^(?:final(?: answer)?|answer|最终回答|正文)\s*[:：]\s*',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    if (boundary == null) return const ChatReplyContent('');
    text = text.substring(boundary.start).replaceFirst(
          RegExp(r'^(?:final(?: answer)?|answer|最终回答|正文)\s*[:：]\s*',
              caseSensitive: false),
          '',
        );
  }
  // Unwrap presentation fences; keep actual source-code fences.
  final fence = RegExp(r'^```(?:text|plaintext)?\s*\n([\s\S]*?)\n```\s*$',
          caseSensitive: false)
      .firstMatch(text);
  if (fence != null) text = fence.group(1)!;
  String? thought;
  text = text.replaceAllMapped(
    RegExp(
        r'<(inner_thought|think|analysis|reasoning|tool_call)\b[^>]*>([\s\S]*?)</\1\s*>',
        caseSensitive: false),
    (match) {
      if (match.group(1)!.toLowerCase() == 'inner_thought') {
        final value = match.group(2)!.trim();
        if (value.isNotEmpty && !_isPlanning(value)) thought = value;
      }
      return '';
    },
  );
  text = text.replaceFirst(
    RegExp(r'<(?:inner_thought|think|analysis|reasoning|tool_call)\b[\s\S]*$',
        caseSensitive: false),
    '',
  );
  final partialTag = RegExp(r'<[^>]*$').firstMatch(text);
  if (partialTag != null) {
    final suffix = partialTag.group(0)!.toLowerCase();
    if (['<inner_thought', '<think', '<analysis', '<reasoning', '<tool_call']
        .any((tag) => tag.startsWith(suffix))) {
      text = text.substring(0, partialTag.start);
    }
  }
  text = text.replaceAll(
      RegExp(r'<tool_call>[\s\S]*?</tool_call>', caseSensitive: false), '');
  text = text.trim();
  if (_isPlanning(text)) {
    final finalReply = parseChatReply(text);
    return ChatReplyContent(finalReply.text,
        innerThought: thought ?? finalReply.innerThought);
  }
  return ChatReplyContent(text, innerThought: thought);
}

String cleanChatContent(String value) => parseChatReply(value).text;

/// Hold ambiguous openings before they reach the UI; ordinary text streams.
class ChatReplyStream {
  final _raw = StringBuffer();
  String _sent = '';
  ChatReplyContent get content => parseChatReply(_raw.toString());

  String add(String delta) {
    _raw.write(delta);
    final raw = _replySource(_raw.toString()).toLowerCase();
    final visible = content.text.toLowerCase();
    if (_planningOpenings.any((prefix) =>
            prefix.startsWith(raw) ||
            raw.startsWith(prefix) ||
            prefix.startsWith(visible) ||
            visible.startsWith(prefix)) ||
        '[心情'.startsWith(raw) ||
        raw.startsWith('[心情') ||
        raw.startsWith('```') ||
        '```'.startsWith(raw) ||
        'response:'.startsWith(raw) ||
        raw.startsWith('response:') ||
        'data:'.startsWith(raw) ||
        raw.startsWith('data:') ||
        'event:'.startsWith(raw) ||
        raw.startsWith('event:')) return '';
    return _takeVisible();
  }

  String finish() => _takeVisible();

  String _takeVisible() {
    final visible = content.text;
    if (!visible.startsWith(_sent)) return '';
    final delta = visible.substring(_sent.length);
    _sent = visible;
    return delta;
  }
}
