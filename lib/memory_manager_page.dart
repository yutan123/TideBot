import 'package:flutter/material.dart';
import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

class MemoryManagerPage extends StatefulWidget {
  final String botId;
  final String botName;
  const MemoryManagerPage(
      {super.key, required this.botId, required this.botName});
  @override
  State<MemoryManagerPage> createState() => _MemoryManagerPageState();
}

class _MemoryManagerPageState extends State<MemoryManagerPage> {
  List<Map<String, dynamic>> _items = [];
  String _type = 'long';
  String _frequency = 'once';
  DateTime? _taskDate;
  TimeOfDay? _taskTime;
  bool _loading = true;
  String get _label => _type == 'long'
      ? '长期记忆'
      : _type == 'short'
          ? '短期记忆'
          : '未来任务';
  IconData get _icon => _type == 'long'
      ? Icons.auto_awesome_rounded
      : _type == 'short'
          ? Icons.bolt_rounded
          : Icons.schedule_rounded;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_type == 'future') {
      final items = await DBManager().querySchedules(widget.botId);
      if (mounted)
        setState(() {
          _items = items;
          _loading = false;
        });
      return;
    }
    final items = await DBManager().queryMemories(widget.botId, type: _type);
    if (mounted)
      setState(() {
        _items = items;
        _loading = false;
      });
  }

  String _date(dynamic raw) {
    final ms = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    if (ms == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    if (_type == 'future' && item != null) {
      final task = item['prompt']?.toString() ?? item['note']?.toString() ?? '';
      await TideDialogs.show<void>(
          context: context,
          builder: (ctx) => Center(
              child: Material(
                  type: MaterialType.transparency,
                  child: TideDialogs.glassContent(context: ctx, children: [
                    Text(item['title']?.toString() ?? '未来任务',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'TideFont')),
                    const SizedBox(height: 12),
                    Text(task,
                        style: const TextStyle(
                            fontFamily: 'TideFont', height: 1.5)),
                    const SizedBox(height: 8),
                    Text('时间：${item['run_at'] ?? item['time'] ?? ''}',
                        style: const TextStyle(fontFamily: 'TideFont')),
                    const SizedBox(height: 14),
                    TideDialogs.glassButton('关闭',
                        onTap: () => Navigator.pop(ctx))
                  ]))));
      return;
    }
    if (_type == 'future') {
      final title =
          TextEditingController(text: item?['title']?.toString() ?? '');
      final prompt = TextEditingController(
          text: item?['prompt']?.toString() ?? item?['note']?.toString() ?? '');
      _frequency = 'once';
      _taskDate = DateTime.now();
      _taskTime = TimeOfDay.now();
      final ok = await TideDialogs.show<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
              builder: (ctx, setDialog) => Center(
                  child: Material(
                      type: MaterialType.transparency,
                      child: TideDialogs.glassContent(context: ctx, children: [
                        const Text('添加未来任务',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'TideFont')),
                        const SizedBox(height: 12),
                        TextField(
                            controller: title,
                            decoration: const InputDecoration(labelText: '标题')),
                        const SizedBox(height: 10),
                        TextField(
                            controller: prompt,
                            minLines: 3,
                            maxLines: 5,
                            decoration:
                                const InputDecoration(labelText: '给机器人的任务提示词')),
                        DropdownButton<String>(
                            value: _frequency,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                  value: 'daily', child: Text('每天')),
                              DropdownMenuItem(value: 'once', child: Text('一次'))
                            ],
                            onChanged: (v) {
                              if (v != null) setDialog(() => _frequency = v);
                            }),
                        if (_frequency == 'once')
                          ListTile(
                              title: Text(_taskDate == null
                                  ? '选择日期'
                                  : '${_taskDate!.year}-${_taskDate!.month}-${_taskDate!.day}'),
                              trailing: const Icon(Icons.calendar_today),
                              onTap: () async {
                                final d = await showDatePicker(
                                    context: ctx,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 3650)),
                                    initialDate: _taskDate ?? DateTime.now());
                                if (d != null) setDialog(() => _taskDate = d);
                              }),
                        ListTile(
                            title: Text(_taskTime == null
                                ? '选择时间'
                                : _taskTime!.format(ctx)),
                            trailing: const Icon(Icons.access_time),
                            onTap: () async {
                              final t = await showTimePicker(
                                  context: ctx,
                                  initialTime: _taskTime ?? TimeOfDay.now());
                              if (t != null) setDialog(() => _taskTime = t);
                            }),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                              child: TideDialogs.glassButton('取消',
                                  onTap: () => Navigator.pop(ctx))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: TideDialogs.glassButton('保存',
                                  onTap: () => Navigator.pop(ctx, true)))
                        ])
                      ])))));
      if (ok == true && prompt.text.trim().isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await DBManager().insertFutureTask({
          'id': item?['id'] ?? 'task_$now',
          'bot_id': widget.botId,
          'title': title.text.trim().isEmpty ? '未来任务' : title.text.trim(),
          'note': prompt.text.trim(),
          'prompt': prompt.text.trim(),
          'time': now,
          'run_at': ((_taskDate ?? DateTime.now()).copyWith(
                  hour: _taskTime?.hour ?? TimeOfDay.now().hour,
                  minute: _taskTime?.minute ?? TimeOfDay.now().minute))
              .millisecondsSinceEpoch,
          'frequency': _frequency,
          'is_done': 0,
          'status': 'pending'
        });
        await _load();
      }
      title.dispose();
      prompt.dispose();
      return;
    }
    final content =
        TextEditingController(text: item?['content']?.toString() ?? '');
    final ok = await TideDialogs.show<bool>(
        context: context,
        builder: (ctx) {
          final theme = TideTheme.of(ctx);
          final decoration = InputDecoration(
            filled: true,
            fillColor: theme.surfaceVariant,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
          );
          return Center(
            child: Material(
              type: MaterialType.transparency,
              child: TideDialogs.glassContent(context: ctx, children: [
                Text(item == null ? '添加$_label' : '编辑记忆',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'TideFont')),
                const SizedBox(height: 16),
                TextField(
                    controller: content,
                    minLines: 4,
                    maxLines: 7,
                    decoration: decoration.copyWith(
                        labelText: '记忆内容', alignLabelWithHint: true)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: TideDialogs.glassButton('取消',
                          color: theme.buttonSecondary,
                          textColor: theme.textStrong,
                          onTap: () => Navigator.pop(ctx))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TideDialogs.glassButton('保存',
                          onTap: () => Navigator.pop(ctx, true))),
                ]),
              ]),
            ),
          );
        });
    if (ok == true && content.text.trim().isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = {
        'title': '',
        'type': _type,
        'content': content.text.trim(),
        'timestamp': now
      };
      if (item == null)
        await DBManager().insertMemory(
            {'id': 'mem_$now', 'bot_id': widget.botId, ...values});
      else
        await DBManager().updateMemory(item['id'].toString(), values);
      await _load();
    }
    content.dispose();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await TideDialogs.show<bool>(
        context: context,
        builder: (ctx) {
          final theme = TideTheme.of(ctx);
          return Center(
            child: Material(
              type: MaterialType.transparency,
              child: TideDialogs.glassContent(context: ctx, children: [
                const Text('删除这条记忆？',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'TideFont')),
                const SizedBox(height: 8),
                Text('删除后无法恢复。',
                    style: TextStyle(
                        color: theme.textWeak, fontFamily: 'TideFont')),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: TideDialogs.glassButton('取消',
                          color: theme.buttonSecondary,
                          textColor: theme.textStrong,
                          onTap: () => Navigator.pop(ctx))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TideDialogs.glassButton('删除',
                          color: Colors.redAccent,
                          onTap: () => Navigator.pop(ctx, true))),
                ]),
              ]),
            ),
          );
        });
    if (ok == true) {
      if (_type == 'future') {
        await DBManager().deleteFutureTask(item['id'].toString());
        await _load();
        return;
      }
      await DBManager().deleteMemory(item['id'].toString());
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final accent = _type == 'long'
        ? theme.primary
        : _type == 'medium'
            ? const Color(0xFF8B7CF6)
            : const Color(0xFFF09B5D);
    return Scaffold(
        backgroundColor: theme.bgColor,
        appBar: AppBar(
            title: Text('${widget.botName} 的记忆',
                style: const TextStyle(fontFamily: 'TideFont')),
            actions: [
              IconButton(
                  onPressed: _loading ? null : () => _edit(),
                  icon: const Icon(Icons.add_rounded))
            ]),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                for (final entry in const <String, String>{
                  'long': '长期记忆',
                  'short': '短期记忆',
                  'future': '未来任务',
                }.entries) ...[
                  Expanded(
                    child: BouncyTap(
                      onTap: () {
                        if (_type == entry.key) return;
                        setState(() {
                          _type = entry.key;
                          _loading = true;
                        });
                        _load();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: _type == entry.key
                              ? accent
                              : theme.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(entry.value,
                              style: TextStyle(
                                  color: _type == entry.key
                                      ? Colors.white
                                      : theme.textWeak,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'TideFont')),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: accent))
                  : _items.isEmpty
                      ? Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_icon, size: 44, color: theme.textFaint),
                          const SizedBox(height: 12),
                          Text('还没有$_label',
                              style: TextStyle(
                                  fontFamily: 'TideFont',
                                  color: theme.textWeak)),
                          Text('把值得记住的事保存下来吧',
                              style: TextStyle(
                                  fontFamily: 'TideFont',
                                  color: theme.textFaint,
                                  fontSize: 12))
                        ]))
                      : RefreshIndicator(
                          color: accent,
                          onRefresh: _load,
                          child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 32),
                              itemCount: _items.length,
                              itemBuilder: (_, i) {
                                final item = _items[i];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _edit(item),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14, horizontal: 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _type == 'future'
                                                    ? (item['title']
                                                            ?.toString() ??
                                                        '未来任务')
                                                    : item['content']
                                                            ?.toString() ??
                                                        '',
                                                style: TextStyle(
                                                  height: 1.55,
                                                  fontSize: 15,
                                                  color: theme.textStrong,
                                                  fontFamily: 'TideFont',
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _date(item['timestamp']),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: theme.textFaint,
                                                  fontFamily: 'TideFont',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: '删除',
                                          onPressed: () => _delete(item),
                                          icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 19,
                                              color: theme.textFaint),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              })))
        ]));
  }
}
