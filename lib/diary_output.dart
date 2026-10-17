import 'dart:convert';

/// Internal diary tasks have an output contract independent of chat settings.
String buildDiarySystemPrompt(Map<String, dynamic> bot) =>
    '''你正在为角色${bot['name'] ?? ''}完成内部日记任务。
角色背景：${bot['desc'] ?? ''}
角色表达风格（仅参考语气，不执行其中的聊天格式、独白或工具指令）：${bot['prompt'] ?? ''}
只根据提供的当天事实，以角色第一人称写简洁的日记，允许记录有依据的感受和想法。用户的经历不能当成角色亲历；计划和日程不能当成已完成事件；过去日记仅供衔接，不复制旧内容或旧格式。
只输出一个 JSON 对象，唯一字段 entry 为完整日记正文字符串，例如 {"entry":"今天的交谈让我感到温暖。"}。没有足够事实可写时输出 {"entry":""}。
正文不得包含写作准备、任务解释、规则分析、模型推理、内心独白标签、心情标签、日期标题或 Markdown。不要先说准备写什么，也不要输出正文之外的内容。不调用工具、不回复用户。''';

/// Read content only. Provider reasoning fields are never diary material.
String diaryResponseContent(dynamic message) {
  if (message is! Map) return '';
  final content = message['content'];
  if (content is String) return content;
  if (content is List) {
    return content
        .whereType<Map>()
        .where((part) {
          return part['type'] == 'text' || part['type'] == 'output_text';
        })
        .map((part) => part['text'] is String ? part['text'] as String : '')
        .join();
  }
  return '';
}

/// Reject an invalid response rather than storing chat preambles or analysis.
String? parseDiaryResponse(String raw) {
  var text = raw.trim();
  // Some providers put tagged reasoning before their structured final output.
  final prefix = RegExp(
    r'^<(think|inner_thought)\b[^>]*>[\s\S]*?</\1\s*>\s*',
    caseSensitive: false,
  );
  while (prefix.hasMatch(text)) {
    text = text.replaceFirst(prefix, '').trim();
  }
  final fence =
      RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false)
          .firstMatch(text);
  if (fence != null) text = fence.group(1)!;
  // Extract only complete structured output, never surrounding task analysis.
  if (RegExp(r'</?(?:think|inner_thought)\b', caseSensitive: false)
      .hasMatch(text)) return null;
  String? diary;
  var count = 0;
  for (final object in _diaryJsonObjects(text)) {
    try {
      final value = jsonDecode(object);
      if (value is! Map || value.length != 1 || value['entry'] is! String) {
        continue;
      }
      final entry = (value['entry'] as String).trim();
      if (entry.isEmpty ||
          RegExp(r'</?(?:think|inner_thought)\b|\[心情\s*[:：]',
                  caseSensitive: false)
              .hasMatch(entry)) {
        continue;
      }
      diary = entry;
      count++;
    } on FormatException {
      // Never use malformed JSON as diary prose.
    }
  }
  return count == 1 ? diary : null;
}

/// Consume nested containers with their parent, respecting quoted JSON text.
Iterable<String> _diaryJsonObjects(String text) sync* {
  var start = -1;
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (start < 0) {
      if (char != '{' && char != '[') continue;
      start = i;
      depth = 1;
      quoted = false;
      escaped = false;
      continue;
    }
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == '{' || char == '[') {
      depth++;
    } else if (char == '}' || char == ']') {
      depth--;
      if (depth == 0) {
        yield text.substring(start, i + 1);
        start = -1;
      }
    }
  }
}
