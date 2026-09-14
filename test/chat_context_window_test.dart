import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_context_window.dart';

void main() {
  Map<String, dynamic> message(int tokens) =>
      {'role': 'user', 'content': 'a' * (tokens * 4)};
  test('full budget then half, with growth between rollovers', () {
    var chat = List.generate(9, (_) => message(1000));
    expect(rollChatWindow(chat, 10000).removed, 0);
    chat.add(message(1000));
    final first = rollChatWindow(chat, 10000);
    expect(first, (removed: 5, tokens: 5000));
    chat = chat.skip(first.removed).toList()
      ..addAll(List.generate(4, (_) => message(1000)));
    expect(rollChatWindow(chat, 10000), (removed: 0, tokens: 9000));
    chat.add(message(1000));
    expect(rollChatWindow(chat, 10000), (removed: 5, tokens: 5000));
  });
  test('20000 budget retains 10000 and has no turn cap', () {
    expect(rollChatWindow(List.generate(200, (_) => message(100)), 20000),
        (removed: 100, tokens: 10000));
    expect(
        rollChatWindow(List.generate(80, (_) => message(100)), 20000).removed,
        0);
  });
  test('whole messages and oversized latest message are preserved', () {
    expect(rollChatWindow([message(6000), message(4500)], 10000),
        (removed: 1, tokens: 4500));
    expect(rollChatWindow([message(1000), message(11000)], 10000),
        (removed: 1, tokens: 11000));
    expect(rollChatWindow([], 10000), (removed: 0, tokens: 0));
  });
}
