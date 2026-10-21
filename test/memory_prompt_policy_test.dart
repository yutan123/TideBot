import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/memory_prompt_policy.dart';
import 'package:tide_bot/cognition_review.dart';

void main() {
  test('recent reference includes IDs and excludes cognition before limiting',
      () {
    final reference = recentMemoryReference([
      {'id': 'profile', 'category': '角色眼中的你', 'content': '画像'},
      {'id': 'event', 'category': '记忆', 'content': '同一事件'},
      {'id': 'other', 'category': '记忆', 'content': '其他事件'},
    ], limit: 1);
    expect(reference, contains('event'));
    expect(reference, isNot(contains('profile')));
    expect(reference, isNot(contains('other')));
  });
  test('cognition review preserves profiles and rejects event summaries', () {
    final prompt = cognitionReviewPrompt(bot: {}, memories: [
      {'category': '角色眼中的你', 'content': '耐心且认真'},
    ], now: DateTime(2026));
    expect(prompt, contains(memoryCategoryPolicy));
    expect(prompt, contains('耐心且认真'));
    expect(prompt, contains('保留旧内容中仍有效的信息'));
    expect(prompt, contains('modify 必须为 false'));
    expect(memoryDeduplicationPolicy, contains('同一件事'));
    expect(memoryDeduplicationPolicy, contains('没有新增事实'));
  });
}
