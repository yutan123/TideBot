import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tide_bot/skill_runtime.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final rows = [
    {'server_id': 'mcp_1790000000000', 'name': 'search_web'},
    {'server_id': 'other_server', 'name': 'search_web'},
  ];
  final alias = mcpToolName(rows.first['server_id'], rows.first['name']);
  check(resolveMcpTool(rows, alias) == rows.first,
      'Generated server IDs and tool names must survive routing');
  check(resolveMcpTool(rows, 'mcp_missing_search_web') == null,
      'Unknown tools must stay unavailable');
  check(
      McpClient.parseResponseBody(
              'event: message\r\ndata: {"jsonrpc":"2.0","method":"notifications/progress"}\r\n\r\n'
              'data: {"jsonrpc":"2.0","id":7,\r\ndata: "result":{"ok":true}}\r\n\r\n'
              'data: {"jsonrpc":"2.0","method":"notifications/progress"}\r\n\r\n',
              expectedId: 7)['ok'] ==
          true,
      'SSE must join multiline data and select the matching response');

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final calls = <String>[];
  Object? serverError;
  server.listen((request) async {
    try {
      if (request.method == 'DELETE') {
        request.response.statusCode = 204;
        await request.response.close();
        return;
      }
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      final method = body['method'] as String;
      calls.add(method);
      check(
          request.headers.value('authorization') == 'Bearer test', 'Auth lost');
      if (method != 'initialize') {
        check(request.headers.value('mcp-session-id') == 'session-test',
            'Session header missing');
        check(request.headers.value('mcp-protocol-version') == '2025-03-26',
            'Negotiated protocol header missing');
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = 202;
        await request.response.close();
        return;
      }
      final id = body['id'];
      if (method == 'tools/call') {
        final params = body['params'] as Map;
        check(params['name'] == 'search_web', 'Original tool name lost');
        check(params['arguments']['query'] == 'hello', 'Arguments lost');
        request.response.bufferOutput = false;
        request.response.headers.contentType =
            ContentType('text', 'event-stream');
        request.response.write(
            'data: {"jsonrpc":"2.0","method":"notifications/progress"}\n\n');
        request.response.write('data: ${jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'content': [
                  {'type': 'text', 'text': 'done'}
                ],
                'structuredContent': {'answer': 42}
              }
            })}\n\n');
        await request.response.flush();
        // Deliberately keep the response open. The client must return now.
        return;
      }
      request.response.headers.contentType = ContentType.json;
      if (method == 'initialize') {
        request.response.headers.set('Mcp-Session-Id', 'session-test');
      }
      request.response.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': method == 'initialize'
            ? {'protocolVersion': '2025-03-26'}
            : {
                'tools': [
                  {'name': 'search_web'}
                ]
              },
      }));
      await request.response.close();
    } catch (error) {
      serverError = error;
      request.response.statusCode = 500;
      await request.response.close();
    }
  });
  final client = McpClient(
    url: 'http://127.0.0.1:${server.port}/mcp',
    headers: const {'Authorization': 'Bearer test'},
    timeout: const Duration(seconds: 3),
  );
  try {
    await client.initialize();
    check((await client.listTools()).single['name'] == 'search_web',
        'List failed');
    final result = await client.callTool(
        'search_web', {'query': 'hello'}).timeout(const Duration(seconds: 2));
    check(
        result['structuredContent']['answer'] == 42, 'Structured result lost');
    check(
        calls.join(',') ==
            'initialize,notifications/initialized,tools/list,tools/call',
        'Wrong lifecycle');
    if (serverError != null) throw serverError!;
    await client.close();
  } finally {
    client.dispose();
    await server.close(force: true);
  }

  final rejected = McpClient(
    url: 'https://example.test/mcp',
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      if (body['method'] == 'notifications/initialized') {
        return http.Response('', 403);
      }
      return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {'protocolVersion': '2025-03-26'}
          }),
          200);
    }),
  );
  try {
    await rejected.initialize();
    throw StateError('Rejected initialization notification was ignored');
  } on StateError catch (error) {
    check(
        error.toString().contains('403'), 'Wrong notification failure: $error');
  }
  final failure = McpClient(
    url: 'https://example.test/mcp',
    httpClient: MockClient((request) async => http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': (jsonDecode(request.body) as Map)['id'],
          'result': {
            'isError': true,
            'content': [
              {'type': 'text', 'text': 'bad input'}
            ]
          }
        }),
        200)),
  );
  try {
    await failure.callTool('bad', {});
    throw StateError('Tool error was ignored');
  } on StateError catch (error) {
    check(error.toString().contains('bad input'), 'Wrong tool failure: $error');
  }
  print('MCP checks passed: routing, HTTP session/auth/version, list/call, '
      'open SSE, multiline events, structured results, notification/tool errors');
}
