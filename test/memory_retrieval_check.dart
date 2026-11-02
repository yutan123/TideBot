import 'dart:convert';
import 'package:tide_bot/memory_retrieval_policy.dart';
import 'package:tide_bot/memory_prompt_policy.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Map<String, dynamic> memory(String id, String content,
        {int priority = 3, String category = '记忆'}) =>
    {
      'id': id,
      'title': '',
      'content': content,
      'importance': priority,
      'category': category,
      'timestamp': int.tryParse(id) ?? 0,
    };

void main() {
  final rows = [
    memory('profile', '用户画像', category: '角色眼中的你'),
    for (var i = 20; i > 0; i--) memory('$i', '用户在第$i天去了海边')
  ];
  final recent = recentOrdinaryMemories(rows);
  check(recent.map((r) => r['id']).join(',') == '20,19,18,17,16',
      'recent must be the latest five ordinary rows');
  final matches = rankMemoryMatches(rows, '海边', exclude: recent);
  check(matches.length == 5, 'at most five matches');
  check(matches.every((r) => !recent.any((m) => m['id'] == r['id'])),
      'groups must not overlap');
  check(matches.every(ordinaryMemory), 'profiles stay separate');
  final reference = recentMemoryReference(rows);
  final payload =
      jsonDecode(reference.substring(reference.indexOf('\n') + 1)) as List;
  check(payload.length == 5 && payload.first['id'] == '20',
      'prompt default budget is five');

  final ranked = rankMemoryMatches([
    memory('low', '花生过敏', priority: 1),
    memory('high', '花生过敏，需要注意饮食', priority: 5),
    memory('unrelated', '喜欢看电影', priority: 5),
  ], '花生过敏');
  check(ranked.first['id'] == 'high',
      'priority affects equally relevant memories');
  check(ranked.length == 2, 'priority alone must not admit unrelated memories');
  final semantic = memory('cat', '对方养了一只叫团子的布偶猫。');
  final semanticResult = rankMemoryMatches([semantic], '我家那只小家伙叫什么',
      similarities: {memoryIdentity(semantic): 0.471});
  check(
      semanticResult.length == 1 && semanticResult.single['_keyword_hits'] == 0,
      'true semantic evidence can admit a lexical miss');
  check(rankMemoryMatches([semantic], '我家那只小家伙叫什么').isEmpty,
      'keyword fallback must not invent a semantic score');
  check(
      rankMemoryMatches([semantic], '天气',
          similarities: {memoryIdentity(semantic): 0.24}).isEmpty,
      'weak semantic similarity is rejected');

  final legacy = {
    ...memory('legacy', '对方养了一只叫团子的布偶猫。'),
    '_source': 'world_book_entries',
    'keys': '["宠物"]',
    'priority': 100
  };
  check(rankMemoryMatches([legacy, semantic], '宠物 布偶猫').length == 1,
      'same fact from two tables appears once');
  final gated = {
    ...legacy,
    'keys': '["red","blue"]',
    'key_mode': 'all',
    'secondary_keys': '["green"]'
  };
  check(!explicitMemoryMatch(gated, 'red blue'),
      'secondary keys gate explicit activation');
  check(!explicitMemoryMatch(gated, 'red green'),
      'all mode requires every primary key');
  check(explicitMemoryMatch(gated, 'red blue green'),
      'legacy key gates are preserved');
  check(
      !explicitMemoryMatch(
          {...legacy, 'keys': '["cat"]', 'match_whole_words': 1}, 'catalog'),
      'whole word matching');
  check(
      explicitMemoryMatch(
          {...legacy, 'keys': '["cat"]', 'match_whole_words': 1}, 'a cat!'),
      'whole word boundaries');
  check(
      !explicitMemoryMatch({...legacy, 'keys': '["["]', 'use_regex': 1}, 'cat'),
      'malformed legacy regex must not crash');
  check(memoryKeys('bad json').isEmpty, 'malformed keyword JSON');
  check(memoryImportance(legacy) == 5, 'legacy priority maps to importance');
  check((cosineMemory([1, 0], [1, 0]) - 1).abs() < 1e-8, 'cosine identical');
  check(cosineMemory([0, 0], [1, 0]) == 0 && cosineMemory([1], [1, 0]) == 0,
      'invalid vector handling');

  final history = [
    for (var i = 0; i < 12; i++)
      {'role': 'user', 'type': 'text', 'content': '历史$i', 'timestamp': i},
    {'role': 'tool', 'content': '内部协议', 'timestamp': 20},
    {
      'role': 'assistant',
      'content': '失败正文',
      'timestamp': 21,
      'send_status': 'failed'
    },
    {'role': 'user', 'content': '本轮问题', 'timestamp': 22},
    {
      'role': 'user',
      'content': '错误日志正文',
      'timestamp': 23,
      'error_log': 'network'
    },
  ];
  final query = memoryConversationQuery('本轮问题', history);
  check(
      query.contains('历史11') &&
          query.contains('历史7') &&
          !query.contains('历史6\n'),
      'matching uses the newest five messages');
  check(
      !query.contains('内部协议') &&
          !query.contains('失败正文') &&
          !query.contains('错误日志正文'),
      'internal and failed records excluded');
  check('本轮问题'.allMatches(query).length == 1, 'current message not duplicated');
  check(query == memoryConversationQuery('本轮问题', history.reversed.toList()),
      'timestamp order independent');
  print(
      'Memory retrieval policy checks passed: 5+5, deduplication, priority, hybrid admission, legacy keys, recent context.');
}
