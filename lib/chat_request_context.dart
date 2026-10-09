/// Maintains a stable history start until the full budget is reached.
/// The caller persists [startId]; loading full database history must not restore
/// messages discarded by a previous rollover.
({int removed, int tokens, String? startId}) rollStableHistory(
  List<Map<String, dynamic>> messages, {
  required int budget,
  required int Function(String) countTokens,
  String? startId,
}) {
  var removed = 0;
  if (startId != null && startId.isNotEmpty) {
    final index = messages.indexWhere((m) => m['id'] == startId);
    if (index > 0) {
      messages.removeRange(0, index);
      removed += index;
    }
  }
  final sizes =
      messages.map((m) => countTokens(m['content']?.toString() ?? '')).toList();
  var tokens = sizes.fold<int>(0, (sum, size) => sum + size);
  var roll = 0;
  if (tokens >= budget) {
    while (tokens > budget ~/ 2 && roll < sizes.length - 1) {
      tokens -= sizes[roll++];
    }
  }
  if (roll > 0) messages.removeRange(0, roll);
  return (
    removed: removed + roll,
    tokens: tokens,
    startId: messages.isEmpty ? null : messages.first['id']?.toString(),
  );
}

String stickerModelContext({required String role, required String type}) {
  final actor = role == 'assistant' ? '你' : '对方';
  final label = type.trim().isEmpty ? '未分类' : type.trim();
  return '[$actor发送了一个表情包，表情包类型：$label]';
}

int? cachedPromptTokens(Map usage) {
  final details = usage['prompt_tokens_details'];
  final value = (details is Map ? details['cached_tokens'] : null) ??
      usage['cached_tokens'] ??
      usage['prompt_cache_hit_tokens'] ??
      usage['cache_read_input_tokens'];
  return value is num ? value.toInt() : null;
}
