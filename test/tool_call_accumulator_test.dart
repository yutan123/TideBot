import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/tool_call_accumulator.dart';

void main() {
  test('preserves image tool name and joins JSON argument fragments', () {
    final accumulator = ToolCallAccumulator();
    accumulator.add([
      {
        'index': 0,
        'id': 'call_image',
        'type': 'function',
        'function': {'name': 'generate_image', 'arguments': ''}
      }
    ]);
    accumulator.add([
      {
        'index': 0,
        'function': {'arguments': '{"prompt":"'}
      }
    ]);
    accumulator.add([
      {
        'index': 0,
        'function': {'arguments': '睡前照片"}'}
      }
    ]);
    final call = accumulator.calls.single;
    expect(call['id'], 'call_image');
    expect(call['function']['name'], 'generate_image');
    expect(jsonDecode(call['function']['arguments']), {'prompt': '睡前照片'});
    expect(call.containsKey('index'), false);
  });

  test('keeps interleaved tools independent and ordered by index', () {
    final accumulator = ToolCallAccumulator();
    accumulator.add([
      {
        'index': 1,
        'id': 'b',
        'function': {'name': 'set_emotion', 'arguments': '{"mood":'}
      }
    ]);
    accumulator.add([
      {
        'index': 0,
        'id': 'a',
        'function': {'name': 'generate_', 'arguments': '{"prompt":'}
      }
    ]);
    accumulator.add([
      {
        'index': 1,
        'function': {'arguments': '"开心"}'}
      },
      {
        'index': 0,
        'function': {'name': 'image', 'arguments': '"照片"}'}
      },
    ]);
    expect(accumulator.calls.map((call) => call['id']), ['a', 'b']);
    expect(accumulator.calls.first['function']['name'], 'generate_image');
    expect(jsonDecode(accumulator.calls.last['function']['arguments']),
        {'mood': '开心'});
  });

  test(
      'complete message snapshot replaces fragments instead of duplicating them',
      () {
    final accumulator = ToolCallAccumulator();
    accumulator.add([
      {
        'index': 0,
        'id': 'a',
        'function': {'name': 'generate_image', 'arguments': '{"prompt":'}
      }
    ]);
    accumulator.add([
      {
        'id': 'a',
        'type': 'function',
        'function': {'name': 'generate_image', 'arguments': '{"prompt":"照片"}'}
      }
    ], snapshot: true);
    expect(accumulator.calls.single['function']['name'], 'generate_image');
    expect(jsonDecode(accumulator.calls.single['function']['arguments']),
        {'prompt': '照片'});
  });
}
