import 'package:tide_bot/ai_request_task.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/cognition_review.dart';

void main() {
  test('only completed reviews suppress catch-up, including legacy attempts',
      () {
    final now = DateTime(2026, 1, 2, 12);
    for (final state in [null, 'attempted', 'pending']) {
      expect(isCognitionReviewDue(state, now: now), isTrue);
    }
    expect(isCognitionReviewDue('done', now: now), isFalse);
    final retry = now.add(const Duration(minutes: 5));
    expect(
        isCognitionReviewDue('pending',
            now: now, retryAt: '${retry.millisecondsSinceEpoch}'),
        isFalse);
    expect(
        isCognitionReviewDue('pending',
            now: retry, retryAt: '${retry.millisecondsSinceEpoch}'),
        isTrue);
  });

  test('review requires a real reply with all three decisions', () {
    final reply = jsonEncode({
      for (final category in cognitionCategories) category: {'modify': false}
    });
    expect(
        parseCognitionReviewResult({'success': true, 'reply': reply}), isEmpty);
    for (final result in <Map<String, dynamic>>[
      {'success': false, 'reply': reply},
      {'success': true, 'silent': true, 'reply': reply},
      {'success': true, 'reply': ''},
      {'success': true},
      {'success': true, 'reply': '{}'},
    ]) {
      expect(() => parseCognitionReviewResult(result),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())));
    }
  });
  test('cognition review prompt includes persona and eight world entries', () {
    final rows = [
      {'category': '角色眼中的你', 'content': '当前认知'},
      ...List.generate(
          8, (i) => {'category': '记忆', 'title': '条目$i', 'content': '内容$i'}),
      {'category': '记忆', 'title': '第九条', 'content': '不应进入'},
    ];
    final prompt = cognitionReviewPrompt(
      bot: {'name': '小潮', 'prompt': '温柔简洁', 'desc': '海边机器人'},
      memories: rows,
      now: DateTime(2026, 1, 1),
    );
    final system = internalTaskSystemPrompt(
        AIRequestTask.cognitionReview, {'name': '小潮', 'prompt': '温柔简洁'});
    expect(system, contains('小潮'));
    expect(system, contains('温柔简洁'));
    expect(prompt, isNot(contains('温柔简洁')));
    expect(prompt, contains('条目0'));
    expect(prompt, isNot(contains('第九条')));
  });

  test('cognition review parser keeps only explicit modifications', () {
    final result = parseCognitionReview(jsonEncode({
      '角色眼中的你': {'modify': false},
      '角色的自我认知': {'modify': true, 'content': '我是一名摄影师'},
      '关系': {'modify': false},
    }));
    expect(result, {'角色的自我认知': '我是一名摄影师'});
  });

  test('cognition review parser rejects invalid decisions', () {
    expect(
        () => parseCognitionReview(jsonEncode({
              '角色眼中的你': {'modify': true},
              '角色的自我认知': {'modify': false},
              '关系': {'modify': false},
            })),
        throwsFormatException);
  });
}
