import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_content.dart';

void main() {
  group('cleanChatContent', () {
    test('keeps ordinary content', () {
      expect(cleanChatContent('hello response: body'), 'hello response: body');
    });

    test('removes response prefixes only at the beginning', () {
      expect(cleanChatContent(' response: hello'), 'hello');
      expect(cleanChatContent('Response： hello'), 'hello');
      expect(cleanChatContent('data: response: hello'), 'hello');
      expect(cleanChatContent('event: response： hello'), 'hello');
    });

    test('keeps tool payload and handles empty content', () {
      expect(cleanChatContent('{"tool_calls":[]}'), '{"tool_calls":[]}');
      expect(cleanChatContent('  '), '');
    });
  });
}
