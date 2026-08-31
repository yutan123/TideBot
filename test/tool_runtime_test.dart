import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tide_bot/bot_state.dart';
import 'package:tide_bot/skill_runtime.dart';

void main() {
  group('isBotDisabled', () {
    test('accepts only explicit disabled values', () {
      expect(isBotDisabled(1), isTrue);
      expect(isBotDisabled(' true '), isTrue);
      expect(isBotDisabled(false), isFalse);
      expect(isBotDisabled(0), isFalse);
      expect(isBotDisabled('unavailable'), isFalse);
      expect(isBotDisabled(null), isFalse);
    });
  });

  group('TideSkillValidator', () {
    test('accepts a constrained HTTP skill', () {
      final result = TideSkillValidator.validate({
        'id': 'example.weather',
        'name': 'Weather',
        'version': '1.0.0',
        'tools': [
          {
            'name': 'forecast',
            'executor': 'http',
            'url': 'https://example.com/weather',
            'input_schema': {'type': 'object'},
          },
        ],
      });
      expect(result.isValid, isTrue);
    });

    test('rejects arbitrary executable definitions and duplicate tools', () {
      final result = TideSkillValidator.validate({
        'id': 'unsafe',
        'name': 'Unsafe',
        'version': '1',
        'tools': [
          {'name': 'run', 'executor': 'python'},
          {'name': 'run', 'executor': 'native'},
        ],
      });
      expect(result.isValid, isFalse);
      expect(result.error, contains('不支持执行器'));
    });

    test('validates mcp proxy and prompt executor definitions', () {
      final missingProxyTarget = TideSkillValidator.validate({
        'id': 'example.proxy',
        'name': 'Proxy',
        'version': '1.0.0',
        'tools': [
          {'name': 'call', 'executor': 'mcp_proxy'},
        ],
      });
      expect(missingProxyTarget.isValid, isFalse);
      expect(missingProxyTarget.error, contains('mcp_server_id'));

      final prompt = TideSkillValidator.validate({
        'id': 'example.prompt',
        'name': 'Prompt',
        'version': '1.0.0',
        'tools': [
          {
            'name': 'guide',
            'executor': 'prompt',
            'prompt': 'Use the supplied arguments as context.',
          },
        ],
      });
      expect(prompt.isValid, isTrue);
    });

    test(
        'rejects unsupported Skill metadata and undeclared executor permissions',
        () {
      final unsupportedVersion = TideSkillValidator.validate({
        'id': 'example.future',
        'name': 'Future',
        'version': '1.0.0',
        'api_version': '2',
        'tools': const [],
      });
      expect(unsupportedVersion.isValid, isFalse);
      expect(unsupportedVersion.error, contains('api_version'));

      final missingPermission = TideSkillValidator.validate({
        'id': 'example.permission',
        'name': 'Permission',
        'version': '1.0.0',
        'api_version': '1',
        'permissions': ['prompt'],
        'tools': [
          {
            'name': 'fetch',
            'executor': 'http',
            'url': 'https://example.com',
          },
        ],
      });
      expect(missingPermission.isValid, isFalse);
      expect(missingPermission.error, contains('network'));
    });

    test('classifies MCP transport failures for connection diagnostics', () {
      expect(
        McpClient.describeError(TimeoutException('timed out')),
        'MCP 请求超时',
      );
      expect(
        McpClient.describeError(StateError('MCP HTTP 401')),
        contains('鉴权失败'),
      );
      expect(
        McpClient.describeError(StateError('MCP HTTP 503')),
        contains('服务端错误'),
      );
    });

    test('parses JSON and SSE MCP responses', () {
      expect(
        McpClient.parseResponseBody('{"result":{"tools":[]}}'),
        {'tools': []},
      );
      expect(
        McpClient.parseResponseBody(
            'event: message\ndata: {"result":{"prompts":[]}}\n\n'),
        {'prompts': []},
      );
    });

    test('preserves MCP tool result structures and surfaces isError', () async {
      expect(
        McpClient.parseResponseBody(
          '{"result":{"content":[{"type":"text","text":"ok"}],'
          '"structuredContent":{"answer":42},"isError":false}}',
        ),
        {
          'content': [
            {'type': 'text', 'text': 'ok'}
          ],
          'structuredContent': {'answer': 42},
          'isError': false,
        },
      );
      expect(
        McpClient.parseResponseBody(
          '{"result":{"content":[{"type":"text","text":"failed"}],'
          '"isError":true}}',
        )['isError'],
        isTrue,
      );
    });
    test('rejects MCP error responses', () {
      expect(
        () => McpClient.parseResponseBody('{"error":{"code":-1}}'),
        throwsStateError,
      );
    });

    test('runs a Streamable HTTP session with cursor pagination', () async {
      final methods = <String>[];
      final sessions = <String?>[];
      final client = MockClient((request) async {
        sessions.add(request.headers['mcp-session-id']);
        if (request.method == 'DELETE') {
          expect(request.headers['accept'], contains('text/event-stream'));
          return http.Response('', 204);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'] as String;
        methods.add(method);
        if (method == 'notifications/initialized') {
          expect(request.headers['mcp-session-id'], 'session-1');
          return http.Response('', 202);
        }
        final id = body['id'];
        final params = body['params'] as Map<String, dynamic>;
        switch (method) {
          case 'initialize':
            expect(params['protocolVersion'], '2025-03-26');
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': id,
                'result': {'protocolVersion': '2025-03-26'},
              }),
              200,
              headers: {'mcp-session-id': 'session-1'},
            );
          case 'tools/list':
            final cursor = params['cursor'];
            return http.Response(
              'data: ${jsonEncode({
                    'jsonrpc': '2.0',
                    'id': id,
                    'result': cursor == null
                        ? {
                            'tools': [
                              {'name': 'first'}
                            ],
                            'nextCursor': 'page-2',
                          }
                        : {
                            'tools': [
                              {'name': 'second'}
                            ],
                          },
                  })}\n\n',
              200,
            );
          case 'tools/call':
            expect(params['name'], 'first');
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': id,
                'result': {
                  'content': [
                    {'type': 'text', 'text': 'done'}
                  ],
                },
              }),
              200,
            );
        }
        fail('unexpected MCP method: $method');
      });
      final mcp = McpClient(
        url: 'https://mcp.example.test/mcp',
        headers: const {'Authorization': 'Bearer token'},
        httpClient: client,
      );

      await mcp.initialize();
      final tools = await mcp.listTools();
      final result = await mcp.callTool('first', const {'query': 'hello'});
      await mcp.close();
      mcp.dispose();

      expect(tools.map((tool) => tool['name']), ['first', 'second']);
      expect(result['content'], [
        {'type': 'text', 'text': 'done'}
      ]);
      expect(
        methods,
        [
          'initialize',
          'notifications/initialized',
          'tools/list',
          'tools/list',
          'tools/call'
        ],
      );
      expect(sessions, [
        null,
        'session-1',
        'session-1',
        'session-1',
        'session-1',
        'session-1'
      ]);
      expect(mcp.sessionId, isNull);
      expect(mcp.negotiatedProtocolVersion, isNull);
    });

    test('cleans up a negotiated session when a tool call fails', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'DELETE') return http.Response('', 204);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'initialize') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {},
            }),
            200,
            headers: {'mcp-session-id': 'session-2'},
          );
        }
        if (body['method'] == 'notifications/initialized') {
          return http.Response('', 202);
        }
        return http.Response('gateway failure', 502);
      });
      final mcp = McpClient(
        url: 'https://mcp.example.test/mcp',
        httpClient: client,
      );

      await mcp.initialize();
      await expectLater(mcp.callTool('broken', const {}), throwsStateError);
      await mcp.close();

      expect(requests.last.method, 'DELETE');
      expect(requests.last.headers['mcp-session-id'], 'session-2');
      expect(mcp.sessionId, isNull);
    });
  });
}
