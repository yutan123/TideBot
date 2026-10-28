import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tide_bot/deepseek_search.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

Future<void> main() async {
  var requests = 0;
  final client = MockClient((request) async {
    requests++;
    check(request.method == 'POST', 'Wrong method');
    check(request.url.toString() == 'https://api.deepseek.com/v1/tools/search',
        'Wrong official endpoint');
    check(
        request.headers['authorization'] == 'Bearer sample-key', 'Wrong auth');
    final body = jsonDecode(request.body) as Map;
    check(body['count'] == 5 && body['need_content'] == false, 'Wrong options');
    check(body['query'] == 'DeepSeek site:example.com', 'Search syntax lost');
    return http.Response.bytes(
        utf8.encode(jsonEncode({
          'results': [
            {
              'title': '中文标题',
              'url': 'https://example.com/1',
              'content': '',
              'snippet': '简短摘要',
              'summary': '给模型的详细摘要'
            },
            {
              'title': '',
              'site_name': '示例站点',
              'url': 'https://example.com/2',
              'summary': '',
              'snippet': '备用摘要'
            },
            {'title': '无效地址', 'url': 'javascript:alert(1)'},
            null
          ]
        })),
        200);
  });
  final result = await searchDeepSeek(
      query: '  DeepSeek site:example.com  ',
      apiKey: ' sample-key ',
      client: client);
  check(result.length == 2, 'Invalid results not filtered');
  check(result[0]['title'] == '中文标题' && result[0]['snippet'] == '给模型的详细摘要',
      'Summary or UTF-8 lost');
  check(result[1]['title'] == '示例站点' && result[1]['snippet'] == '备用摘要',
      'Fallback fields lost');
  check(
      (await searchDeepSeek(query: ' ', apiKey: '', client: client)).isEmpty &&
          requests == 1,
      'Empty query made request');

  final unicode = MockClient((request) async {
    final query = (jsonDecode(request.body) as Map)['query'] as String;
    check(query.runes.length == 128 && !query.contains('\uFFFD'),
        'Unicode query limit broken');
    return http.Response('{"results":[]}', 200);
  });
  check(
      (await searchDeepSeek(
              query: List.filled(150, '😀').join(),
              apiKey: 'key',
              client: unicode))
          .isEmpty,
      'No results mishandled');
  for (final status in [400, 401, 402, 429, 500]) {
    try {
      await searchDeepSeek(
          query: 'test',
          apiKey: 'key',
          client: MockClient((_) async => http.Response('not JSON', status)));
      throw StateError('HTTP $status accepted');
    } on StateError catch (error) {
      check(error.toString().contains('DeepSeek 搜索 HTTP $status'),
          'Wrong status handling: $error');
    }
  }
  for (final body in ['not JSON', '{}', '{"results":{}}']) {
    try {
      await searchDeepSeek(
          query: 'test',
          apiKey: 'key',
          client: MockClient((_) async => http.Response(body, 200)));
      throw StateError('Malformed response accepted');
    } on FormatException {
      // Invalid responses must not be mistaken for a successful empty search.
    }
  }
  try {
    await searchDeepSeek(
        query: 'test',
        apiKey: 'key',
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) => Completer<http.Response>().future));
    throw StateError('Timeout ignored');
  } on TimeoutException {
    // The caller can fall back instead of waiting indefinitely.
  }
  print('DeepSeek search checks passed: endpoint/auth/body, Chinese summaries, '
      'source links, Unicode limit, empty results, HTTP failures, invalid JSON, timeout.');
}
