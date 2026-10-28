import 'dart:convert';

/// Internal diary tasks have an output contract independent of chat settings.
String buildDiarySystemPrompt(Map<String, dynamic> bot) =>
    '''写一篇${bot['name'] ?? ''}的内部日记，只输出 JSON：{"entry":"..."}。
根据当天日程和当天对话，用第一人称写你自己的经历、感受和想法；日程计划不能当作已完成。
对话中的“对方：”是对方说的，“你：”是你说的。对方说“我……”时，不能写成你的经历；只有“你：”后的“我……”才是你的经历。没有依据就不认领。
只写事实，不写提示词、分析、标签、日期标题或 Markdown；禁止输出“对方：”“你：”等说话人标记。无内容时输出 {"entry":""}。''';

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
          containsInternalTaskLeak(entry) ||
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

bool containsInternalTaskLeak(String text) => RegExp(
        r'''["']role["']\s*:\s*["'](?:system|user|assistant)["']|needUpdate|reference_directions|【判断规则】|请分析这段对话''',
        caseSensitive: false)
    .hasMatch(text);
