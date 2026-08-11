import 'package:flutter/material.dart';

import 'life_schedule_service.dart';
import 'theme.dart';

class LifeSchedulePoolPage extends StatefulWidget {
  final Map<String, List<String>> initialPools;
  const LifeSchedulePoolPage({super.key, required this.initialPools});

  @override
  State<LifeSchedulePoolPage> createState() => _LifeSchedulePoolPageState();
}

class _LifeSchedulePoolPageState extends State<LifeSchedulePoolPage> {
  late final Map<String, List<String>> _pools;
  static const _labels = <String, String>{
    'themes': '主题池',
    'moods': '心情池',
    'outfits': '穿搭池',
    'types': '日程池',
  };

  @override
  void initState() {
    super.initState();
    _pools =
        widget.initialPools.map((k, v) => MapEntry(k, List<String>.from(v)));
  }

  Future<void> _add(String key) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加${_labels[key]}',
            style: const TextStyle(fontFamily: 'TideFont')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入内容'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('添加')),
        ],
      ),
    );
    if (value == null || value.isEmpty || _pools[key]!.contains(value)) return;
    setState(() => _pools[key]!.add(value));
    await LifeScheduleService.instance.savePools(_pools);
  }

  Future<void> _remove(String key, String value) async {
    setState(() => _pools[key]!.remove(value));
    await LifeScheduleService.instance.savePools(_pools);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('管理日程池', style: TextStyle(fontFamily: 'TideFont')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: _labels.entries.map((entry) {
          final values = _pools[entry.key] ?? const <String>[];
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(entry.value,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: theme.textStrong,
                              fontFamily: 'TideFont'))),
                  IconButton(
                    tooltip: '添加',
                    onPressed: () => _add(entry.key),
                    icon: Icon(Icons.add_rounded, color: theme.primary),
                  ),
                ]),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: values
                      .map((value) => InputChip(
                            label: Text(value,
                                style: const TextStyle(fontFamily: 'TideFont')),
                            onDeleted: () => _remove(entry.key, value),
                          ))
                      .toList(),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
