import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key});

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  bool _loading = true;
  int _database = 0;
  List<Map<String, dynamic>> _bots = const [];
  final Map<String, int> _chatBytes = {};
  final Set<String> _selected = {};

  String _format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _load() async {
    final path = await getDatabasesPath();
    final file = File('$path/tidebot.db');
    final values = await Future.wait<dynamic>([
      file.exists().then((exists) => exists ? file.length() : 0),
      DBManager().getAllBots().catchError((_) => <Map<String, dynamic>>[]),
      DBManager().chatStorageByBot().catchError((_) => <String, int>{}),
    ]);
    if (!mounted) return;
    setState(() {
      _database = values[0] as int;
      _bots = values[1] as List<Map<String, dynamic>>;
      _chatBytes
        ..clear()
        ..addAll(values[2] as Map<String, int>);
      _selected.removeWhere(
        (id) => !_bots.any((bot) => bot['id']?.toString() == id),
      );
      _loading = false;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final approved = await TideDialogs.show<bool>(
          context: context,
          builder: (dialogContext) => TideDialogSurface(
            title: const Text('删除聊天记录'),
            content: Text('将删除 ${_selected.length} 个机器人的全部聊天记录，此操作无法撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved) return;
    for (final id in _selected) {
      await DBManager().clearChatHistory(id);
    }
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('聊天记录已删除')));
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final selectedBytes = _selected.fold<int>(
      0,
      (total, id) => total + (_chatBytes[id] ?? 0),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('聊天数据库', style: TextStyle(color: theme.onBackgroundStrong)),
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                FrostCard(
                  child: Row(
                    children: [
                      Icon(Icons.storage_rounded, color: theme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '聊天数据库 ${_format(_database)}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: theme.textStrong,
                            fontFamily: 'TideFont',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '选择要删除聊天记录的机器人',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.onBackgroundStrong,
                    fontFamily: 'TideFont',
                  ),
                ),
                const SizedBox(height: 8),
                FrostCard(
                  padding: EdgeInsets.zero,
                  child: _bots.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('暂无机器人', textAlign: TextAlign.start),
                        )
                      : Column(
                          children: _bots.map((bot) {
                            final id = bot['id']?.toString() ?? '';
                            return CheckboxListTile(
                              value: _selected.contains(id),
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  _selected.add(id);
                                } else {
                                  _selected.remove(id);
                                }
                              }),
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                bot['name']?.toString() ?? '未命名机器人',
                                style: const TextStyle(fontFamily: 'TideFont'),
                              ),
                              subtitle: Text(
                                '聊天记录约 ${_format(_chatBytes[id] ?? 0)}',
                                style: const TextStyle(
                                  fontFamily: 'TideFont',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(
                    _selected.isEmpty
                        ? '选择机器人后删除聊天记录'
                        : '删除 ${_selected.length} 个机器人的聊天记录（${_format(selectedBytes)}）',
                    style: const TextStyle(fontFamily: 'TideFont'),
                  ),
                ),
              ],
            ),
    );
  }
}
