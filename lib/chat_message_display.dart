import 'chat_content.dart';

/// Reconcile persisted thought rows with legacy thoughts attached to text rows.
/// A reply group owns one thought; identical thoughts in different turns survive.
List<Map<String, dynamic>> normalizeChatMessages(
    Iterable<Map<String, dynamic>> messages) {
  final byId = <String, Map<String, dynamic>>{};
  final input = messages.toList();
  final sourceIds = input
      .where((m) => m['type'] != 'inner_thought')
      .map((m) => m['id']?.toString())
      .toSet();
  for (final message in input) {
    final id = message['id']?.toString() ?? '';
    if (message['type'] == 'inner_thought' &&
        id.endsWith('_thought') &&
        sourceIds.contains(id.substring(0, id.length - 8))) continue;
    if (id.isNotEmpty) byId[id] = message;
  }
  final rows = byId.values.toList()
    ..sort((a, b) => ((a['timestamp'] as num?)?.toInt() ?? 0)
        .compareTo((b['timestamp'] as num?)?.toInt() ?? 0));
  final explicit = rows.where((m) => m['type'] == 'inner_thought').toList();
  final result = <Map<String, dynamic>>[];
  final thoughtGroups = <String>{};
  for (final original in rows) {
    var row = original;
    // Streaming text was parsed before entering the reveal queue. Preserve
    // both the empty placeholder and its identity for in-place frame updates.
    if (row['role'] == 'assistant' &&
        row['type'] == 'text' &&
        row['is_streaming'] != true) {
      final parsed = parseChatReply(row['content']?.toString() ?? '');
      if (parsed.text.isEmpty) continue;
      row = {
        ...row,
        'content': parsed.text,
        if ((row['inner_thought']?.toString().trim() ?? '').isEmpty &&
            parsed.innerThought != null)
          'inner_thought': parsed.innerThought,
      };
    }
    final group = row['reply_group_id']?.toString() ?? '';
    if (row['type'] == 'inner_thought') {
      if (group.isNotEmpty && !thoughtGroups.add(group)) continue;
      result.add(row);
      continue;
    }
    final thought = row['inner_thought']?.toString().trim() ?? '';
    if (row['role'] == 'assistant' &&
        row['type'] == 'text' &&
        thought.isNotEmpty) {
      final ownsExplicit = explicit.any((m) {
        if (group.isNotEmpty) return m['reply_group_id'] == group;
        final delta = ((row['timestamp'] as num?)?.toInt() ?? 0) -
            ((m['timestamp'] as num?)?.toInt() ?? 0);
        return m['content']?.toString().trim() == thought &&
            delta >= 0 &&
            delta <= 1000;
      });
      if (!ownsExplicit && (group.isEmpty || thoughtGroups.add(group))) {
        result.add({
          ...row,
          'id': '${row['id']}_thought',
          'type': 'inner_thought',
          'content': thought
        });
      }
    }
    result.add(row);
  }
  return result;
}
