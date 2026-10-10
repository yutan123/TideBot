import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/cognition_review.dart';

void main() {
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
    expect(prompt, contains('小潮'));
    expect(prompt, contains('温柔简洁'));
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
