import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLogEntry {
  final DateTime time;
  final String level;
  final String message;
  const AppLogEntry(this.time, this.level, this.message);
  Map<String, dynamic> toJson() =>
      {'time': time.toIso8601String(), 'level': level, 'message': message};
  factory AppLogEntry.fromJson(Map value) => AppLogEntry(
      DateTime.tryParse(value['time']?.toString() ?? '') ?? DateTime.now(),
      value['level']?.toString() ?? 'INFO',
      value['message']?.toString() ?? '');
}

class AppLogSession {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<AppLogEntry> entries;
  const AppLogSession(
      {required this.id,
      required this.startedAt,
      required this.endedAt,
      required this.entries});
  bool get hasError =>
      entries.any((e) => e.level.toUpperCase().contains('ERROR'));
  Map<String, dynamic> toJson() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'entries': entries.map((e) => e.toJson()).toList()
      };
  factory AppLogSession.fromJson(Map value) {
    final raw = value['entries'];
    return AppLogSession(
        id: value['id']?.toString() ??
            'log_${DateTime.now().millisecondsSinceEpoch}',
        startedAt: DateTime.tryParse(value['started_at']?.toString() ?? '') ??
            DateTime.now(),
        endedAt: DateTime.tryParse(value['ended_at']?.toString() ?? '') ??
            DateTime.now(),
        entries: raw is List
            ? raw.whereType<Map>().map(AppLogEntry.fromJson).toList()
            : const []);
  }
}

class AppLogService {
  AppLogService._();
  static final instance = AppLogService._();
  final entries = <AppLogEntry>[];
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  bool _enabled = false;
  DateTime? _startedAt;
  bool get enabled => _enabled;

  Future<void> restoreForLaunch() async {
    _enabled = false;
    _startedAt = null;
    entries.clear();
    await (await SharedPreferences.getInstance())
        .setBool('dev_log_enabled', false);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (value) {
      entries.clear();
      _startedAt = DateTime.now();
      add('INFO', '实时日志已开启');
    }
    await (await SharedPreferences.getInstance())
        .setBool('dev_log_enabled', value);
    revision.value++;
  }

  void add(String level, String message) {
    if (!_enabled) return;
    entries.add(AppLogEntry(DateTime.now(), level, _redact(message)));
    if (entries.length > 3000) entries.removeRange(0, entries.length - 3000);
    revision.value++;
  }

  void addJson(String level, String title, Object? value) => add(
      level, '$title\n${const JsonEncoder.withIndent('  ').convert(value)}');

  String _redact(String text) {
    var value = text
        .replaceAll(RegExp(r'Bearer\s+[^\s,}]+', caseSensitive: false),
            'Bearer [REDACTED]')
        .replaceAll(RegExp(r'"api_key"\s*:\s*"[^"]*"', caseSensitive: false),
            '"api_key":"[REDACTED]"');
    // Audio payloads are useful to identify in diagnostics but must never make
    // the live log unreadable. The duration is intentionally approximate.
    value = value.replaceAllMapped(
      RegExp(
          r'(?:data:audio/[^;,\s]+;base64,|"audio_base64"\s*:\s*")[A-Za-z0-9+/=_-]{128,}',
          caseSensitive: false),
      (match) {
        final payload = match.group(0)!;
        final seconds = (payload.length / 16000).ceil().clamp(1, 999);
        return '[语音] $seconds秒';
      },
    );
    return value;
  }

  Future<File> _historyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/tidebot_dev_logs.json');
  }

  Future<void> saveCurrent() async {
    if (entries.isEmpty) return;
    final all = await history();
    all.insert(
        0,
        AppLogSession(
            id: 'log_${(_startedAt ?? DateTime.now()).millisecondsSinceEpoch}',
            startedAt: _startedAt ?? entries.first.time,
            endedAt: DateTime.now(),
            entries: List<AppLogEntry>.from(entries)));
    await (await _historyFile())
        .writeAsString(jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<List<AppLogSession>> history() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is List &&
          raw.isNotEmpty &&
          raw.first is Map &&
          (raw.first as Map).containsKey('entries'))
        return raw.whereType<Map>().map(AppLogSession.fromJson).toList();
      if (raw is List) {
        final old = raw.whereType<Map>().map(AppLogEntry.fromJson).toList();
        return old.isEmpty
            ? []
            : [
                AppLogSession(
                    id: 'legacy',
                    startedAt: old.first.time,
                    endedAt: old.last.time,
                    entries: old)
              ];
      }
    } catch (_) {}
    return [];
  }

  Future<void> deleteSession(String id) async {
    final sessions = await history();
    sessions.removeWhere((s) => s.id == id);
    await (await _historyFile())
        .writeAsString(jsonEncode(sessions.map((e) => e.toJson()).toList()));
  }
}
