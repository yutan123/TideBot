import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tide_bot/ai.dart';
import 'package:tide_bot/app_log_service.dart';
import 'package:tide_bot/db.dart';

import 'support/sqlite_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteBridge sqlite;
  final db = DBManager();
  final payloads = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> reports(String title) => AppLogService
      .instance.entries
      .where((e) => e.level == 'CACHE' && e.message.startsWith('$title\n'))
      .map((e) => jsonDecode(e.message.substring(e.message.indexOf('\n') + 1))
          as Map<String, dynamic>)
      .toList();

  Future<void> message(String id, String role, String content, int timestamp,
          {String type = 'text', String? path}) =>
      db.insertMessage({
        'id': id,
        'bot_id': 'cache-bot',
        'role': role,
        'type': type,
        'content': content,
        'timestamp': timestamp,
        if (path != null) 'file_path': path,
      });

  Future<Map<String, dynamic>> send(String text,
          {String extra = '',
          List<String>? images,
          bool streaming = true,
          bool callTool = false}) =>
      http.runWithClient(
          () => AIManager().sendMessage(
                botId: 'cache-bot',
                text: text,
                persistResponse: false,
                enableAutoSummary: false,
                skipLifeState: true,
                extraSystemPrompt: extra,
                imagePaths: images,
                onDelta: streaming ? (_) {} : null,
              ),
          () => MockClient((request) async {
                final payload =
                    jsonDecode(request.body) as Map<String, dynamic>;
                payloads.add(payload);
                final index = payloads.length;
                final usage = {
                  'prompt_tokens': 25835,
                  'completion_tokens': 3,
                  'total_tokens': 25838,
                  'prompt_tokens_details': {
                    'cached_tokens': index == 1 ? 18304 : 1152
                  },
                };
                if (payload['stream'] != true) {
                  final toolCall = callTool && index == 1;
                  return http.Response(
                      jsonEncode({
                        'id': 'response-$index',
                        'model': 'returned-cache-model',
                        'system_fingerprint': 'fp-cache',
                        'usage': usage,
                        'choices': [
                          {
                            'message': {
                              'role': 'assistant',
                              'content': toolCall ? null : '正常回复。',
                              if (toolCall)
                                'tool_calls': [
                                  {
                                    'id': 'call-1',
                                    'type': 'function',
                                    'function': {
                                      'name': 'inspect_image',
                                      'arguments':
                                          jsonEncode({'image_number': 999})
                                    },
                                  }
                                ],
                            },
                            'finish_reason': toolCall ? 'tool_calls' : 'stop',
                          }
                        ],
                      }),
                      200,
                      headers: {
                        'x-request-id': 'upstream-$index',
                        'content-type': 'application/json; charset=utf-8'
                      });
                }
                return http.Response(
                    [
                      'data: ${jsonEncode({
                            'id': 'response-$index',
                            'model': 'returned-cache-model',
                            'system_fingerprint': 'fp-cache',
                            'choices': [
                              {
                                'delta': {'content': '正常回复。'},
                                'finish_reason': null
                              }
                            ]
                          })}',
                      '',
                      'data: ${jsonEncode({
                            'choices': [
                              {'delta': {}, 'finish_reason': 'stop'}
                            ]
                          })}',
                      '',
                      'data: ${jsonEncode({
                            'id': 'response-$index',
                            'choices': [],
                            'usage': usage
                          })}',
                      '',
                      'data: [DONE]',
                      '',
                    ].join('\n'),
                    200,
                    headers: {
                      'content-type': 'text/event-stream; charset=utf-8',
                      'x-request-id': 'upstream-$index',
                    });
              }));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqlite = SqliteBridge();
    await sqlite.open();
    payloads.clear();
    await db.insertBot({
      'id': 'cache-bot',
      'name': '测试角色',
      'desc': '固定角色背景',
      'prompt': '自然回复。',
      'chat_model': 'cache-provider',
      'max_tokens': 128000,
    });
    await db.setKV(
        'provider_list',
        jsonEncode([
          {
            'id': 'cache-provider',
            'name': 'test',
            'url': 'https://cache.invalid/v1',
            'key': 'test-only',
            'model': 'cache-model',
          }
        ]));
    await AppLogService.instance.setEnabled(true);
  });

  tearDown(() async {
    await AppLogService.instance.setEnabled(false);
    await sqlite.close();
  });

  test(
      'real SQL and request assembly preserve long pure-text history across turns',
      () async {
    for (var i = 0; i < 40; i++) {
      await message('history-$i', i.isEven ? 'user' : 'assistant',
          '第$i条历史 ${'x' * 2500}', 1700000000000 + i * 1000);
    }
    for (final entry in [('a', 1), ('z', 2)]) {
      await db.saveSkill({
        'id': entry.$1,
        'name': 'skill-${entry.$1}',
        'version': '1.0.0',
        'description': '固定技能',
        'manifest_json': jsonEncode({'instructions': '固定指引-${entry.$1}'}),
        'enabled': 1,
        'updated_at': entry.$2,
      }, []);
    }
    for (var turn = 0; turn < 3; turn++) {
      final text = '纯文本第$turn轮';
      await message('user-$turn', 'user', text, 1700000100000 + turn * 2000);
      // Database query order changes without changing the skill instructions.
      await (await db.database).update('skills', {'updated_at': 10 + turn},
          where: 'id = ?', whereArgs: [turn.isEven ? 'a' : 'z']);
      final result = await send(text, extra: '本轮动态约束-$turn');
      expect(result['success'], isTrue, reason: '$result');
      expect(result['reply'], '正常回复。');
      expect((result['usage'] as Map)['prompt_tokens'], 25835);
      await message(
          'assistant-$turn', 'assistant', '正常回复。', 1700000101000 + turn * 2000);
    }
    expect(payloads, hasLength(3)); // No tool follow-up or provider retry.
    final firstMessages = payloads.first['messages'] as List;
    for (var i = 1; i < payloads.length; i++) {
      final messages = payloads[i]['messages'] as List;
      expect(messages.take(41).toList(), firstMessages.take(41).toList());
      expect(payloads[i]['tools'], payloads.first['tools']);
      expect(messages.where((m) => m['role'] == 'user').last['content'],
          contains('纯文本第$i轮'));
    }
    final stable = firstMessages.first['content'] as String;
    expect(stable, contains('固定指引-a'));
    expect(stable.indexOf('固定指引-a'), lessThan(stable.indexOf('固定指引-z')));
    expect(stable, isNot(contains('本轮动态约束')));
    expect(jsonEncode(firstMessages), isNot(contains('local_timestamp')));
    final diagnostics = reports('完整请求前缀变化诊断');
    expect(diagnostics, hasLength(3));
    for (final report in diagnostics.skip(1)) {
      expect(report['fixed_changed'], isFalse);
      expect(report['tools_changed'], isFalse);
      expect(report['common_full_messages'], greaterThanOrEqualTo(41));
      expect((report['history_window'] as Map)['rolled_messages'], 0);
    }
    final usages = reports('分请求缓存统计');
    expect(usages.map((u) => u['cached_tokens']).toList(), [18304, 1152, 1152]);
    for (var i = 0; i < usages.length; i++) {
      expect(usages[i]['request_id'], diagnostics[i]['request_id']);
      expect(usages[i]['response_id'], 'response-${i + 1}');
      expect(usages[i]['provider_request_id'], 'upstream-${i + 1}');
      expect(usages[i]['returned_model'], 'returned-cache-model');
      expect(usages[i]['system_fingerprint'], 'fp-cache');
    }
  });

  test(
      'image markers stay beside messages without changing fixed instructions or tools',
      () async {
    await message('u1', 'user', '先聊纯文本', 1700000000000);
    expect((await send('先聊纯文本'))['success'], isTrue);
    await message('a1', 'assistant', '正常回复。', 1700000001000);
    await message('image1', 'user', '旧图说明', 1700000002000,
        type: 'image', path: '/test/old-image.png');
    await message('u2', 'user', '再聊纯文本', 1700000003000);
    expect((await send('再聊纯文本'))['success'], isTrue);
    expect(
        (await send('编辑本轮图',
            images: ['/test/current1.png', '/test/current2.png']))['success'],
        isTrue);
    final stable = (payloads.first['messages'] as List).first;
    final tools = payloads.first['tools'];
    for (final payload in payloads) {
      expect((payload['messages'] as List).first, stable);
      expect(payload['tools'], tools);
      expect(jsonEncode(payload), isNot(contains('历史编号')));
      expect(jsonEncode(payload), isNot(contains('本轮编号')));
    }
    final historyMessages = payloads[1]['messages'] as List;
    expect(
        historyMessages.any((m) =>
            m['role'] == 'user' && m['content'].toString().contains('[图片#1]')),
        isTrue);
    final current = (payloads[2]['messages'] as List)
        .where((m) => m['role'] == 'user')
        .last;
    expect(jsonEncode(current), contains('[本轮图片#1]'));
    expect(jsonEncode(current), contains('[本轮图片#2]'));
  });

  test('actual window rollover is distinguished from reloading a saved cursor',
      () async {
    await db.updateBot('cache-bot', {'max_tokens': 1000});
    for (var i = 0; i < 12; i++) {
      await message('history-$i', i.isEven ? 'user' : 'assistant', 'x' * 800,
          1700000000000 + i * 1000);
    }
    await message('u1', 'user', '第一轮', 1700000020000);
    expect((await send('第一轮'))['success'], isTrue);
    await message('a1', 'assistant', '正常回复。', 1700000021000);
    await message('u2', 'user', '第二轮', 1700000022000);
    expect((await send('第二轮'))['success'], isTrue);
    final diagnostics = reports('完整请求前缀变化诊断');
    final first = diagnostics[0]['history_window'] as Map;
    final second = diagnostics[1]['history_window'] as Map;
    expect(first['rolled_messages'], greaterThan(0));
    expect(second['rolled_messages'], 0);
    expect(second['removed_messages'], greaterThan(0));
    expect(second['start_id'], first['start_id']);
    expect(second['previous_start_id'], first['start_id']);
    final count = first['retained_messages'] as int;
    expect((payloads[1]['messages'] as List).take(count + 1).toList(),
        (payloads[0]['messages'] as List).take(count + 1).toList());
  });
  test(
      'non-streaming tool follow-up uses canonical payload and separate correlation',
      () async {
    await message('u1', 'user', '回看旧图', 1700000000000);
    final result = await send('回看旧图', streaming: false, callTool: true);
    expect(result['success'], isTrue, reason: '$result');
    expect(payloads, hasLength(2));
    expect(payloads[1]['tools'], payloads[0]['tools']);
    final followUpMessages = payloads[1]['messages'] as List;
    expect(followUpMessages.last['role'], 'tool');
    expect(followUpMessages.last['tool_call_id'], 'call-1');
    final diagnostics = reports('完整请求前缀变化诊断');
    final usages = reports('分请求缓存统计');
    expect(diagnostics, hasLength(2));
    expect(usages, hasLength(2));
    expect(
        diagnostics[1]['request_id'], '${diagnostics[0]['request_id']}_tool_1');
    expect(usages[0]['stage'], 'initial');
    expect(usages[1]['stage'], 'tool_follow_up');
    expect(usages[1]['request_id'], diagnostics[1]['request_id']);
    expect(usages[1]['response_id'], 'response-2');
    expect(usages[1]['cached_tokens'], 1152);
  });
}
