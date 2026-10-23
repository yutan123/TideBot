import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tide_bot/db.dart';

/// Runs the application's actual sqflite SQL against isolated Python SQLite.
/// Starts empty so DBManager runs its real onCreate and onOpen migrations.
class SqliteBridge {
  static const _channel = MethodChannel('com.tekartik.sqflite');
  late Process _process;
  late StreamIterator<String> _replies;

  Future<void> open() async {
    _process = await Process.start('python3', [
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
    _replies = StreamIterator(_process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter()));
    databaseFactory = databaseFactorySqflitePlugin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = call.arguments as Map? ?? {};
      switch (call.method) {
        case 'getDatabasesPath':
          return '/test/chat_cache';
        case 'openDatabase':
          return {'id': 1};
        case 'closeDatabase':
          return null;
        case 'query':
          return execute(args['sql'] as String,
              List<Object?>.from(args['arguments'] as List? ?? []));
        case 'execute':
        case 'insert':
        case 'update':
          final result = await execute(args['sql'] as String,
              List<Object?>.from(args['arguments'] as List? ?? [])) as Map;
          if (call.method == 'insert') return result['id'];
          if (call.method == 'update') return result['changes'];
          return null;
        default:
          throw StateError('Unexpected SQLite method: ${call.method}');
      }
    });
  }

  Future<dynamic> execute(String sql, [List<Object?> args = const []]) async {
    _process.stdin.writeln(jsonEncode({'sql': sql, 'args': args}));
    if (!await _replies.moveNext()) throw StateError('SQLite process exited');
    final reply = jsonDecode(_replies.current) as Map;
    if (reply.containsKey('error')) {
      throw PlatformException(
          code: 'sqlite_error', message: reply['error'] as String);
    }
    return reply['result'];
  }

  Future<void> close() async {
    await DBManager().close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    await _process.stdin.close();
    await _replies.cancel();
    await _process.exitCode;
  }
}
