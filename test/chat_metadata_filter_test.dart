import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_content.dart';
import 'package:tide_bot/chat_request_context.dart';
import 'package:tide_bot/chat_message_display.dart';

void main() {
  test('removes complete metadata regardless of value or colon width', () {
    for (final tag in [
      '[你发送了一个表情包，表情包类型:开心]',
      '[你发送了一个表情包，表情包类型：任意新类型]',
      '[对方发送了一个表情包，表情包类型:未知]',
      '[发送时间:2026-10-22 12:00:00]',
      '[发送时间：任意内容]',
    ]) {
      expect(parseChatReply('前${tag}后').text, '前后');
      final stream = ChatReplyStream();
      var visible = '';
      for (final character in '前${tag}后'.split('')) {
        visible += stream.add(character);
        expect(visible, anyOf('前', '前后'));
      }
      visible += stream.finish();
      expect(visible, '前后');
    }
  });

  test('keeps ordinary brackets and hides incomplete metadata', () {
    expect(parseChatReply('你好[发送时间:尚未闭合').text, '你好');
    expect(parseChatReply('你好[你发送了一个表情包，表情包类型:').text, '你好');
    expect(parseChatReply('使用[普通标签]和[1, 2]').text, '使用[普通标签]和[1, 2]');
  });

  test('historical assistant labels are hidden without mutating rows', () {
    final row = {
      'id': 'a',
      'role': 'assistant',
      'type': 'text',
      'content': '[发送时间:任意]你好',
      'timestamp': 1
    };
    expect(normalizeChatMessages([row]).single['content'], '你好');
    expect(row['content'], '[发送时间:任意]你好');
  });

  test('time context uses message timestamp and explicit unknown fallback', () {
    final stamp = DateTime(2026, 10, 22, 9, 8, 7).millisecondsSinceEpoch;
    expect(messageTimeContext('你好', stamp), '[发送时间:2026-10-22 09:08:07]\n你好');
    expect(messageTimeContext('你好', null), '[发送时间:未知]\n你好');
  });
}
