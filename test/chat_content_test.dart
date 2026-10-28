import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_content.dart';

void main() {
  test('media metadata is removed even when streamed one character at a time',
      () {
    for (final tag in [
      '[你发送了一个表情包,表情包类型：开心]',
      '[对方发送了一个表情包， 表情包类型:开心]',
      '[你发送了一个表情包,表情包类型开心]',
      '[图片#12]',
      '[本轮图片#1]',
      '[图片：海边]',
    ]) {
      expect(cleanChatContent('你好$tag呀'), '你好呀');
      final stream = ChatReplyStream();
      final visible = StringBuffer();
      for (final char in '你好$tag呀'.split('')) {
        visible.write(stream.add(char));
      }
      visible.write(stream.finish());
      expect(visible.toString(), '你好呀', reason: tag);
    }
    expect(cleanChatContent('看看[普通备注]和[1, 2]'), '看看[普通备注]和[1, 2]');
  });
  test('unfinished sticker metadata stays hidden when the response ends', () {
    for (final tag in [
      '[你发送了一个表情包,表情包类型',
      '[你发送了一个表情包，表情包类型',
      '[你发送了一个表情包,表情包类型:',
      '[你发送了一个表情包,表情包类型：开心',
    ]) {
      expect(cleanChatContent(tag), isEmpty);
      expect(cleanChatContent('你好$tag'), '你好');
      for (final prefix in ['', '你好']) {
        final stream = ChatReplyStream();
        final visible = StringBuffer();
        for (final char in '$prefix$tag'.split('')) {
          visible.write(stream.add(char));
        }
        visible.write(stream.finish());
        expect(visible.toString(), prefix, reason: tag);
        expect(stream.content.text, prefix, reason: tag);
      }
    }
  });
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
