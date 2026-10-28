import 'dart:convert';

import 'package:http/http.dart' as http;

/// Official API: https://api-docs.deepseek.com/guides/search/
Future<List<Map<String, String>>> searchDeepSeek({
  required String query,
  required String apiKey,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final normalizedQuery = query.trim();
  if (normalizedQuery.isEmpty) return [];
  if (apiKey.trim().isEmpty) throw ArgumentError('缺少 DeepSeek API Key');
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse('https://api.deepseek.com/v1/tools/search'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${apiKey.trim()}',
          },
          body: jsonEncode({
            // The official limit is 128 Unicode characters.
            'query': String.fromCharCodes(normalizedQuery.runes.take(128)),
            'count': 5,
            'need_content': false,
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      // Do not include request headers, credentials or arbitrary server bodies.
      throw StateError('DeepSeek 搜索 HTTP ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map || body['results'] is! List) {
      throw const FormatException('DeepSeek 搜索响应缺少 results 数组');
    }
    final results = <Map<String, String>>[];
    for (final row in (body['results'] as List).whereType<Map>()) {
      final url = row['url']?.toString().trim() ?? '';
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasAuthority ||
          (uri.scheme != 'https' && uri.scheme != 'http')) continue;
      String text(List<String> fields) {
        for (final field in fields) {
          final value = row[field]?.toString().trim() ?? '';
          if (value.isNotEmpty) return value;
        }
        return '';
      }

      results.add({
        'title': text(['title', 'site_name']).isEmpty
            ? '网页来源'
            : text(['title', 'site_name']),
        'url': url,
        // summary is designed for models; content is empty when not requested.
        'snippet': text(['summary', 'snippet', 'content']),
      });
      if (results.length == 5) break;
    }
    return results;
  } finally {
    if (client == null) transport.close();
  }
}
