// Run with: dart run test/speaker_context_check.dart
// Pure Dart checks; no Flutter engine or Android build is required.
import 'package:tide_bot/chat_content.dart';
import 'package:tide_bot/chat_request_context.dart';

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void main() {
  for (final role in ['user', 'assistant']) {
    final original = <String, dynamic>{
      'role': role,
      'content': '我今天加班。他说：“我明天休息”。',
      'id': 'message-1',
    };
    final marked = messageWithSpeaker(original);
    final body = marked['content'] as String;
    check(marked['role'] == role, 'API role must be preserved');
    check(marked['id'] == original['id'], 'Window identity must be preserved');
    check(body.endsWith(original['content'] as String), 'Keep original words');
    final marker = role == 'user' ? '[说话人:对方]' : '[说话人:你]';
    check(body == '$marker\n${original['content']}',
        'Use only a compact speaker marker before the original content');
    check(original['content'] == '我今天加班。他说：“我明天休息”。',
        'Do not modify stored messages');
  }

  for (final mediaType in ['image_url', 'input_audio']) {
    final media = <String, dynamic>{
      mediaType: {'data': 'unchanged'}
    };
    final parts = <Map<String, dynamic>>[
      {'type': 'text', 'text': '我发来的附件'},
      {'type': mediaType, ...media},
    ];
    final marked = messageWithSpeaker({'role': 'user', 'content': parts});
    final result = marked['content'] as List;
    check(result.length == 3, 'Add one text marker to multimodal content');
    check(result.first['type'] == 'text', 'Marker must be a text part');
    check(result.first['text'] == '[说话人:对方]', 'Use compact media marker');
    check(identical(result.last, parts.last), 'Preserve media payload');
    check(parts.length == 2, 'Do not mutate original multimodal list');
  }

  final cleaned =
      stripChatMetadata('[说话人：对方；普通原话的第一人称指对方]\n[说话人：你；普通原话的第一人称指你]\n正文');
  check(cleaned == '\n\n正文',
      'Remove internal speaker markers from visible replies');
  check(stripChatMetadata('[说话人:对方]\n[说话人:你]\n正文') == '\n\n正文',
      'Remove compact speaker markers');
  for (final marker in ['[说话人:对方]', '[说话人:你]']) {
    for (var end = 1; end < marker.length; end++) {
      check(stripChatMetadata('正文${marker.substring(0, end)}') == '正文',
          'Hide incomplete speaker markers while streaming');
    }
  }
  for (final role in ['system', 'tool']) {
    final source = <String, dynamic>{
      'role': role,
      'content': 'internal context'
    };
    check(messageWithSpeaker(source)['content'] == source['content'],
        'Do not attribute system instructions or tool results to a person');
  }
  check(
      messageWithSpeaker({'role': 'assistant', 'content': null})['content'] ==
          null,
      'Do not invent content for tool-only assistant messages');

  const stamp = 1700000000000;
  const text = '我今天加班';
  final history = <String, dynamic>{'role': 'user', 'content': text};
  history['content'] = messageTimeContext(history['content'] as String, stamp);
  final markedHistory = messageWithSpeaker(history);
  final current = messageWithSpeaker({
    'role': 'user',
    'content': messageTimeContext(text, stamp),
  });
  // The metadata order must be identical when a current turn becomes history.
  check(markedHistory['content'] == current['content'],
      'Preserve the reusable request prefix across consecutive turns');
  print('Speaker context checks passed.');
}
