import 'package:flutter/material.dart';
import 'db.dart';
import 'future_task_scheduler.dart';
import 'theme.dart';
import 'ui_components.dart';
import 'global_notice.dart';

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
  String _frequency = 'daily';
  // Future tasks use an explicit, editable YYYY-MM-DD HH:mm input.
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

  /* Legacy date/time picker implementation retained below temporarily.
  Future<DateTime?> _pickDate(BuildContext ctx) async {
    final theme = TideTheme.of(ctx);
    var year = _taskDate?.year ?? DateTime.now().year;
    var month = _taskDate?.month ?? DateTime.now().month;
    var day = _taskDate?.day ?? DateTime.now().day;
    return await showTideSheet<DateTime>(
      context: ctx,
      height: 440,
      child: StatefulBuilder(builder: (ctx, setDialog) {
        final daysInMonth = DateTime(year, month + 1, 0).day;
        final firstWeekday = DateTime(year, month, 1).weekday;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          children: [
            const Text('选择日期',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    fontFamily: 'TideFont')),
            const SizedBox(height: 6),
            // 年月步进
            Row(children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => setDialog(() {
                        if (month == 1) {
                          month = 12;
                          year--;
                        } else {
                          month--;
                        }
                        if (day > DateTime(year, month + 1, 0).day) {
                          day = DateTime(year, month + 1, 0).day;
                        }
                      })),
              Expanded(
                  child: Center(
                      child: Text('$year 年 $month 月',
                          style: TextStyle(
                              color: theme.textStrong,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'TideFont')))),
              IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => setDialog(() {
                        if (month == 12) {
                          month = 1;
                          year++;
                        } else {
                          month++;
                        }
                        if (day > DateTime(year, month + 1, 0).day) {
                          day = DateTime(year, month + 1, 0).day;
                        }
                      })),
            ]),
            const SizedBox(height: 4),
            // 星期表头
            Row(children: [
              for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                    child: Center(
                        child: Text(w,
                            style: TextStyle(
                                color: theme.textWeak,
                                fontSize: 12,
                                fontFamily: 'TideFont')))),
            ]),
            const SizedBox(height: 6),
            // 日期网格（7 列）
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                for (var i = 0; i < firstWeekday - 1; i++) const SizedBox(),
                for (var d = 1; d <= daysInMonth; d++)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, DateTime(year, month, d)),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: d == day ? theme.primary : theme.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Text('$d',
                          style: TextStyle(
                              color: d == day ? Colors.white : theme.textStrong,
                              fontFamily: 'TideFont')),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TideDialogs.glassButton('确定',
                onTap: () => Navigator.pop(ctx, DateTime(year, month, day))),
          ],
        );
      }),
    );
  }

  /// 自定义时间选择器（避免使用系统原生 showTimePicker）。
  /// 用小时/分钟网格选择。
  Future<TimeOfDay?> _pickTime(BuildContext ctx) async {
    final theme = TideTheme.of(ctx);
    var hour = _taskTime?.hour ?? DateTime.now().hour;
    var minute = _taskTime?.minute ?? 0;
    return await showTideSheet<TimeOfDay>(
      context: ctx,
      height: 440,
      child: StatefulBuilder(builder: (ctx, setDialog) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          children: [
            const Text('选择时间',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    fontFamily: 'TideFont')),
            const SizedBox(height: 8),
            Text(
                '${hour.toString().padLeft(2, '0')} : ${minute.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: theme.primary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'TideFont')),
            const SizedBox(height: 10),
            const Text('小时',
                style: TextStyle(
                    color: Colors.grey, fontSize: 12, fontFamily: 'TideFont')),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var h = 0; h < 24; h++)
                  GestureDetector(
                    onTap: () => setDialog(() => hour = h),
                    child: Container(
                      width: 40,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: h == hour ? theme.primary : theme.surfaceVariant,
                      ),
                      child: Text('$h',
                          style: TextStyle(
                              color:
                                  h == hour ? Colors.white : theme.textStrong,
                              fontFamily: 'TideFont')),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('分钟',
                style: TextStyle(
                    color: Colors.grey, fontSize: 12, fontFamily: 'TideFont')),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var m = 0; m < 60; m += 5)
                  GestureDetector(
                    onTap: () => setDialog(() => minute = m),
                    child: Container(
                      width: 44,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color:
                            m == minute ? theme.primary : theme.surfaceVariant,
                      ),
                      child: Text('$m',
                          style: TextStyle(
                              color:
                                  m == minute ? Colors.white : theme.textStrong,
                              fontSize: 13,
                              fontFamily: 'TideFont')),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TideDialogs.glassButton('确定',
                onTap: () =>
                    Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute))),
          ],
        );
      }),
    );
  }
  */

  Future<void> _edit([Map<String, dynamic>? item]) async {
    if (_type == 'future') {
      final title =
          TextEditingController(text: item?['title']?.toString() ?? '');
      final prompt = TextEditingController(
          text: item?['prompt']?.toString() ?? item?['note']?.toString() ?? '');
      final runAt = (item?['run_at'] as num?)?.toInt() ??
          (item?['time'] as num?)?.toInt() ??
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final runAtLocal = DateTime.fromMillisecondsSinceEpoch(runAt).toLocal();
      // 频率分离：每天只填时间，一次填日期 + 时间两个框。
      final dateText = TextEditingController(
          text: '${runAtLocal.year.toString().padLeft(4, '0')}-'
              '${runAtLocal.month.toString().padLeft(2, '0')}-'
              '${runAtLocal.day.toString().padLeft(2, '0')}');
      final timeText = TextEditingController(
          text: '${runAtLocal.hour.toString().padLeft(2, '0')}:'
              '${runAtLocal.minute.toString().padLeft(2, '0')}');
      _frequency = item?['frequency']?.toString() ?? 'once';
      final ok = await TideDialogs.show<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
              builder: (ctx, setDialog) => Center(
                  child: Material(
                      type: MaterialType.transparency,
                      child: TideDialogs.glassContent(context: ctx, children: [
                        Text(item == null ? '添加未来任务' : '编辑未来任务',
                            style: const TextStyle(
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
                        const SizedBox(height: 10),
                        // 自定义频率选择器（非系统原生）
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('执行频率',
                                style: TextStyle(fontFamily: 'TideFont')),
                            trailing: Text(_frequency == 'daily' ? '每天' : '一次',
                                style: TextStyle(
                                    color: TideTheme.of(ctx).primary,
                                    fontFamily: 'TideFont')),
                            onTap: () async {
                              final picked = await showTideSheet<String>(
                                context: ctx,
                                height: 320,
                                child: ListView(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 10, 16, 20),
                                  children: [
                                    const Text('选择执行频率',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 18,
                                            fontFamily: 'TideFont')),
                                    const SizedBox(height: 8),
                                    for (final opt in const [
                                      ('daily', '每天'),
                                      ('once', '一次')
                                    ])
                                      ListTile(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                        title: Text(opt.$2,
                                            style: const TextStyle(
                                                fontFamily: 'TideFont')),
                                        trailing: _frequency == opt.$1
                                            ? Icon(Icons.check_rounded,
                                                color:
                                                    TideTheme.of(ctx).primary)
                                            : null,
                                        onTap: () => Navigator.pop(ctx, opt.$1),
                                      ),
                                  ],
                                ),
                              );
                              if (picked != null)
                                setDialog(() => _frequency = picked);
                            }),
                        // 动态表单：每天只填时间；一次显示日期 + 时间两个独立输入框。
                        if (_frequency == 'daily')
                          TextField(
                              controller: timeText,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: '每天执行时间',
                                hintText: 'HH:mm',
                              ))
                        else ...[
                          TextField(
                              controller: dateText,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: '执行日期',
                                hintText: 'YYYY-MM-DD',
                              )),
                          const SizedBox(height: 10),
                          TextField(
                              controller: timeText,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: '执行时间',
                                hintText: 'HH:mm',
                              )),
                        ],
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
        final t = timeText.text.trim();
        DateTime? parsedRunAt;
        if (_frequency == 'daily') {
          // 每天：把 HH:mm 拼到今天（仅用于校验合法且时刻有效），实际按每日触发。
          parsedRunAt = DateTime.tryParse(
              '${DateTime.now().toString().substring(0, 10)}T$t');
        } else {
          parsedRunAt = DateTime.tryParse(
              '${dateText.text.trim()}T$t'.replaceFirst(' ', 'T'));
        }
        if (parsedRunAt == null ||
            (_frequency != 'daily' &&
                parsedRunAt.millisecondsSinceEpoch <=
                    DateTime.now().millisecondsSinceEpoch)) {
          if (mounted) {
            GlobalNotice.show(
                _frequency == 'daily'
                    ? '请输入有效的 HH:mm 时间'
                    : '请输入当前时间之后的日期和 HH:mm 时间',
                color: const Color(0xFFE74C3C));
          }
          title.dispose();
          prompt.dispose();
          dateText.dispose();
          timeText.dispose();
          return;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        // 每日任务把 run_at 归一为「今天该时刻」的时间戳；每天任务在第二天零点后顺延。
        final effectiveRunAt = _frequency == 'daily' &&
                parsedRunAt.millisecondsSinceEpoch <=
                    DateTime.now().millisecondsSinceEpoch
            ? parsedRunAt.add(const Duration(days: 1)).millisecondsSinceEpoch
            : parsedRunAt.millisecondsSinceEpoch;
        final task = {
          'id': item?['id'] ?? 'task_$now',
          'bot_id': widget.botId,
          'title': title.text.trim().isEmpty ? '未来任务' : title.text.trim(),
          'note': prompt.text.trim(),
          'prompt': prompt.text.trim(),
          'time': now,
          'run_at': effectiveRunAt,
          'frequency': _frequency,
          'is_done': 0,
          'status': 'pending'
        };
        await DBManager().insertFutureTask(task);
        if (!await FutureTaskScheduler.schedule(task)) {
          GlobalNotice.show('系统定时唤醒不可用，将由后台任务队列继续处理');
        }
        await _load();
      }
      title.dispose();
      prompt.dispose();
      dateText.dispose();
      timeText.dispose();
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
        await FutureTaskScheduler.cancel(item['id'].toString());
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
        : _type == 'short'
            ? const Color(0xFFF09B5D)
            : const Color(0xFF8B7CF6);
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
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
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _type == 'future'
                                                ? (item['title']?.toString() ??
                                                    '未来任务')
                                                : item['content']?.toString() ??
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
                                      icon: Icon(Icons.delete_outline_rounded,
                                          size: 19, color: theme.textFaint),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }))
        ]),
      ),
    );
  }
}
