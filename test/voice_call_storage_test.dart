import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tide_bot/db.dart';
import 'package:tide_bot/voice_call_state_service.dart';

// Exercise the real Dart database methods and SQL using Python's SQLite driver.
// No Android build, SQLite mock, or additional application dependency is needed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.tekartik.sqflite');
  late Process sqlite;
  late StreamIterator<String> replies;

  Future<dynamic> sql(String statement, [List<Object?> args = const []]) async {
    sqlite.stdin.writeln(jsonEncode({'sql': statement, 'args': args}));
    if (!await replies.moveNext()) throw StateError('SQLite process exited');
    final reply = jsonDecode(replies.current) as Map;
    if (reply.containsKey('error')) {
      throw PlatformException(
          code: 'sqlite_error', message: reply['error'] as String);
    }
    return reply['result'];
  }

  setUp(() async {
    sqlite = await Process.start('python3', [
      '-u',
      '-c',
      r'''
import sys, json, sqlite3
con = sqlite3.connect(':memory:', isolation_level=None)
con.row_factory = sqlite3.Row
for line in sys.stdin:
    try:
        req = json.loads(line)
        cursor = con.execute(req['sql'], req['args'])
        result = [dict(row) for row in cursor] if cursor.description else {
            'changes': cursor.rowcount, 'id': cursor.lastrowid
        }
        print(json.dumps({'result': result}), flush=True)
    except Exception as e:
        print(json.dumps({'error': str(e)}), flush=True)
'''
    ]);
    replies = StreamIterator(
        sqlite.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    await sql('PRAGMA user_version = 34');
    await sql('CREATE TABLE kv_store (key TEXT PRIMARY KEY, value TEXT)');
    await sql("INSERT INTO kv_store VALUES ('schema_repair_version', '36')");
    await sql('CREATE TABLE bots (id TEXT PRIMARY KEY, last_msg_time INTEGER)');
    await sql("INSERT INTO bots VALUES ('bot', 0)");
    await sql('CREATE TABLE memories (category TEXT)');
    await sql(
        'CREATE TABLE chat_history (id TEXT PRIMARY KEY, bot_id TEXT, role TEXT, type TEXT, content TEXT, timestamp INTEGER)');
    databaseFactory = databaseFactorySqflitePlugin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map? ?? {};
      switch (call.method) {
        case 'getDatabasesPath':
          return '/test/voice_storage';
        case 'openDatabase':
          return {'id': 1};
        case 'closeDatabase':
          return null;
        case 'query':
          return sql(args['sql'] as String,
              List<Object?>.from(args['arguments'] as List? ?? []));
        case 'execute':
        case 'insert':
        case 'update':
          final result = await sql(args['sql'] as String,
              List<Object?>.from(args['arguments'] as List? ?? [])) as Map;
          if (call.method == 'insert') return result['id'];
          if (call.method == 'update') return result['changes'];
          return null;
        default:
          throw StateError('Unexpected SQLite method: ${call.method}');
      }
    });
  });

  tearDown(() async {
    VoiceCallStateService.instance.reject('bot', 'call');
    VoiceCallStateService.instance.endCall();
    await DBManager().close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await sqlite.stdin.close();
    await replies.cancel();
    await sqlite.exitCode;
  });

  Future<void> save(
      {String status = 'ringing', String text = '', bool invalidCard = false}) {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    return DBManager().insertVoiceCallRecord(
      callId: 'call',
      botId: 'bot',
      initiator: 'assistant',
      status: status,
      transcript: text,
      summary: '',
      startTime: now,
      endTime: now.add(const Duration(seconds: 65)),
      chatMessage: {
        'id': 'card_call',
        'bot_id': 'bot',
        'role': 'assistant',
        'type': 'voice_call_card',
        'content': '[语音通话]',
        'call_id': 'call',
        'call_status': status,
        'call_duration': 65,
        'duration': 65,
        'timestamp': now.millisecondsSinceEpoch,
        if (invalidCard) 'invalid_column': 1,
      },
    );
  }

  test(
      'current repair marker still creates missing call storage and persists one incoming call',
      () async {
    await save();
    expect(
        (await DBManager().getVoiceCallRecord('call'))?['status'], 'ringing');
    await save(status: 'ended', text: '用户：你好\n机器人：你好');
    await DBManager().close();
    final record = await DBManager().getVoiceCallRecord('call');
    expect(record?['initiator'], 'assistant');
    expect(record?['transcript'], contains('用户：你好'));
    expect(record?['duration'], 65);
    final cards = await sql('SELECT * FROM chat_history');
    expect(cards, hasLength(1));
    expect(cards.first['id'], 'card_call');
    expect(cards.first['call_status'], 'ended');
  });

  test('populated old call table gains time fields without losing its records',
      () async {
    await sql(
        'CREATE TABLE voice_call_records (id TEXT PRIMARY KEY, bot_id TEXT, initiator TEXT, status TEXT, duration INTEGER, summary TEXT, transcript TEXT, timestamp INTEGER)');
    await sql(
        "INSERT INTO voice_call_records VALUES ('old', 'bot', 'user', 'ended', 10, '', '旧原文', 123)");
    await save();
    final old = await DBManager().getVoiceCallRecord('old');
    expect(old?['transcript'], '旧原文');
    expect(old?['start_time'], 0);
    expect((await DBManager().getVoiceCallRecord('call'))?['start_time'],
        1700000000000);
  });

  test(
      'failed card insert rolls back both new calls and changes to existing calls',
      () async {
    await expectLater(
        save(invalidCard: true), throwsA(isA<DatabaseException>()));
    expect(await DBManager().getVoiceCallRecord('call'), isNull);
    await save();
    await expectLater(save(status: 'ended', text: '未提交', invalidCard: true),
        throwsA(isA<DatabaseException>()));
    expect(
        (await DBManager().getVoiceCallRecord('call'))?['status'], 'ringing');
    expect(
        (await sql('SELECT call_status FROM chat_history'))
            .first['call_status'],
        'ringing');
  });
  test(
      'incoming state accepts the original call and timeout updates its persisted card',
      () async {
    await save();
    final service = VoiceCallStateService.instance;
    service.startRinging('call', 'bot');
    service.accept('bot', 'call');
    expect(service.activeCall?.callId, 'call');
    expect(service.hasRingingCall('bot'), isFalse);
    service.endCall();
    service.startRinging('call', 'bot');
    await service.timeout('bot', 'call');
    expect(service.hasRingingCall('bot'), isFalse);
    expect(
        (await DBManager().getVoiceCallRecord('call'))?['status'], 'timeout');
    expect(
        (await sql('SELECT call_status FROM chat_history'))
            .first['call_status'],
        'timeout');
  });

  test('storage repair errors propagate and cannot create a visible card',
      () async {
    await sql('CREATE VIEW voice_call_records AS SELECT 1 AS id');
    await expectLater(save(), throwsA(isA<DatabaseException>()));
    expect(await sql('SELECT * FROM chat_history'), isEmpty);
    expect(
        (await sql(
                "SELECT value FROM kv_store WHERE key = 'schema_repair_version'"))
            .first['value'],
        '36');
  });
}
