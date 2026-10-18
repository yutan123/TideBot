import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/ai_request_task.dart';
import 'package:tide_bot/diary_output.dart';

void main() {
  test('task policies keep appointments history and isolate content generators',
      () {
    expect(AIRequestTask.lifeSchedule.needsHistory, isTrue);
    expect(AIRequestTask.lifeSchedule.needsWorldBook, isTrue);
    expect(AIRequestTask.cognitionReview.needsHistory, isTrue);
    for (final task in [
      AIRequestTask.dailyQuote,
      AIRequestTask.feedComment,
      AIRequestTask.callSummary,
      AIRequestTask.memoryReview,
      AIRequestTask.diary
    ]) {
      expect(task.needsHistory, isFalse, reason: task.name);
    }
    for (final task in AIRequestTask.values.where((t) => t.internal)) {
      final prompt =
          internalTaskSystemPrompt(task, {'name': '潮', 'prompt': '自然简短'});
      expect(prompt, isNot(contains('必须调用 save_memory')));
      expect(prompt, isNot(contains('本轮必须调用一次 send_sticker')));
      expect(prompt, isNot(contains('每轮面向对方的文字回复必须先输出')));
    }
    expect(internalTaskSystemPrompt(AIRequestTask.lifeSchedule, {}),
        contains('相对日期'));
  });

  test(
      'newest window preserves chronological roles, timestamps and newest message',
      () {
    final rows = List.generate(
        100,
        (i) => <String, dynamic>{
              'id': 'm${100 - i}',
              'role': i.isEven ? 'user' : 'assistant',
              'type': 'text',
              'timestamp': 1000000 - i,
              'content': '消息${100 - i}',
            });
    final selected = recentTaskMessages([
      {
        'id': 'thought',
        'role': 'assistant',
        'type': 'inner_thought',
        'content': '不作为事实'
      },
      {
        'id': 'failed',
        'role': 'user',
        'type': 'text',
        'content': '未发送',
        'error_code': 'network'
      },
      {'id': 'system', 'role': 'system', 'type': 'text', 'content': '内部指令'},
      ...rows,
    ], limit: 20);
    expect(selected.length, 20);
    expect(selected.first['id'], 'm81');
    expect(selected.last['id'], 'm100');
    final transcript = jsonDecode(taskTranscript(selected)) as List;
    expect(transcript.last['role'], 'user');
    expect(transcript.last['timestamp'], 1000000);
    expect(transcript.last['local_time'], isNotNull);
    expect(transcript.any((r) => r['id'] == 'm1'), isFalse);
  });

  test(
      'structured tasks reject prose and preserve date JSON without chat cleaning',
      () {
    const json = '{"timeline":[{"time":"08:00","activity":"见面"}]}';
    expect(validateInternalTaskOutput(AIRequestTask.lifeSchedule, json), json);
    expect(
        () => validateInternalTaskOutput(
            AIRequestTask.lifeSchedule, '我来安排一下。$json'),
        throwsFormatException);
    expect(
        () => validateInternalTaskOutput(AIRequestTask.cognitionReview,
            '<inner_thought>想法</inner_thought>{}'),
        throwsFormatException);
    expect(
        () => validateInternalTaskOutput(AIRequestTask.feedPost, '正文',
            structuredPost: true),
        throwsFormatException);
  });

  test('memory plan validates all actions and ids before saving any change',
      () {
    final existing = <Map<String, dynamic>>[
      {'id': 'known', 'category': '记忆'}
    ];
    expect(validateMemoryReview({'needUpdate': false, 'actions': []}, existing),
        isEmpty);
    expect(
        validateMemoryReview({
          'needUpdate': true,
          'actions': [
            {'type': 'delete', 'id': 'known'}
          ]
        }, existing)
            .single['id'],
        'known');
    for (final plan in [
      {
        'needUpdate': true,
        'actions': [
          {'type': 'delete', 'id': 'other'}
        ]
      },
      {
        'needUpdate': false,
        'actions': [
          {'type': 'delete', 'id': 'known'}
        ]
      },
      {
        'needUpdate': true,
        'actions': [
          {'type': 'create', 'title': '事实', 'content': '内容', 'keys': []}
        ]
      },
      {
        'needUpdate': true,
        'actions': [
          {
            'type': 'update',
            'id': 'known',
            'title': '事实',
            'content': '内容',
            'keys': ['词'],
            'priority': 101
          }
        ]
      },
    ]) {
      expect(() => validateMemoryReview(plan, existing), throwsFormatException);
    }
  });

  test('memory writes use the real memories columns', () {
    final values = memoryReviewValues({
      'title': '约定',
      'content': '明天见面',
      'keys': ['见面'],
      'priority': 90
    }, 123);
    expect(values.keys.toSet(),
        {'title', 'content', 'keys_json', 'importance', 'updated_at'});
    expect(jsonDecode(values['keys_json'] as String), ['见面']);
    expect(values['importance'], 5);
    expect(values['updated_at'], 123);
  });

  test('request transcripts cannot be saved as diary entries', () {
    const leak = '今天聊了天。{"role":"user","content":"请分析这段对话，判断是否需要更新世界书"}';
    expect(containsInternalTaskLeak(leak), isTrue);
    expect(parseDiaryResponse(jsonEncode({'entry': leak})), isNull);
    expect(parseDiaryResponse(jsonEncode({'entry': '今天聊了背单词，我很开心。'})),
        '今天聊了背单词，我很开心。');
  });
}
