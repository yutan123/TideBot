import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'db.dart';
import 'ops.dart';
import 'theme.dart';
import 'ui_components.dart';

class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key});
  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  bool _loading = true;
  int _documents = 0,
      _temporary = 0,
      _database = 0,
      _apk = 0,
      _appData = 0,
      _total = 0;
  List<Map<String, dynamic>> _bots = [];
  final Map<String, int> _chatBytes = {};
  final Set<String> _selected = {};

  Future<int> _size(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final item in dir.list(recursive: true, followLinks: false)) {
      if (item is File) {
        try {
          total += await item.length();
        } catch (_) {}
      }
    }
    return total;
  }

  String _format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  Future<void> _loadAsync() async {
    final docs = await getApplicationDocumentsDirectory();
    final temp = await getTemporaryDirectory();
    final dbPath = await getDatabasesPath();
    final dbFile = File('$dbPath/tidebot.db');
    final native = await OpsManager().storageInfo();
    final values = await Future.wait<dynamic>([
      _size(docs),
      _size(temp),
      dbFile.exists().then((yes) => yes ? dbFile.length() : 0),
      DBManager().getAllBots(),
      DBManager().chatStorageByBot(),
    ]);
    if (!mounted) return;
    setState(() {
      _documents = values[0] as int;
      _temporary = values[1] as int;
      _database = values[2] as int;
      _bots = values[3] as List<Map<String, dynamic>>;
      _chatBytes
        ..clear()
        ..addAll(values[4] as Map<String, int>);
      _total = (native['total'] as num?)?.toInt() ?? 0;
      _apk = (native['apk'] as num?)?.toInt() ?? 0;
      _appData = (native['data'] as num?)?.toInt() ??
          (_documents + _temporary + _database);
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadAsync();
  }

  Future<void> _clearCache() async {
    final temp = await getTemporaryDirectory();
    if (await temp.exists()) {
      await for (final item in temp.list(followLinks: false)) {
        try {
          await item.delete(recursive: true);
        } catch (_) {}
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('缓存已清理')));
      _loadAsync();
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    for (final id in _selected) {
      await DBManager().clearChatHistory(id);
    }
    if (mounted) {
      setState(_selected.clear);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清理所选机器人的聊天记录')));
      _loadAsync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final used = _apk + _appData;
    final pct =
        _total == 0 ? '—' : '${(used / _total * 100).toStringAsFixed(3)}%';
    return Scaffold(
        backgroundColor: theme.bgColor,
        appBar: AppBar(
            title: const Text('存储空间', style: TextStyle(fontFamily: 'TideFont')),
            backgroundColor: Colors.transparent,
            elevation: 0),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: theme.primary))
            : ListView(padding: const EdgeInsets.all(16), children: [
                FrostCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('TideBot 已用 ${_format(used)}',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: theme.textStrong,
                              fontFamily: 'TideFont')),
                      const SizedBox(height: 6),
                      Text('占设备总存储 $pct${_total == 0 ? '（设备总容量不可用）' : ''}',
                          style: TextStyle(
                              color: theme.textWeak, fontFamily: 'TideFont'))
                    ])),
                const SizedBox(height: 16),
                FrostCard(
                    child: Column(children: [
                  _row(Icons.install_mobile_rounded, '安装包', _format(_apk)),
                  _row(Icons.data_object_rounded, '应用数据', _format(_appData)),
                  _row(Icons.storage_rounded, '聊天数据库（已含于应用数据）',
                      _format(_database)),
                  _row(Icons.cached_rounded, '可清理缓存', _format(_temporary),
                      action: '清理', onTap: _clearCache)
                ])),
                const SizedBox(height: 22),
                Text('聊天记录管理',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: theme.textStrong,
                        fontFamily: 'TideFont')),
                const SizedBox(height: 8),
                FrostCard(
                    child: Column(children: [
                  for (final bot in _bots)
                    CheckboxListTile(
                        value: _selected.contains(bot['id']),
                        onChanged: (v) => setState(() {
                              if (v == true)
                                _selected.add(bot['id'].toString());
                              else
                                _selected.remove(bot['id'].toString());
                            }),
                        title: Text(bot['name']?.toString() ?? '未命名机器人',
                            style: const TextStyle(fontFamily: 'TideFont')),
                        subtitle: Text(
                            '聊天记录约 ${_format(_chatBytes[bot['id']?.toString() ?? ''] ?? 0)}',
                            style: const TextStyle(fontFamily: 'TideFont')),
                        controlAffinity: ListTileControlAffinity.leading),
                  if (_bots.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('暂无机器人', textAlign: TextAlign.start))
                ])),
                const SizedBox(height: 12),
                FilledButton.icon(
                    onPressed: _selected.isEmpty ? null : _deleteSelected,
                    icon: const Icon(Icons.delete_outline),
                    label: Text('清理已选 ${_selected.length} 个机器人的聊天记录',
                        style: const TextStyle(fontFamily: 'TideFont'))),
              ]));
  }

  Widget _row(IconData icon, String title, String value,
          {String? action, VoidCallback? onTap}) =>
      ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontFamily: 'TideFont')),
          subtitle: Text(value, style: const TextStyle(fontFamily: 'TideFont')),
          trailing: action == null
              ? null
              : TextButton(
                  onPressed: onTap,
                  child: Text(action,
                      style: const TextStyle(fontFamily: 'TideFont'))));
}
