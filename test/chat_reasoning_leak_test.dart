import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_content.dart';
import 'package:tide_bot/chat_message_display.dart';

const leakedReply =
    '''Given the time (around 3:28 AM) and the established sleep schedule, the appropriate response aligns with the persona's resting state. The user's query ("睡着了吗") indicates a casual, friendly interaction. Considering the context, a gentle and brief reply reflecting the character's sleep would be suitable.

```text
<inner_thought>困死了……大半夜又被震醒。</inner_thought> 没呢。
```
''';

void main() {
  test('old assistant leaks are hidden on reload without rewriting stored rows',
      () {
    final row = <String, dynamic>{
      'id': 'old',
      'role': 'assistant',
      'type': 'text',
      'timestamp': 1000,
      'content': leakedReply,
    };
    final rows = normalizeChatMessages([row]);
    expect(rows.where((m) => m['type'] == 'text').single['content'], '没呢。');
    expect(rows.where((m) => m['type'] == 'inner_thought').single['content'],
        '困死了……大半夜又被震醒。');
    expect(row['content'], leakedReply);
    final user = {...row, 'id': 'user', 'role': 'user'};
    expect(normalizeChatMessages([user]).single['content'], leakedReply);
  });
  test('extracts screenshot reply and keeps only character thought separately',
      () {
    final parsed = parseChatReply(leakedReply);
    expect(parsed.text, '没呢。');
    expect(parsed.innerThought, '困死了……大半夜又被震醒。');
  });

  test('no leaked prefix or fragmented tag reaches the streaming callback', () {
    for (final size in [1, 2, 5, 17, leakedReply.length]) {
      final stream = ChatReplyStream();
      final visible = StringBuffer();
      for (var i = 0; i < leakedReply.length; i += size) {
        visible.write(stream.add(
            leakedReply.substring(i, (i + size).clamp(0, leakedReply.length))));
        expect(visible.toString(), '', reason: 'chunk size $size at $i');
      }
      visible.write(stream.finish());
      expect(visible.toString(), '没呢。');
      expect(stream.content.innerThought, '困死了……大半夜又被震醒。');
    }
  });

  test('mood headers and preceding thoughts cannot expose a planning prefix',
      () {
    for (final raw in [
      '[心情:平静]\n$leakedReply',
      '<inner_thought>好困。</inner_thought>Given the context, the appropriate response should be brief.\nFinal answer: 没呢。',
    ]) {
      final stream = ChatReplyStream();
      final out = StringBuffer();
      for (final rune in raw.runes) {
        out.write(stream.add(String.fromCharCode(rune)));
        expect('没呢。'.startsWith(out.toString()), isTrue);
      }
      out.write(stream.finish());
      expect(out.toString(), '没呢。');
    }
    expect(cleanChatContent('<tool_call>{"name":"set_emotion"}</tool_call>你好'),
        '你好');
  });

  test('streams an ordinary response without waiting for completion', () {
    final stream = ChatReplyStream();
    expect(stream.add('好'), '好');
    expect(stream.add('呀，'), '呀，');
    expect(stream.add('明天见。'), '明天见。');
    expect(stream.finish(), '');
  });

  test('split thought tags and reasoning tags never flash onscreen', () {
    for (final tag in ['inner_thought', 'think', 'analysis', 'reasoning']) {
      final raw = '<$tag>private</$tag>你好';
      final stream = ChatReplyStream();
      final visible = StringBuffer();
      for (final rune in raw.runes) {
        visible.write(stream.add(String.fromCharCode(rune)));
        expect('你好'.startsWith(visible.toString()), isTrue);
      }
      visible.write(stream.finish());
      expect(visible.toString(), '你好');
      expect(stream.content.innerThought,
          tag == 'inner_thought' ? 'private' : null);
    }
  });

  test('unfinished thoughts cannot affect a different response or stream', () {
    expect(cleanChatContent('<inner_thought>未结束'), '');
    expect(cleanChatContent('你好。'), '你好。');
    final a = ChatReplyStream();
    final b = ChatReplyStream();
    expect(a.add('<inner_thought>困'), '');
    expect(b.add('你好'), '你好');
    expect(a.add('了</inner_thought>晚安'), '晚安');
    expect(b.add('呀'), '呀');
  });

  test('requires a final boundary and never falls back to analysis alone', () {
    expect(
        cleanChatContent(
            'Given the context, the appropriate response should be brief.'),
        '');
    expect(
        cleanChatContent(
            'I need to follow the system instructions and craft a reply.'),
        '');
    expect(cleanChatContent('我需要分析用户的消息，考虑角色应该如何回复。'), '');
    expect(
        cleanChatContent(
            'Given the context, the appropriate response should be brief.\nFinal answer: Hello!'),
        'Hello!');
    expect(cleanChatContent('<think>model reasoning</think>Hi!'), 'Hi!');
  });

  test('keeps English conversations, translations, code and JSON intact', () {
    for (final text in [
      'I need to rest. Let us talk tomorrow.',
      'Given the weather, we should stay home.',
      'Let me know how you feel.',
      'The user interface needs a new button.',
      '我需要休息一下，明天再聊。',
      '这段英文的意思是：Given the time, the appropriate response should be brief.',
      '```dart\nfinal tag = "<inner_thought>example</inner_thought>";\n```',
      '{"entry":"a normal JSON example"}',
    ]) {
      expect(cleanChatContent(text), text);
      final stream = ChatReplyStream();
      final out = StringBuffer();
      for (final rune in text.runes) {
        out.write(stream.add(String.fromCharCode(rune)));
      }
      out.write(stream.finish());
      expect(out.toString(), text);
    }
  });
}
