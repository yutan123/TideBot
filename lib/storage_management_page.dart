import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'full_backup_service.dart';
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
      _databaseSidecars = 0,
      _apk = 0,
      _appData = 0,
      _total = 0;
  List<MapEntry<String, int>> _documentItems = const [];
  Map<String, Object> _databaseInfo = const {};
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

  Future<int> _fileSize(File file) async {
    if (!await file.exists()) return 0;
    return file.length();
  }

  Future<List<MapEntry<String, int>>> _children(Directory dir) async {
    if (!await dir.exists()) return const [];
    final items = <MapEntry<String, int>>[];
    await for (final item in dir.list(followLinks: false)) {
      try {
        final bytes =
            item is File ? await item.length() : await _size(item as Directory);
        final name = item.path.split(Platform.pathSeparator).last;
        items.add(MapEntry(name, bytes));
      } catch (_) {}
    }
    items.sort((a, b) => b.value.compareTo(a.value));
    return items;
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
    final dbWal = File('$dbPath/tidebot.db-wal');
    final dbShm = File('$dbPath/tidebot.db-shm');
    final native = await OpsManager().storageInfo();
    final values = await Future.wait<dynamic>([
      _size(docs),
      _size(temp),
      _fileSize(dbFile),
      Future.wait<int>([
        _fileSize(dbWal),
        _fileSize(dbShm),
      ]).then((sizes) => sizes[0] + sizes[1]),
      _children(docs),
      DBManager().databaseDiagnostics(),
      DBManager().getAllBots(),
      DBManager().chatStorageByBot(),
    ]);
    if (!mounted) return;
    setState(() {
      _documents = values[0] as int;
      _temporary = values[1] as int;
      _database = values[2] as int;
      _databaseSidecars = values[3] as int;
      _documentItems = values[4] as List<MapEntry<String, int>>;
      _databaseInfo = values[5] as Map<String, Object>;
      _bots = values[6] as List<Map<String, dynamic>>;
      _chatBytes
        ..clear()
        ..addAll(values[7] as Map<String, int>);
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

  Future<void> _showDatabaseDiagnostics() async {
    final tables = _databaseInfo['tables'] as Map<String, int>? ?? const {};
    final rows = tables.entries
        .map(
            (entry) => '${entry.key}: ${entry.value < 0 ? '不可读' : entry.value}')
        .join('\n');
    await TideDialogs.show<void>(
      context: context,
      builder: (dialogContext) => TideDialogSurface(
        title: const Text('数据库诊断'),
        content: SelectableText(
          '路径\n${_databaseInfo['path'] ?? '不可用'}\n\n'
          'SQLite 版本: ${_databaseInfo['userVersion'] ?? '不可用'}\n\n'
          '记录数\n$rows',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
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

  Future<void> _backupAll() async {
    try {
      final exported = await FullBackupService.export();
      if (mounted && exported) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('完整备份已导出')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('备份失败：$error')));
      }
    }
  }

  Future<void> _restoreAll() async {
    final confirmed = await TideDialogs.show<bool>(
          context: context,
          builder: (dialogContext) => TideDialogSurface(
            title: const Text('恢复完整备份'),
            content: const Text('恢复会覆盖当前的设置、聊天记录、机器人、记忆和媒体文件。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('选择备份文件'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      final restored = await FullBackupService.restore();
      if (!restored) return;
      await _loadAsync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('完整备份已恢复，请重新打开页面以刷新运行中的服务')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复失败：$error')));
      }
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
                      _format(_database),
                      action: '诊断', onTap: _showDatabaseDiagnostics),
                  _row(Icons.sync_alt_rounded, '数据库日志（WAL/SHM）',
                      _format(_databaseSidecars)),
                  _row(Icons.folder_outlined, '应用文件', _format(_documents)),
                  _row(Icons.cached_rounded, '可清理缓存', _format(_temporary),
                      action: '清理', onTap: _clearCache)
                ])),
                const SizedBox(height: 12),
                FrostCard(
                    child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('备份所有数据',
                        style: TextStyle(fontFamily: 'TideFont')),
                    subtitle: const Text('导出设置、聊天记录、机器人、记忆和媒体文件',
                        style: TextStyle(fontFamily: 'TideFont', fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _backupAll,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.restore_rounded),
                    title: const Text('恢复所有数据',
                        style: TextStyle(fontFamily: 'TideFont')),
                    subtitle: const Text('导入完整备份并覆盖当前所有数据',
                        style: TextStyle(fontFamily: 'TideFont', fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _restoreAll,
                  ),
                ])),
                const SizedBox(height: 12),
                FrostCard(
                    child: Column(children: [
                  const ListTile(
                    leading: Icon(Icons.folder_open_outlined),
                    title: Text('应用文件明细',
                        style: TextStyle(fontFamily: 'TideFont')),
                    subtitle: Text('图片、录音、背景、表情包、导出和日志',
                        style: TextStyle(fontFamily: 'TideFont', fontSize: 12)),
                  ),
                  for (final item in _documentItems)
                    _row(Icons.insert_drive_file_outlined, item.key,
                        _format(item.value)),
                  if (_documentItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无应用文件', textAlign: TextAlign.start),
                    ),
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
