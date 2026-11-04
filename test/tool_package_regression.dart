import 'dart:convert';
import 'package:tide_bot/tool_package_catalog.dart';
import 'package:tide_bot/tool_package_runtime.dart';
import 'package:tide_bot/tool_argument_validation.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final schema = {
    'type': 'object',
    'properties': {
      'city': {'type': 'string', 'minLength': 1},
      'days': {'type': 'integer', 'minimum': 1, 'maximum': 7},
    },
    'required': ['city'],
    'additionalProperties': false
  };
  Map<String, dynamic> tool(String parent, String name,
          {bool sensitive = false,
          bool authorized = false,
          bool enabled = true}) =>
      {
        'skill_id': parent,
        'server_id': parent,
        'name': name,
        'description': '查询城市天气',
        'schema_json': jsonEncode(schema),
        'enabled': enabled ? 1 : 0,
        'risk_level': sensitive ? 'sensitive' : 'normal',
        'authorized': authorized ? 1 : 0,
        'url': 'PRIVATE_URL',
        'secret': 'PRIVATE_SECRET',
      };
  final skills = <Map<String, dynamic>>[
    {
      'id': 'same',
      'name': '同名包',
      'enabled': 1,
      'description': '技能天气',
      'manifest_json': jsonEncode({
        'instructions': 'PRIVATE_GUIDANCE_ONLY_ON_VIEW',
        'files': ['references/guide.md'],
        'tools': [
          {'secret': 'PRIVATE_EXECUTOR'}
        ]
      }),
    },
    {
      'id': 'guide',
      'name': '纯指引',
      'enabled': 1,
      'manifest_json': jsonEncode({'instructions': '先整理再总结'})
    },
    {'id': 'disabled', 'enabled': 0}
  ];
  final servers = <Map<String, dynamic>>[
    {
      'id': 'same',
      'name': '同名包',
      'enabled': 1,
      'service_description': '服务天气说明',
      'url': 'PRIVATE_URL',
    },
    {'id': 'fallback', 'enabled': 1},
    {'id': 'disabled', 'enabled': 0}
  ];
  final skillTools = [
    tool('same', 'search'),
    tool('same', 'secret_tool', sensitive: true),
    tool('same', 'approved', sensitive: true, authorized: true),
    tool('same', 'off', enabled: false),
    tool('same', 'read_skill_file')
  ];
  final mcpTools = [tool('same', 'search'), tool('fallback', 'search')];
  ToolPackageCatalog catalog() => ToolPackageCatalog(
      skills: skills,
      servers: servers,
      skillTools: skillTools,
      mcpTools: mcpTools);
  final packages = catalog();
  check(packages.schemas().length == 2, 'Expose exactly two unified tools');
  final initial = jsonEncode(packages.schemas());
  for (final secret in [
    'PRIVATE_GUIDANCE',
    'PRIVATE_EXECUTOR',
    'PRIVATE_URL',
    'PRIVATE_SECRET',
    'schema_json',
    'secret_tool',
    'references/guide.md'
  ]) {
    check(!initial.contains(secret), 'Initial catalog leaked $secret');
  }
  check(packages.summaries.length == 4, 'Group each enabled source once');
  check(packages.get('skill:same') != null && packages.get('mcp:same') != null,
      'Same source IDs must not collide across kinds');
  check(packages.get('mcp:same')!['description'] == '服务天气说明',
      'Use service description');
  check(packages.get('mcp:fallback')!['description'] == '查询城市天气',
      'Summarize tools');
  servers.first['description'] = '用户填写';
  check(catalog().get('mcp:same')!['description'] == '用户填写',
      'Prefer user description');
  final calls = <String>[];
  Future<Map<String, dynamic>> execute(String source, String id, String name,
      Map<String, dynamic> args, bool reader) async {
    calls.add('$source:$id/$name:$reader');
    return {
      'result': {'ok': true, 'city': args['city']}
    };
  }

  Future<Map> run(String operation, Map<String, dynamic> args) async =>
      (await executeToolPackage(
          catalog: catalog(),
          name: operation,
          args: args,
          execute: execute))['result'] as Map;
  final viewed = await run('get_tool_package', {'package_id': 'skill:same'});
  check(viewed['instructions'] == 'PRIVATE_GUIDANCE_ONLY_ON_VIEW',
      'Lazy instructions');
  check(!jsonEncode(viewed).contains('PRIVATE_EXECUTOR'),
      'Do not disclose executors');
  check(!jsonEncode(viewed).contains('secret_tool'), 'Hide unauthorized tools');
  check(viewed['tool_count'] == 4, 'Count permitted tools plus file reader');
  check(calls.isEmpty, 'Discovery must not execute');
  for (final id in ['skill:same', 'mcp:same']) {
    final result = await run('call_package_tool', {
      'package_id': id,
      'tool_name': 'search',
      'arguments': {'city': '北京', 'days': 2}
    });
    check(result['ok'] == true, 'Dispatch $id');
  }
  check(calls[0] != calls[1], 'Same tool names route by package');
  final count = calls.length;
  for (final arguments in [
    {},
    {'city': ''},
    {'city': '北京', 'days': 8},
    {'city': '北京', 'days': '2'},
    {'city': '北京', 'extra': 1},
    'not an object'
  ]) {
    final result = await run('call_package_tool', {
      'package_id': 'mcp:same',
      'tool_name': 'search',
      'arguments': arguments
    });
    check(result['ok'] == false, 'Reject malformed args: $arguments');
  }
  for (final name in ['secret_tool', 'off', 'unknown']) {
    check(
        (await run('call_package_tool', {
              'package_id': 'skill:same',
              'tool_name': name,
              'arguments': {'city': '北京'}
            }))['ok'] ==
            false,
        'Reject $name');
  }
  check(calls.length == count, 'Invalid calls must not reach executor');
  final reader = (viewed['tools'] as List)
      .cast<Map>()
      .firstWhere((t) => t['reference_reader'] == true);
  check(reader['name'] == '_read_skill_file',
      'Virtual reader must not shadow a real tool');
  check(
      (await run('call_package_tool', {
            'package_id': 'skill:same',
            'tool_name': reader['name'],
            'arguments': {'path': 'references/guide.md'}
          }))['ok'] ==
          true,
      'Read packaged references');
  check(calls.last.endsWith(':true'), 'Route reference reader separately');
  servers.first['enabled'] = 0;
  check(
      (await run('call_package_tool', {
            'package_id': 'mcp:same',
            'tool_name': 'search',
            'arguments': {'city': '北京'}
          }))['ok'] ==
          false,
      'Recheck package permission after discovery');
  skillTools.first['enabled'] = 0;
  check(
      (await run('call_package_tool', {
            'package_id': 'skill:same',
            'tool_name': 'search',
            'arguments': {'city': '北京'}
          }))['ok'] ==
          false,
      'Recheck tool permission after discovery');
  check(
      (await run('get_tool_package', {'package_id': 'skill:guide'}))[
              'instructions'] ==
          '先整理再总结',
      'Instruction-only skills remain usable');
  check(
      ToolPackageCatalog(skills: [], servers: [], skillTools: [], mcpTools: [])
          .schemas()
          .isEmpty,
      'No gateways when nothing is enabled');

  skills.add({'id': 'broken', 'enabled': 1, 'manifest_json': 'not json'});
  check(catalog().get('skill:guide') != null,
      'Broken packages must not block healthy packages');
  final failed = await executeToolPackage(
      catalog: catalog(),
      name: 'call_package_tool',
      args: {
        'package_id': 'mcp:fallback',
        'tool_name': 'search',
        'arguments': {'city': '北京'}
      },
      execute: (_, __, ___, ____, _____) async =>
          throw StateError('connection lost'));
  check((failed['result'] as Map)['ok'] == false,
      'Executor exceptions return repairable errors');
  skillTools[2]['authorized'] = 0;
  check(
      (await run('call_package_tool', {
            'package_id': 'skill:same',
            'tool_name': 'approved',
            'arguments': {'city': '北京'}
          }))['ok'] ==
          false,
      'Revoked sensitive authorization takes effect immediately');

  final nested = {
    'type': 'object',
    r'$defs': {
      'point': {'type': 'integer', 'minimum': 0}
    },
    'properties': {
      'points': {
        'type': 'array',
        'items': {r'$ref': r'#/$defs/point'},
        'minItems': 1
      }
    }
  };
  check(
      validateToolArguments(nested, {
            'points': [1, 2]
          }) ==
          null,
      'Nested refs valid');
  check(
      validateToolArguments(nested, {
            'points': [-1]
          }) !=
          null,
      'Nested refs enforce minimum');
  check(
      validateToolArguments({
            'oneOf': [
              {'type': 'string'},
              {'type': 'integer'}
            ]
          }, true) !=
          null,
      'Reject invalid union');
  check(
      validateToolArguments({
            'type': ['string', 'null']
          }, null) ==
          null,
      'Nullable union');
  print(
      'PASS: package catalog, lazy guidance, dispatch, same-name isolation, reference reader, live permissions and argument validation');
}
