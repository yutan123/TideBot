import 'dart:convert';

import 'tool_call_accumulator.dart';

/// Keep protocol content separate from the filtered text shown in chat.
Map<String, dynamic> toolAssistantMessage(Map message) => {
      'role': 'assistant',
      'content': message['content'],
      if (message['tool_calls'] is List) 'tool_calls': message['tool_calls'],
      for (final key in ['reasoning_content', 'reasoning', 'reasoning_details'])
        if (message[key] != null) key: message[key],
    };

/// Some compatible endpoints return JSON even when stream=true.
/// Tool continuations are buffered so partial protocol text never reaches UI.
Map<String, dynamic> decodeToolCompletion(String body) {
  final trimmed = body.trimLeft();
  if (trimmed.startsWith('{')) {
    return Map<String, dynamic>.from(jsonDecode(body) as Map);
  }
  final result = <String, dynamic>{};
  final content = StringBuffer();
  final reasoning = <String, StringBuffer>{};
  final calls = ToolCallAccumulator();
  Map<String, dynamic>? snapshot;
  var sawEvent = false;
  for (final line in const LineSplitter().convert(body)) {
    if (!line.startsWith('data:')) continue;
    final data = line.substring(5).trim();
    if (data.isEmpty) continue;
    if (data == '[DONE]') break;
    final event = jsonDecode(data);
    if (event is! Map) continue;
    if (event['error'] != null)
      throw FormatException('工具后续响应错误：${event['error']}');
    sawEvent = true;
    for (final key in ['id', 'model', 'system_fingerprint', 'usage']) {
      if (event[key] != null) result[key] = event[key];
    }
    final choices = event['choices'];
    if (choices is! List || choices.isEmpty) continue;
    final choice = choices.first as Map;
    if (choice['message'] is Map) {
      snapshot = toolAssistantMessage(choice['message'] as Map);
    }
    final delta = choice['delta'];
    if (delta is! Map) continue;
    if (delta['content'] is String) content.write(delta['content']);
    for (final key in ['reasoning_content', 'reasoning']) {
      if (delta[key] is String) {
        reasoning.putIfAbsent(key, StringBuffer.new).write(delta[key]);
      }
    }
    if (delta['tool_calls'] is List) calls.add(delta['tool_calls'] as List);
  }
  if (!sawEvent) throw const FormatException('工具后续响应不是有效 JSON 或 SSE');
  result['choices'] = [
    {
      'message': snapshot ??
          {
            'role': 'assistant',
            'content': content.isEmpty ? null : content.toString(),
            if (calls.calls.isNotEmpty) 'tool_calls': calls.calls,
            for (final entry in reasoning.entries)
              entry.key: entry.value.toString(),
          },
    }
  ];
  return result;
}
