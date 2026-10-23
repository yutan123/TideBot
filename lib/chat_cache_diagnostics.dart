import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Sort object keys, but preserve array order (messages, image parts and enums).
/// Tool order has no execution meaning and is sorted separately by name.
Object? canonicalChatValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonicalChatValue(value[key])};
  }
  if (value is List) return value.map(canonicalChatValue).toList();
  return value;
}

Map<String, dynamic> prepareChatCompletionPayload(
    Map<String, dynamic> payload) {
  final prepared = Map<String, dynamic>.from(payload);
  final tools = prepared['tools'];
  if (tools is List) {
    prepared['tools'] = List<Object?>.from(tools)
      ..sort((a, b) {
        String name(Object? tool) {
          if (tool is! Map) return '';
          final function = tool['function'];
          return function is Map ? function['name']?.toString() ?? '' : '';
        }

        return name(a).compareTo(name(b));
      });
  }
  return Map<String, dynamic>.from(canonicalChatValue(prepared) as Map);
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
int _commonPrefix(String a, String b) {
  var i = 0;
  while (i < a.length && i < b.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

/// Compares the actual outgoing protocol, including EVERY system message and
/// tool field. No prompt text, image data or credentials are emitted in reports.
/// Scope initial requests by endpoint/bot/provider/model/task, so a background
/// diary or a tool follow-up cannot replace the last normal-chat comparison.
class ChatCacheDiagnostics {
  ChatCacheDiagnostics({this.maxEntries = 16, this.maxSnapshotChars = 500000});
  final int maxEntries;
  final int maxSnapshotChars;
  final _snapshots = <String, _RequestSnapshot>{};

  void clear() => _snapshots.clear();

  Map<String, dynamic> record({
    required String scope,
    required String requestId,
    required Map<String, dynamic> payload,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    final previous = _snapshots.remove(scope);
    final messages = (payload['messages'] as List? ?? const [])
        .map((m) => jsonEncode(m))
        .toList();
    final roles = (payload['messages'] as List? ?? const [])
        .map((m) => m is Map ? m['role']?.toString() : null)
        .toList();
    final tools = <String, String>{};
    for (final tool in (payload['tools'] as List? ?? const [])) {
      if (tool is Map) {
        final name = (tool['function'] as Map?)?['name']?.toString() ?? '';
        tools[name] = _digest(jsonEncode(tool));
      }
    }
    final settings = Map<String, dynamic>.from(payload)
      ..remove('messages')
      ..remove('tools');
    final body = jsonEncode(payload);
    final messageBody = jsonEncode(payload['messages']);
    final toolBody = jsonEncode(payload['tools']);
    var commonMessages = 0;
    if (previous != null) {
      while (commonMessages < previous.messages.length &&
          commonMessages < messages.length &&
          previous.messages[commonMessages] == messages[commonMessages]) {
        commonMessages++;
      }
    }
    final changed = commonMessages;
    final hasChangedMessage = previous != null &&
        (changed < messages.length || changed < previous.messages.length);
    final names = {...?previous?.tools.keys, ...tools.keys}.toList()..sort();
    final report = <String, dynamic>{
      'request_id': requestId,
      'previous_request_id': previous?.requestId,
      'previous_request_available': previous != null,
      'seconds_since_previous': previous == null
          ? null
          : now.difference(previous.at).inMilliseconds / 1000,
      'payload_sha256': _digest(body),
      'messages_sha256': _digest(messageBody),
      'tools_sha256': _digest(toolBody),
      'message_count': messages.length,
      'message_roles': roles,
      'system_message_indices': [
        for (var i = 0; i < roles.length; i++)
          if (roles[i] == 'system') i,
      ],
      'common_full_messages': previous == null ? null : commonMessages,
      'common_message_json_prefix_chars': previous == null
          ? null
          : _commonPrefix(previous.messageBody, messageBody),
      'first_changed_message_index': hasChangedMessage ? changed : null,
      'first_changed_message_role':
          hasChangedMessage && changed < roles.length ? roles[changed] : null,
      'first_changed_message_previous_role':
          hasChangedMessage && changed < previous.roles.length
              ? previous.roles[changed]
              : null,
      'fixed_changed': previous == null
          ? null
          : (messages.isEmpty ? null : messages.first) !=
              (previous.messages.isEmpty ? null : previous.messages.first),
      'tools_changed': previous == null ? null : previous.toolBody != toolBody,
      'changed_tool_names': previous == null
          ? null
          : [
              for (final name in names)
                if (previous.tools[name] != tools[name]) name,
            ],
      'request_settings_changed':
          previous == null ? null : previous.settings != jsonEncode(settings),
      'snapshot_retained': body.length <= maxSnapshotChars && maxEntries > 0,
      'note': '比较实际发送的全部消息与工具；字符数不是缓存 token。相同前缀不保证上游缓存命中。',
    };
    if (body.length <= maxSnapshotChars && maxEntries > 0) {
      while (_snapshots.length >= maxEntries) {
        _snapshots.remove(_snapshots.keys.first);
      }
      _snapshots[scope] = _RequestSnapshot(requestId, now, messages, roles,
          messageBody, toolBody, tools, jsonEncode(settings));
    }
    return report;
  }
}

class _RequestSnapshot {
  const _RequestSnapshot(this.requestId, this.at, this.messages, this.roles,
      this.messageBody, this.toolBody, this.tools, this.settings);
  final String requestId;
  final DateTime at;
  final List<String> messages;
  final List<String?> roles;
  final String messageBody;
  final String toolBody;
  final Map<String, String> tools;
  final String settings;
}

/// Public response identity only; never collect arbitrary response headers.
Map<String, dynamic> cacheResponseMetadata(Map response) => {
      if (response['id'] != null) 'response_id': response['id'],
      if (response['model'] != null) 'returned_model': response['model'],
      if (response['system_fingerprint'] != null)
        'system_fingerprint': response['system_fingerprint'],
    };
