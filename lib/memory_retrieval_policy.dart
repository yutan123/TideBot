import 'dart:convert';
import 'dart:math' as math;

const semanticMemoryThreshold = 0.45;
const profileMemoryCategories = ['角色眼中的你', '角色的自我认知', '关系', '角色档案'];
bool ordinaryMemory(Map<String, dynamic> row) =>
    !profileMemoryCategories.contains(row['category']);
String memoryIdentity(Map<String, dynamic> row) =>
    '${row['_source'] ?? 'memories'}:${row['id']}';
String memoryDocument(Map<String, dynamic> row) =>
    '${row['title'] ?? ''}\n${row['content'] ?? ''}';
String memoryFact(Map<String, dynamic> row) =>
    '${row['content'] ?? ''}'.replaceAll(RegExp(r'\s+'), '').toLowerCase();

List<String> memoryTokens(String text) {
  final tokens = <String>{};
  for (final match in RegExp(r'[a-zA-Z0-9_]+|[\u3400-\u9fff]+')
      .allMatches(text.toLowerCase())) {
    final word = match[0]!;
    if (word.length >= 2) tokens.add(word);
    if (RegExp(r'^[\u3400-\u9fff]+$').hasMatch(word)) {
      for (var i = 0; i < word.length - 1; i++) {
        tokens.add(word.substring(i, i + 2));
      }
    }
  }
  return tokens.toList();
}

List<String> memoryKeys(dynamic value) {
  try {
    final decoded = value is String ? jsonDecode(value) : value;
    return decoded is List
        ? decoded.whereType<String>().where((s) => s.trim().isNotEmpty).toList()
        : [];
  } catch (_) {
    return [];
  }
}

// Preserve legacy explicit keyword semantics, including secondary gates.
bool explicitMemoryMatch(Map<String, dynamic> row, String query) {
  final legacy = row['_source'] == 'world_book_entries';
  final keys = memoryKeys(legacy ? row['keys'] : row['keys_json']);
  if (keys.isEmpty) return false;
  final sensitive = legacy && row['case_sensitive'] == 1;
  bool matches(String key) {
    try {
      if (legacy && row['use_regex'] == 1) {
        return RegExp(key, caseSensitive: sensitive).hasMatch(query);
      }
      final needle = sensitive ? key : key.toLowerCase();
      final haystack = sensitive ? query : query.toLowerCase();
      if (legacy && row['match_whole_words'] == 1) {
        return RegExp(
                '(^|[^\\w\\u3400-\\u9fff])${RegExp.escape(needle)}(\$|[^\\w\\u3400-\\u9fff])')
            .hasMatch(haystack);
      }
      return haystack.contains(needle);
    } catch (_) {
      return false;
    }
  }

  final primary = legacy && row['key_mode'] == 'all'
      ? keys.every(matches)
      : keys.any(matches);
  final secondary = memoryKeys(row['secondary_keys']);
  return primary && (secondary.isEmpty || secondary.any(matches));
}

double cosineMemory(List<double> a, List<double> b) {
  if (a.isEmpty || a.length != b.length) return 0;
  double dot = 0, aa = 0, bb = 0;
  for (var i = 0; i < a.length; i++) {
    if (!a[i].isFinite || !b[i].isFinite) return 0;
    dot += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  return aa == 0 || bb == 0 ? 0 : dot / math.sqrt(aa * bb);
}

int memoryImportance(Map<String, dynamic> row) =>
    row['_source'] == 'world_book_entries'
        ? (((row['priority'] as num? ?? 50) / 20).ceil()).clamp(1, 5)
        : ((row['importance'] as num?)?.toInt() ?? 3).clamp(1, 5);

List<Map<String, dynamic>> rankMemoryMatches(
    List<Map<String, dynamic>> candidates, String query,
    {Map<String, double> similarities = const {},
    Iterable<Map<String, dynamic>> exclude = const [],
    int limit = 5}) {
  final tokens = memoryTokens(query);
  final seen = exclude.map(memoryFact).toSet();
  final excludedIds = exclude.map(memoryIdentity).toSet();
  final scored = <Map<String, dynamic>>[];
  for (final row in candidates) {
    if (!ordinaryMemory(row) || excludedIds.contains(memoryIdentity(row)))
      continue;
    final document = memoryDocument(row).toLowerCase();
    final hits = tokens.where(document.contains).length;
    final explicit = explicitMemoryMatch(row, query);
    final similarity = similarities[memoryIdentity(row)] ?? 0;
    // Priority never admits an unrelated memory on its own.
    if (hits == 0 && !explicit && similarity < semanticMemoryThreshold)
      continue;
    final lexical = tokens.isEmpty ? 0.0 : hits / tokens.length;
    final relevance = math.max(explicit ? 1.0 : lexical,
        similarity >= semanticMemoryThreshold ? similarity : 0.0);
    scored.add({
      ...row,
      '_score': relevance +
          (row['_source'] == 'world_book_entries'
              ? ((row['priority'] as num?) ?? 50).clamp(0, 100) * 0.00175
              : memoryImportance(row) * 0.035),
      '_similarity': similarity,
      '_keyword_hits': hits,
      '_explicit': explicit
    });
  }
  scored.sort((a, b) {
    final score = (b['_score'] as num).compareTo(a['_score'] as num);
    if (score != 0) return score;
    final priority = memoryImportance(b).compareTo(memoryImportance(a));
    if (priority != 0) return priority;
    final time = ((b['timestamp'] as num?) ?? 0)
        .compareTo((a['timestamp'] as num?) ?? 0);
    return time != 0 ? time : memoryIdentity(a).compareTo(memoryIdentity(b));
  });
  return scored.where((row) => seen.add(memoryFact(row))).take(limit).toList();
}

List<Map<String, dynamic>> recentOrdinaryMemories(
    List<Map<String, dynamic>> rows) {
  final seen = <String>{};
  return rows
      .where(ordinaryMemory)
      .where((m) => seen.add(memoryFact(m)))
      .take(5)
      .toList();
}

// Sort by timestamps when supplied; otherwise callers' chronological order is used.
String memoryConversationQuery(
    String current, List<Map<String, dynamic>> history) {
  final rows = history
      .where((m) =>
          const ['user', 'assistant'].contains(m['role']) &&
          const ['text', 'audio', 'image', 'video', 'shared_post']
              .contains(m['type'] ?? 'text') &&
          !const ['failed', 'sending'].contains(m['send_status']) &&
          (m['error_code']?.toString() ?? '').isEmpty &&
          (m['error_log']?.toString() ?? '').isEmpty &&
          m['content'] is String &&
          '${m['content']}'.trim().isNotEmpty)
      .toList();
  if (rows.every((m) => m['timestamp'] is num)) {
    rows.sort(
        (a, b) => (a['timestamp'] as num).compareTo(b['timestamp'] as num));
  }
  final values = rows.reversed
      .map((m) => '${m['content']}'.trim())
      .where((v) => v != current.trim())
      .take(5)
      .toList()
      .reversed;
  return [current.trim(), ...values].join('\n');
}
