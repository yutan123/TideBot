import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_request_context.dart';

void main() {
  test('persisted window survives full history reload across consecutive turns',
      () {
    final database = List.generate(
        10,
        (i) => <String, dynamic>{
              'id': '$i',
              'role': 'user',
              'content': 'a' * 10,
            });
    final first = database.map((m) => Map<String, dynamic>.from(m)).toList();
    final rolled =
        rollStableHistory(first, budget: 100, countTokens: (s) => s.length);
    expect(rolled.startId, '5');
    expect(rolled.tokens, 50);
    for (var turn = 10; turn < 14; turn++) {
      database.add({'id': '$turn', 'role': 'user', 'content': 'a' * 10});
      final reloaded =
          database.map((m) => Map<String, dynamic>.from(m)).toList();
      final next = rollStableHistory(reloaded,
          budget: 100, countTokens: (s) => s.length, startId: rolled.startId);
      expect(next.startId, '5');
      expect(reloaded.take(first.length), first);
    }
  });
  test('rollover preserves oversized latest message and handles deleted cursor',
      () {
    final history = <Map<String, dynamic>>[
      {'id': 'a', 'content': 'x'},
      {'id': 'b', 'content': 'y' * 120},
    ];
    final result = rollStableHistory(history,
        budget: 100, countTokens: (s) => s.length, startId: 'deleted');
    expect(result.startId, 'b');
    expect(result.tokens, 120);
    expect(history.length, 1);
    expect(
        rollStableHistory([], budget: 100, countTokens: (s) => s.length)
            .startId,
        isNull);
  });
  test('sticker descriptions identify both actors and always include type', () {
    expect(
        stickerModelContext(role: 'user', type: '开心'), '[对方发送了一个表情包，表情包类型：开心]');
    expect(stickerModelContext(role: 'assistant', type: ' 害羞 '),
        '[你发送了一个表情包，表情包类型：害羞]');
    expect(stickerModelContext(role: 'assistant', type: ''),
        '[你发送了一个表情包，表情包类型：未分类]');
  });
  test(
      'cache usage supports provider formats and does not treat missing as zero',
      () {
    expect(
        cachedPromptTokens({
          'prompt_tokens_details': {'cached_tokens': 12000}
        }),
        12000);
    expect(
        cachedPromptTokens(
            {'prompt_tokens_details': {}, 'prompt_cache_hit_tokens': 2000}),
        2000);
    expect(cachedPromptTokens({'cache_read_input_tokens': 1000}), 1000);
    expect(cachedPromptTokens({'cached_tokens': 0}), 0);
    expect(cachedPromptTokens({}), isNull);
  });
}
