import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_message_display.dart';

Map<String, dynamic> text(String id, String group, int time) => {
      'id': id,
      'role': 'assistant',
      'type': 'text',
      'content': '正文',
      'inner_thought': '想法',
      'reply_group_id': group,
      'timestamp': time
    };
Map<String, dynamic> thought(String id, String group, int time) => {
      'id': id,
      'role': 'assistant',
      'type': 'inner_thought',
      'content': '想法',
      'reply_group_id': group,
      'timestamp': time
    };
void main() {
  test('persisted thought and attached metadata render once before text', () {
    final rows = normalizeChatMessages(
        [thought('t', 'g', 1), text('m', 'g', 2), text('m', 'g', 2)]);
    expect(rows.map((m) => m['id']), ['t', 'm']);
  });
  test('legacy metadata gets a unique stable identity and survives refresh',
      () {
    final rows = normalizeChatMessages([text('m', 'g', 2)]);
    expect(rows.map((m) => m['id']), ['m_thought', 'm']);
    expect(normalizeChatMessages(rows).map((m) => m['id']), ['m_thought', 'm']);
    final updated = normalizeChatMessages([...rows, thought('t', 'g', 1)]);
    expect(updated.map((m) => m['id']), ['t', 'm']);
  });
  test('same content in different turns is not deduplicated', () {
    final rows = normalizeChatMessages([
      thought('t1', 'g1', 1),
      text('m1', 'g1', 2),
      thought('t2', 'g2', 3),
      text('m2', 'g2', 4)
    ]);
    expect(rows.where((m) => m['type'] == 'inner_thought'), hasLength(2));
  });
  test('legacy explicit row without reply group suppresses matching metadata',
      () {
    expect(normalizeChatMessages([thought('t', '', 1), text('m', '', 2)]),
        hasLength(2));
  });
}
