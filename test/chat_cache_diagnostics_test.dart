import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_cache_diagnostics.dart';

Map<String, dynamic> tool(String name, {String description = 'fixed'}) => {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': {
            'source': {
              'enum': ['current', 'history']
            }
          },
          'required': ['source'],
        },
      },
    };

Map<String, dynamic> request({String dynamicText = 'mood A'}) =>
    prepareChatCompletionPayload({
      'model': 'example',
      'messages': [
        {'role': 'system', 'content': 'stable instructions'},
        {'role': 'user', 'content': 'old user message'},
        {'role': 'assistant', 'content': 'old reply'},
        {'role': 'system', 'content': dynamicText},
        {'role': 'user', 'content': 'current message'},
      ],
      'tools': [tool('z'), tool('a')],
      'max_tokens': 1000,
    });

void main() {
  test('canonical payload ignores object and tool order, preserves arrays', () {
    final a = request();
    final b = prepareChatCompletionPayload({
      for (final entry in a.entries.toList().reversed) entry.key: entry.value,
      'tools': (a['tools'] as List).reversed.toList(),
    });
    expect(jsonEncode(a), jsonEncode(b));
    expect((a['tools'] as List).first['function']['name'], 'a');
    expect(
        (a['tools'] as List).first['function']['parameters']['properties']
            ['source']['enum'],
        ['current', 'history']);
    final parts = [
      {'type': 'text', 'text': 'caption'},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,abc'}
      },
    ];
    final input = <String, dynamic>{
      'tools': [tool('z'), tool('a')],
      'messages': [
        {'role': 'user', 'content': parts}
      ],
    };
    final result = prepareChatCompletionPayload(input);
    expect(result['messages'], input['messages']);
    expect((input['tools'] as List).first['function']['name'], 'z');
    expect(identical(result['messages'], input['messages']), isFalse);
  });

  test('detects a later dynamic system change and correlates requests', () {
    final diagnostics = ChatCacheDiagnostics();
    final at = DateTime(2026, 10, 23, 22);
    diagnostics.record(
        scope: 'chat', requestId: 'first', payload: request(), at: at);
    final report = diagnostics.record(
      scope: 'chat',
      requestId: 'second',
      payload: request(dynamicText: 'mood B'),
      at: at.add(const Duration(seconds: 52)),
    );
    expect(report['previous_request_id'], 'first');
    expect(report['seconds_since_previous'], 52);
    expect(report['common_full_messages'], 3);
    expect(report['first_changed_message_index'], 3);
    expect(report['first_changed_message_role'], 'system');
    expect(report['system_message_indices'], [0, 3]);
    expect(report['fixed_changed'], isFalse);
    expect(report['tools_changed'], isFalse);
    expect(report['request_settings_changed'], isFalse);
    expect(jsonEncode(report), isNot(contains('mood B')));
    expect(jsonEncode(report), isNot(contains('old user message')));
  });

  test('identical requests and append or removal have accurate boundaries', () {
    final diagnostics = ChatCacheDiagnostics();
    diagnostics.record(scope: 'chat', requestId: '1', payload: request());
    final same =
        diagnostics.record(scope: 'chat', requestId: '2', payload: request());
    expect(same['first_changed_message_index'], isNull);
    expect(same['common_full_messages'], 5);
    final appended = request();
    (appended['messages'] as List)
        .add({'role': 'assistant', 'content': 'reply'});
    final more =
        diagnostics.record(scope: 'chat', requestId: '3', payload: appended);
    expect(more['first_changed_message_index'], 5);
    expect(more['first_changed_message_role'], 'assistant');
    expect(more['first_changed_message_previous_role'], isNull);
    final fewer =
        diagnostics.record(scope: 'chat', requestId: '4', payload: request());
    expect(fewer['first_changed_message_role'], isNull);
    expect(fewer['first_changed_message_previous_role'], 'assistant');
  });

  test('tool schema and request settings changes are distinguished', () {
    final diagnostics = ChatCacheDiagnostics();
    diagnostics.record(scope: 'chat', requestId: '1', payload: request());
    final changed = request();
    changed['tools'] = [
      tool('a'),
      tool('z', description: 'changed'),
      tool('new')
    ];
    changed['max_tokens'] = 2000;
    final report = diagnostics.record(
        scope: 'chat',
        requestId: '2',
        payload: prepareChatCompletionPayload(changed));
    expect(report['tools_changed'], isTrue);
    expect(report['changed_tool_names'], ['new', 'z']);
    expect(report['request_settings_changed'], isTrue);
    expect(report['first_changed_message_index'], isNull);
    expect(report['payload_sha256'], hasLength(64));
  });

  test('background tasks and tool follow-ups do not replace chat snapshot', () {
    final diagnostics = ChatCacheDiagnostics();
    diagnostics.record(
        scope: 'chat|initial', requestId: 'chat1', payload: request());
    for (final scope in [
      'diary|initial',
      'chat|tool_follow_up',
      'other-provider'
    ]) {
      diagnostics.record(scope: scope, requestId: scope, payload: request());
    }
    final report = diagnostics.record(
        scope: 'chat|initial', requestId: 'chat2', payload: request());
    expect(report['previous_request_id'], 'chat1');
    expect(report['first_changed_message_index'], isNull);
    diagnostics.clear();
    expect(
        diagnostics.record(
            scope: 'chat|initial',
            requestId: 'chat3',
            payload: request())['previous_request_available'],
        isFalse);
  });

  test('bounded snapshots evict oldest scope and skip oversized requests', () {
    final diagnostics = ChatCacheDiagnostics(maxEntries: 1);
    diagnostics.record(scope: 'a', requestId: '1', payload: request());
    diagnostics.record(scope: 'b', requestId: '2', payload: request());
    expect(
        diagnostics.record(
            scope: 'a',
            requestId: '3',
            payload: request())['previous_request_available'],
        isFalse);
    final limited = ChatCacheDiagnostics(maxSnapshotChars: 10);
    expect(
        limited.record(
            scope: 'a',
            requestId: '1',
            payload: request())['snapshot_retained'],
        isFalse);
    expect(
        limited.record(
            scope: 'a',
            requestId: '2',
            payload: request())['previous_request_available'],
        isFalse);
  });

  test('response identity excludes content and other provider fields', () {
    expect(
        cacheResponseMetadata({
          'id': 'response1',
          'model': 'resolved-model',
          'system_fingerprint': 'fp1',
          'choices': [
            {
              'message': {'content': 'private'}
            }
          ],
          'api_key': 'secret',
        }),
        {
          'response_id': 'response1',
          'returned_model': 'resolved-model',
          'system_fingerprint': 'fp1',
        });
  });
}
