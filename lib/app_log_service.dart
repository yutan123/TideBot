import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLogEntry {
  final DateTime time;
  final String level;
  final String message;

  const AppLogEntry(this.time, this.level, this.message);

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'level': level,
        'message': message,
      };

  factory AppLogEntry.fromJson(Map value) => AppLogEntry(
        DateTime.tryParse(value['time']?.toString() ?? '') ?? DateTime.now(),
        value['level']?.toString() ?? 'INFO',
        value['message']?.toString() ?? '',
      );
}

class AppLogService {
  AppLogService._();
  static final instance = AppLogService._();

  final entries = <AppLogEntry>[];
  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> restoreForLaunch() async {
    // Logging is intentionally session-only. A previous session must never
    // re-enable it when the app is launched again.
    _enabled = false;
    await (await SharedPreferences.getInstance())
        .setBool('dev_log_enabled', false);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (value) entries.clear();
    await (await SharedPreferences.getInstance())
        .setBool('dev_log_enabled', value);
    if (value) add('INFO', '实时日志已开启');
  }

  void add(String level, String message) {
    final line = AppLogEntry(DateTime.now(), level, message);
    if (_enabled) {
      entries.add(line);
      if (entries.length > 1000) entries.removeRange(0, entries.length - 1000);
    }
  }

  Future<File> _historyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/tidebot_dev_logs.json');
  }

  Future<void> saveCurrent() async {
    if (entries.isEmpty) return;
    final file = await _historyFile();
    final old = await history();
    final all = [...old, ...entries];
    await file.writeAsString(jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<List<AppLogEntry>> history() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      return raw is List
          ? raw.whereType<Map>().map(AppLogEntry.fromJson).toList()
          : [];
    } catch (_) {
      return [];
    }
  }
}
