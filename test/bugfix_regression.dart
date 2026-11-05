// Run directly with the Dart VM; no Flutter or Android build is required.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tide_bot/audit_redaction.dart';
import 'package:tide_bot/skill_runtime.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final input = <String, dynamic>{
    'query': 'visible',
    'credentials': {'password': 'nested-secret'},
    'Authorization': 'Bearer auth-secret',
    'items': [
      {'api_token': 'list-secret', 'text': 'safe'}
    ],
  };
  final redacted = redactToolInput(input);
  for (final value in ['nested-secret', 'auth-secret', 'list-secret']) {
    check(!redacted.contains(value), 'Credential leaked: $value');
  }
  check(redacted.contains('visible') && redacted.contains('safe'),
      'Safe context lost');
  check(input['Authorization'] == 'Bearer auth-secret', 'Input was mutated');
  final cyclic = <String, dynamic>{};
  cyclic['self'] = cyclic;
  check(redactToolInput(cyclic).contains('truncated'), 'Cycles must terminate');
  final large = redactToolInput({
    'x' * 100000: 'value',
    'items': List.generate(10000, (_) => '\u0000' * 200),
  });
  check(large.length <= 4000, 'Diagnostics exceed the size budget');
  jsonDecode(large);

  Future<void> pagination({required bool repeated}) async {
    var pages = 0;
    final transport = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      final method = body['method'];
      if (method == 'notifications/initialized') return http.Response('', 202);
      final result = method == 'initialize'
          ? {'protocolVersion': '2025-03-26'}
          : {'tools': [], 'nextCursor': repeated ? 'same' : '${++pages}'};
      if (method == 'tools/list' && repeated) pages++;
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
          200);
    });
    final client =
        McpClient(url: 'https://example.invalid/mcp', httpClient: transport);
    try {
      await client.initialize();
      var rejected = false;
      try {
        await client.listTools();
      } on StateError {
        rejected = true;
      }
      check(rejected, 'Endless pagination was accepted');
      check(pages == (repeated ? 2 : 100), 'Unexpected page limit: $pages');
    } finally {
      client.dispose();
      transport.close();
    }
  }

  await pagination(repeated: true);
  await pagination(repeated: false);
  print(
      'PASS: nested audit redaction, bounded/cyclic input, repeated and endless MCP cursors');
}
