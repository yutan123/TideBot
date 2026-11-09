import 'dart:convert';
import 'package:tide_bot/tool_bot_scope.dart';
import 'package:tide_bot/tool_package_catalog.dart';
import 'package:tide_bot/tool_package_runtime.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  check(toolEnabledForBot(null, 'new-bot'),
      'Legacy/default scope allows new bots');
  for (final scope in ['[]', '["other"]', '{"bot":true}', 'broken']) {
    check(!toolEnabledForBot(scope, 'bot'),
        'Reject excluded or invalid scope: $scope');
  }
  check(toolEnabledForBot('["bot","other"]', 'bot'), 'Selected bot allowed');
  final rows = <Map<String, dynamic>>[
    {'id': 'shared', 'enabled': 1},
    {'id': 'private', 'enabled': 1, 'bot_scope': '["bot"]'},
    {'id': 'none', 'enabled': 1, 'bot_scope': '[]'},
  ];
  check(toolRowsForBot(rows, null).length == 3, 'Manager sees all scopes');
  check(toolRowsForBot(rows, 'bot').length == 2,
      'Selected bot sees shared and private');
  check(
      toolRowsForBot(rows, 'other').length == 1, 'Other bot only sees shared');

  ToolPackageCatalog catalog(String bot) => ToolPackageCatalog(
        skills: toolRowsForBot(rows, bot),
        servers: toolRowsForBot(rows, bot),
        skillTools: toolRowsForBot([
          for (final row in rows)
            {
              ...row,
              'skill_id': row['id'],
              'name': 'run',
              'schema_json': jsonEncode({'type': 'object'}),
            },
        ], bot),
        mcpTools: toolRowsForBot([
          for (final row in rows)
            {
              ...row,
              'server_id': row['id'],
              'name': 'run',
              'schema_json': jsonEncode({'type': 'object'}),
            },
        ], bot),
      );
  var executions = 0;
  for (final source in ['skill', 'mcp']) {
    check(catalog('bot').get('$source:private') != null,
        'Assigned package visible');
    check(catalog('other').get('$source:private') == null,
        'Unassigned package hidden');
    for (final operation in ['get_tool_package', 'call_package_tool']) {
      final denied = await executeToolPackage(
        catalog: catalog('other'),
        name: operation,
        args: {
          'package_id': '$source:private',
          'tool_name': 'run',
          'arguments': <String, dynamic>{}
        },
        execute: (source, id, name, arguments, reader) async {
          executions++;
          return {
            'result': {'ok': true}
          };
        },
      );
      check((denied['result'] as Map)['ok'] == false,
          'Stale/crafted request denied');
    }
    final allowed = await executeToolPackage(
      catalog: catalog('bot'),
      name: 'call_package_tool',
      args: {
        'package_id': '$source:private',
        'tool_name': 'run',
        'arguments': <String, dynamic>{}
      },
      execute: (source, id, name, arguments, reader) async {
        executions++;
        return {
          'result': {'ok': true}
        };
      },
    );
    check((allowed['result'] as Map)['ok'] == true, 'Assigned execution works');
  }
  check(executions == 2, 'Only assigned calls execute');
  print(
      'Passed: bot scope defaults, exclusions, catalog isolation and execution enforcement.');
}
