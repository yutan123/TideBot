import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/tool_completion.dart';

void main() {
  test('SSE continuation reconstructs fragmented tools and usage-only events',
      () {
    final events = [
      {
        'id': 'r1',
        'choices': [
          {
            'delta': {
              'reasoning_content': 'reason',
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'c1',
                  'function': {'name': 'search', 'arguments': '{"q":'}
                }
              ]
            }
          }
        ]
      },
      {
        'choices': [
          {
            'delta': {
              'reasoning_content': 'ing',
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '"test"}'}
                }
              ]
            }
          }
        ]
      },
      {
        'choices': [],
        'usage': {'cache_read_input_tokens': 1234}
      },
    ];
    final body =
        '${events.map((e) => 'data: ${jsonEncode(e)}\r\n\r\n').join()}data: [DONE]\r\n\r\n';
    final decoded = decodeToolCompletion(body);
    final message = decoded['choices'][0]['message'];
    expect(message['reasoning_content'], 'reasoning');
    expect(message['content'], isNull);
    expect(message['tool_calls'][0]['function']['arguments'], '{"q":"test"}');
    expect(decoded['usage']['cache_read_input_tokens'], 1234);
  });
  test('JSON fallback retains opaque reasoning metadata without UI parsing',
      () {
    final message = {
      'role': 'assistant',
      'content': '<inner_thought>感受</inner_thought>',
      'tool_calls': [],
      'reasoning_details': [
        {'signature': 'opaque', 'text': 'private'}
      ]
    };
    final decoded = decodeToolCompletion(jsonEncode({
      'choices': [
        {'message': message}
      ]
    }));
    expect(toolAssistantMessage(decoded['choices'][0]['message']), message);
  });
  test(
      'invalid bodies and SSE error events fail instead of becoming empty replies',
      () {
    expect(() => decodeToolCompletion('bad gateway'), throwsFormatException);
    expect(
        () => decodeToolCompletion('data: {"error":{"message":"failed"}}\n\n'),
        throwsFormatException);
  });
}
