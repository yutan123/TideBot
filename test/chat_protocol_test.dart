import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_protocol.dart';

void main() {
  group('chatListPreview', () {
    test('shared_post always shows a fixed preview', () {
      expect(
        chatListPreview(
          type: 'shared_post',
          rawContent: '{"author":"alice","content":"hello"}',
        ),
        '[动态]',
      );
    });

    test('falls back to type labels when content is empty', () {
      expect(chatListPreview(type: 'image', rawContent: ''), '[图片]');
      expect(chatListPreview(type: 'audio', rawContent: ''), '[语音]');
      expect(chatListPreview(type: 'call_summary', rawContent: ''), '[通话]');
      expect(chatListPreview(type: 'sticker', rawContent: ''), '[表情包]');
      expect(chatListPreview(type: 'emoji', rawContent: ''), '[表情]');
    });

    test('uses trimmed text for ordinary messages', () {
      expect(
        chatListPreview(type: 'text', rawContent: '  hello\nworld  '),
        'hello world',
      );
    });
  });

  group('shared post copy', () {
    test('uses deleted copy for both UI and model context', () {
      expect(sharedPostDeletedUserCopy, '原动态已删除');
      expect(
        sharedPostModelContext(deleted: true, author: 'alice', content: 'x'),
        sharedPostDeletedModelCopy,
      );
    });

    test('keeps live post context when the original still exists', () {
      expect(
        sharedPostModelContext(
          deleted: false,
          author: 'alice',
          content: 'hello',
          time: '刚刚',
          hasImage: true,
        ),
        contains('hello'),
      );
    });
  });

  group('image placeholders', () {
    test('formats numbered placeholders', () {
      expect(formatImagePlaceholder(1), '[图片#1]');
      expect(formatImagePlaceholder(2, caption: 'cat'), '[图片#2]\ncat');
    });

    test('parses image numbers from tags and raw values', () {
      expect(parseImageNumber(3), 3);
      expect(parseImageNumber('图片#4'), 4);
      expect(parseImageNumber('0'), isNull);
      expect(parseImageNumber(''), isNull);
    });
  });
}
