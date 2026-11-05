import 'dart:convert';
import 'memory_prompt_policy.dart';

const cognitionCategories = ['角色眼中的你', '角色的自我认知', '关系'];

bool isCognitionReviewDue(String? status,
    {String? retryAt, required DateTime now}) {
  if (status == 'done') return false;
  final retry = int.tryParse(retryAt ?? '') ?? 0;
  return now.millisecondsSinceEpoch >= retry;
}

Map<String, String> parseCognitionReviewResult(Map<String, dynamic> result) {
  if (result['success'] != true || result['silent'] == true) {
    throw StateError(result['error']?.toString() ?? '认知复核没有真实回复');
  }
  final reply = result['reply'];
  if (reply is! String || reply.trim().isEmpty) {
    throw const FormatException('认知复核回复为空');
  }
  return parseCognitionReview(reply);
}

String cognitionReviewPrompt({
  required Map<String, dynamic> bot,
  required List<Map<String, dynamic>> memories,
  required DateTime now,
}) {
  final current = <String, String>{};
  for (final row in memories) {
    final category = row['category']?.toString() ?? '';
    if (cognitionCategories.contains(category)) {
      current.putIfAbsent(category, () => row['content']?.toString() ?? '');
    }
  }
  final recent = memories
      .where((row) =>
          !cognitionCategories.contains(row['category']) &&
          row['category'] != '角色档案')
      .take(8)
      .toList();
  return '【任务】内部认知复核，只判断三个认知类别是否有新的稳定认识；禁止聊天、问候或调用工具。\n'
      '$memoryCategoryPolicy\n'
      '【依据】结合对话、你的资料与已有认知；禁止编造经历、擅自推进关系或照搬人设。'
      '事件只能作为依据，禁止搬入画像；没有新认识时 modify 必须为 false，空白也不强行填充。\n'
      '【更新】保留旧内容中仍有效的信息，仅修正或补充有依据的认识，提交完整新版。\n'
      '仅输出严格 JSON：{"角色眼中的你":{"modify":false},"角色的自我认知":{"modify":false},"关系":{"modify":false}}。'
      '需要修改的项必须填写 {"modify":true,"content":"完整新内容"}。\n'
      '复核时间：${now.toIso8601String()}\n'
      '当前三项认知：${jsonEncode(current)}\n最近8条世界书条目：${jsonEncode(recent.map((r) => {
            'category': r['category'],
            'title': r['title'],
            'content': r['content'],
            'timestamp': r['timestamp']
          }).toList())}';
}

Map<String, String> parseCognitionReview(String response) {
  var text = response.trim();
  if (text.startsWith('```')) {
    text = text
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
  }
  final value = jsonDecode(text);
  if (value is! Map ||
      value.keys.any((key) => !cognitionCategories.contains(key))) {
    throw const FormatException('认知复核必须只包含三个指定类别');
  }
  final updates = <String, String>{};
  for (final category in cognitionCategories) {
    final decision = value[category];
    if (decision is! Map || decision['modify'] is! bool) {
      throw FormatException('$category 缺少明确的 modify 布尔值');
    }
    if (decision['modify'] == true) {
      final content = decision['content'];
      if (content is! String || content.trim().isEmpty) {
        throw FormatException('$category 修改内容不能为空');
      }
      updates[category] = content.trim();
    }
  }
  return updates;
}
