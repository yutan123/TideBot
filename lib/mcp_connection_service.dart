import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'db.dart';
import 'skill_runtime.dart';

class McpConnectionService {
  McpConnectionService._();

  static final instance = McpConnectionService._();
  bool _running = false;

  Future<void> connectAuto() async {
    if (_running) return;
    _running = true;
    try {
      final servers = await DBManager().queryMcpServers();
      await Future.wait(
        servers
            .where((server) =>
                server['enabled'] == 1 && server['auto_connect'] == 1)
            .map(_connectOne),
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _connectOne(Map<String, dynamic> server) async {
    final id = server['id']?.toString() ?? '';
    final url = server['url']?.toString() ?? '';
    if (id.isEmpty || url.isEmpty) return;
    await DBManager().updateMcpStatus(id, 'connecting');
    try {
      final stored =
          await const FlutterSecureStorage().read(key: 'mcp_headers_$id');
      final headers = <String, String>{};
      if (stored != null && stored.isNotEmpty) {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            headers[key.toString()] = value.toString();
          });
        }
      }
      final timeoutMs = (server['timeout_ms'] as num?)?.toInt() ?? 20000;
      final client = McpClient(
        url: url,
        headers: headers,
        timeout: Duration(milliseconds: timeoutMs),
      );
      try {
        await client.initialize();
        final tools = await client.listTools();
        final resources = await client.listResourcesSafe();
        final prompts = await client.listPromptsSafe();
        await DBManager().saveMcpTools(id, tools);
        await DBManager().saveMcpMetadata(
          id,
          resources: resources,
          prompts: prompts,
        );
      } finally {
        try {
          await client.close();
        } finally {
          client.dispose();
        }
      }
    } catch (error) {
      await DBManager().updateMcpStatus(
        id,
        'error',
        McpClient.describeError(error),
      );
    }
  }
}
