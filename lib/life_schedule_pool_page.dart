import 'package:flutter/material.dart';

import 'life_schedule_service.dart';
import 'theme.dart';
import 'ui_components.dart';

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
    final value = await showTideSheet<String>(
      context: context,
      height: 300,
      child: Builder(builder: (sheetContext) {
        final theme = TideTheme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('添加${_labels[key]}',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: theme.textStrong,
                      fontFamily: 'TideFont')),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                autofocus: true,
                onSubmitted: (_) =>
                    Navigator.pop(context, controller.text.trim()),
                decoration: InputDecoration(
                  hintText: '输入内容',
                  hintStyle:
                      TextStyle(color: theme.textFaint, fontFamily: 'TideFont'),
                  filled: true,
                  fillColor: theme.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.primary, width: 1.4),
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: TideDialogs.glassButton(
                      '取消',
                      onTap: () => Navigator.pop(context),
                      color: theme.surfaceVariant,
                      textColor: theme.textStrong,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TideDialogs.glassButton(
                      '添加',
                      onTap: () =>
                          Navigator.pop(context, controller.text.trim()),
                      color: theme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
    controller.dispose();
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
                      .map((value) => Container(
                            padding: const EdgeInsets.only(
                                left: 12, right: 5, top: 7, bottom: 7),
                            decoration: BoxDecoration(
                              color: theme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                  color: theme.primary.withValues(alpha: 0.28)),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(value,
                                  style: TextStyle(
                                      color: theme.textStrong,
                                      fontFamily: 'TideFont')),
                              const SizedBox(width: 5),
                              GestureDetector(
                                onTap: () => _remove(entry.key, value),
                                child: Icon(Icons.close_rounded,
                                    size: 16, color: theme.primary),
                              ),
                            ]),
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
