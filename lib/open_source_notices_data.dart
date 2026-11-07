import 'dart:convert';

/// Resolves shared text references while keeping every component's own labels.
/// Inline documents are retained for the overview and upstream terms URLs.
List<Map<String, dynamic>> decodeOpenSourceNotices(String source) {
  final data = jsonDecode(source) as Map<String, dynamic>;
  if (data['schema'] != 1) {
    throw const FormatException('Unsupported notices schema');
  }
  final texts = data['texts'] as Map<String, dynamic>? ?? const {};
  return (data['entries'] as List).map((item) {
    final entry = Map<String, dynamic>.from(item as Map);
    entry['documents'] = (entry['documents'] as List).map((value) {
      final document = Map<String, dynamic>.from(value as Map);
      final text = document['text'] ?? texts[document['sha256']];
      if (text is! String) {
        throw const FormatException('Missing bundled license text');
      }
      document['text'] = text;
      return document;
    }).toList();
    return entry;
  }).toList();
}
