/// Proactive turns retain the normal persona and conversation history.
const proactiveContactInstructions =
    '【主动联系】本轮由应用触发，用户没有发来新消息。末尾标有“应用触发的主动开口任务”的 user 消息是本轮内部任务，不属于用户聊天原话。沿用平时的人设、说话方式和分段规则。'
    '结合当前真实时间和完整聊天记录，选择此刻值得说的内容。已经回答过的问题不再补答，过时的问候不沿用旧时段。'
    '可以延续仍有效的话题、关心约定的进展、提出具体而真心好奇的问题，或分享有日程、生活状态、日记或历史依据的自己的近况和感受。'
    '这些是可选方向，不必逐项执行；不要每次都问“在吗”“你呢”，不要编造已经发生的经历，也不要把计划说成已完成。'
    '用户没有回应时，不追问同一个问题、不催回复、不责怪；没有自然且不重复的内容就调用 choose_silence，不输出正文。'
    '任务说明、时间和计数是内部信息，不向用户复述，也不要冒充用户说话。';

/// Fresh runtime facts supplement, rather than replace, the transcript.
/// This request-only task must never be persisted as a real user message.
String buildProactiveContactTurn({
  required DateTime now,
  required int unansweredCount,
  required String trigger,
}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = now.toLocal();
  final offset = local.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  final zone =
      'UTC${offset.isNegative ? '-' : '+'}'
      '${two(minutes ~/ 60)}:${two(minutes % 60)}';
  final clock =
      '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  final count = unansweredCount < 0 ? 0 : unansweredCount;
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return '【应用触发的主动开口任务；不是用户发言】\n'
      '当前本地时间：$clock（$zone，星期${weekdays[local.weekday - 1]}）。\n'
      '之前连续主动联系、用户尚未回应的次数：$count 次。\n'
      '本轮触发信息：\n$trigger\n'
      '请回看完整对话中双方最近实际说过的话及其时间，确认哪些内容已经回应、哪些话题仍适合现在。'
      '选择一个符合当前情境的主动开口：自然跟进、具体的好奇提问，或有依据的自身近况分享。'
      '${count > 0 ? '此前主动联系尚未收到回应，请更克制，不重复上次的问题或问候，也不暗示对方欠你回复。' : ''}'
      '生成可直接发给对方的自然消息；如果此刻没有值得说的新内容，调用 choose_silence。';
}
