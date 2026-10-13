import 'dart:convert';

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
  return '这是每日凌晨的内部认知复核任务，不是与用户聊天，不要问候、发送消息或调用工具。'
      '请结合正常对话上下文、角色资料、当前认知和最近世界书条目，分别判断三个类别是否需要修改。'
      '允许全部保留，也允许只修改其中一项。没有新依据时保留；空白内容可依据已有事实初始化。'
      '不得编造用户经历、擅自推进关系或违背人设。修改时给出该项完整的新内容，而非增量。'
      '"角色眼中的你"：没有新增内容或需要修改的内容请不要修改。'
      '"角色的自我认知"（即"你认为的你"）：人格设定和说话方式只作参考，你可以用自己的理解描述你认为的自己的性格、身份、特点，不要照搬人格设定。没有新增内容或需要修改的内容请不要修改。'
      '仅输出严格 JSON：{"角色眼中的你":{"modify":false},"角色的自我认知":{"modify":false},"关系":{"modify":false}}。'
      '需要修改的项必须填写 {"modify":true,"content":"完整新内容"}。\n'
      '复核时间：${now.toIso8601String()}\n'
      '角色名字：${bot['name'] ?? ''}\n人设：${bot['desc'] ?? ''}\n说话方式与人设指令：${bot['prompt'] ?? ''}\n'
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
