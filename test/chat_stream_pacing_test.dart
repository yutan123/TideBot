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

  test('completed provider text still follows the client pace', () async {
    final watch = Stopwatch()..start();
    final visible = <String>[];
    await for (final text in chatStreamText('你👨‍👩‍👧‍👦好', 100)) {
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(75));
      visible.add(text);
      watch.reset();
    }
    expect(visible, ['你', '你👨‍👩‍👧‍👦', '你👨‍👩‍👧‍👦好']);
  });

  test('segments drain in order without flushing the next segment', () async {
    final visible = <String>[];
    for (final segment in ['甲。', '乙！']) {
      await for (final text in chatStreamText(segment, 100)) {
        visible.add(text);
      }
    }
    expect(visible, ['甲', '甲。', '乙', '乙！']);
  });
}
