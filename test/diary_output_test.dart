import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/diary_output.dart';

void main() {
  test('diary contract preserves character and separates chat requirements',
      () {
    final prompt = buildDiarySystemPrompt({
      'name': '伊伊',
      'desc': '喜欢散步',
      'prompt': '语气温柔',
    });
    expect(prompt, contains('伊伊'));
    expect(prompt, contains('喜欢散步'));
    expect(prompt, contains('语气温柔'));
    expect(prompt, contains('唯一字段 entry'));
    expect(prompt, contains('不调用工具、不回复用户'));
    expect(prompt, isNot(contains('必须先输出')));
  });

  test('reads final content without using provider reasoning', () {
    final raw = diaryResponseContent({
      'content': '{"entry":"今天的聊天让我很开心。"}',
      'reasoning_content': 'The diary task requirements are unclear.',
      'reasoning': '先分析规则。',
    });
    expect(parseDiaryResponse(raw), '今天的聊天让我很开心。');
    expect(diaryResponseContent({'reasoning_content': '只有推理'}), '');
    expect(diaryResponseContent(null), '');
  });

  test('reads text content parts and ignores reasoning parts', () {
    final raw = diaryResponseContent({
      'content': [
        {'type': 'reasoning', 'text': '日记任务规则很复杂'},
        {'type': 'text', 'text': '{"entry":'},
        {'type': 'text', 'text': '"听到他的近况，我很高兴。"}'},
      ],
    });
    expect(parseDiaryResponse(raw), '听到他的近况，我很高兴。');
  });

  test('only saves the structured diary after tagged reasoning', () {
    expect(
      parseDiaryResponse(
        '<think>分析心情标签要求。</think>\n'
        '<inner_thought>先看看该怎么写。</inner_thought>\n'
        '```json\n{"entry":"我们聊起了近况。"}\n```',
      ),
      '我们聊起了近况。',
    );
  });

  test('rejects screenshot preambles and unstructured task analysis', () {
    for (final text in [
      '我先看一下日记该怎么写，再按十五号实际发生的事记。',
      "The diary task's requirements about sentiment tags are unclear.",
      '日记任务的规则似乎很复杂。要先输出独白，然后换行写日记正文。',
      '<think>尚未完成的分析',
      '<inner_thought>只有独白</inner_thought>',
    ]) {
      expect(parseDiaryResponse(text), isNull, reason: text);
    }
  });

  test('extracts final entry after untagged analysis seen in provider logs',
      () {
    const entry = '中午刚躺下就被小泽发消息喊起来。\n\n下午换了衣服下楼慢跑了一圈。';
    final response = "Need to ensure the entry includes factual events and "
        "the character's feelings. October 16th, 2026.\n\n"
        '${jsonEncode({'entry': entry})}';
    expect(parseDiaryResponse(response), entry);
    expect(parseDiaryResponse('准备写日记。{"entry":"今天很开心。"}'), '今天很开心。');
    expect(
      parseDiaryResponse(
          '分析规则。\n```json\n${jsonEncode({'entry': entry})}\n```'),
      entry,
    );
  });
  test('handles braces, backslashes and escaped quotes in diary strings', () {
    const entry = '他说 "把 {entry} 和 [草稿] 留着"，我记下了 C:\\notes。';
    expect(parseDiaryResponse('说明。${jsonEncode({'entry': entry})}'), entry);
  });
  test('rejects ambiguous entries and nested or unfinished reasoning output',
      () {
    for (final text in [
      '{"entry":"第一篇"}\n{"entry":"第二篇"}',
      '<think>分析中 {"entry":"还不是最终答案"}',
      '<inner_thought>{"entry":"分析内容"}</inner_thought>',
      '{"wrapper":{"entry":"嵌套内容"}}',
      '分析。[{"entry":"列表内容"}]',
    ]) {
      expect(parseDiaryResponse(text), isNull, reason: text);
    }
  });
  test('rejects invalid schemas and empty content', () {
    for (final text in [
      '',
      '{}',
      '{"entry":"  "}',
      '{"entry":42}',
      '[{"entry":"今天很开心。"}]',
      '{"entry":"今天很开心。","analysis":"分析规则"}',
      '{"entry":"未完成',
    ]) {
      expect(parseDiaryResponse(text), isNull, reason: text);
    }
  });

  test('does not silently accept thought or mood tags inside the diary', () {
    for (final entry in [
      '<think>分析</think>今天很开心。',
      '<inner_thought>感受</inner_thought>今天很开心。',
      '<inner_thought>没有结束',
      '[心情:开心]\n今天很开心。',
    ]) {
      expect(parseDiaryResponse(jsonEncode({'entry': entry})), isNull);
    }
  });

  test('preserves ordinary feelings, multiline prose and quoted words', () {
    const entry = '他说“别着急”，我听完心里踏实了些。\n\n想起这段交谈，还是觉得温暖。';
    expect(parseDiaryResponse(jsonEncode({'entry': entry})), entry);
  });
}
