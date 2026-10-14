import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_stream_pacing.dart';

void main() {
  test('chat speed remains readable throughout the settings range', () {
    expect(chatStreamInterval(1).inMilliseconds, 320);
    expect(chatStreamInterval(50).inMilliseconds, 201);
    expect(chatStreamInterval(100).inMilliseconds, 80);
  });

  test('large provider chunks are consumed one visible character at a time',
      () {
    var pending = '你好👨‍👩‍👧‍👦e\u0301！';
    final displayed = <String>[];
    while (pending.isNotEmpty) {
      final (character, remainder) = takeChatStreamCharacter(pending);
      displayed.add(character);
      pending = remainder;
    }
    expect(displayed, ['你', '好', '👨‍👩‍👧‍👦', 'e\u0301', '！']);
    expect(takeChatStreamCharacter(''), ('', ''));
  });
}
