import 'package:flutter/material.dart';
import 'android_selection_menu.dart';
import 'db.dart';
import 'future_task_scheduler.dart';
import 'future_task_button.dart';
import 'global_notice.dart';
import 'theme.dart';
import 'ui_components.dart';

int _taskInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
DateTime _taskTime(Map<String, dynamic> task) =>
    DateTime.fromMillisecondsSinceEpoch(
        _taskInt(task['run_at'] ?? task['time']));
String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String _date(DateTime time) =>
    '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

/// Uses the existing task queue shared by the bot and native scheduler.
class FutureTasksPage extends StatefulWidget {
  const FutureTasksPage(
      {super.key, required this.botId, required this.botName});
  final String botId;
  final String botName;
  @override
  State<FutureTasksPage> createState() => _FutureTasksPageState();
}

class _FutureTasksPageState extends State<FutureTasksPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  bool _failed = false;
  String _filter = 'all';
  final _busy = <String>{};
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final tasks = List<Map<String, dynamic>>.of(
          await DBManager().querySchedules(widget.botId));
      tasks.sort((a, b) => _taskTime(a).compareTo(_taskTime(b)));
      if (mounted)
        setState(() {
          _tasks = tasks;
          _loading = false;
          _failed = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _failed = true;
        });
    }
  }

  Future<void> _edit([Map<String, dynamic>? task]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _FutureTaskEditor(
              botId: widget.botId,
              task: task,
            )));
    if (mounted) await _load();
  }

  Future<void> _delete(Map<String, dynamic> task) async {
    final id = task['id'].toString();
    if (_busy.contains(id)) return;
    final confirmed = await showTideDialog<bool>(
        context: context,
        builder: (ctx) {
          final theme = TideTheme.of(ctx);
          return TideDialogSurface(
              child: TideDialogs.glassContent(context: ctx, children: [
            Text('删除未来任务？',
                style: TextStyle(
                    color: theme.textStrong,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('“${task['title'] ?? '未命名任务'}”将被移除，不再按此安排执行。',
                style: TextStyle(color: theme.textWeak, height: 1.6)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                  child: FutureTaskButton(
                      color: theme.surfaceVariant,
                      foregroundColor: theme.textStrong,
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("保留"))),
              const SizedBox(width: 12),
              Expanded(
                  child: FutureTaskButton(
                      color: const Color(0xffd86872),
                      foregroundColor: Colors.white,
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text("删除"))),
            ]),
          ]));
        });
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(id));
    try {
      final database = await DBManager().database;
      final removed = await database.delete('schedule_tasks',
          where:
              "id = ? AND bot_id = ? AND COALESCE(status, 'pending') != 'running'",
          whereArgs: [id, widget.botId]);
      if (removed == 0) {
        await _load();
        GlobalNotice.show('任务正在执行，请结束后再操作');
        return;
      }
      await FutureTaskScheduler.cancel(id);
      await _load();
    } catch (_) {
      GlobalNotice.show('删除失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Widget _surface(TideTheme theme, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: theme.border.withValues(alpha: .16), width: .5)),
        child: AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: child),
      );

  Widget _card(TideTheme theme, Map<String, dynamic> task) {
    final time = _taskTime(task);
    final daily = task['frequency'] == 'daily';
    final status = task['status']?.toString() ?? 'pending';
    final running = status == 'running';
    final failed = status == 'failed';
    final retry = _taskInt(task['retry_at']);
    final color = failed ? const Color(0xffd86872) : theme.primary;
    final label = running
        ? '执行中'
        : failed
            ? '执行失败'
            : retry > 0
                ? '等待重试'
                : '待执行';
    final disabled = running || _busy.contains(task['id'].toString());
    final id = task['id'].toString();
    final expanded = _expanded.contains(id);
    final prompt = task['prompt']?.toString() ?? task['note']?.toString() ?? '';
    return _surface(
        theme,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_clock(time),
                style: TextStyle(
                    color: theme.textStrong,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.6)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    daily ? '每天 · 下次 ${_date(time)}' : '${_date(time)} · 仅一次',
                    style: TextStyle(color: theme.textWeak, fontSize: 11))),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 10),
          Text(task['title']?.toString() ?? '未命名任务',
              maxLines: expanded ? null : 2,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: TextStyle(
                  color: theme.textStrong,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.35)),
          if (prompt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(prompt,
                maxLines: expanded ? null : 2,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: TextStyle(
                    color: theme.textWeak, height: 1.45, fontSize: 12)),
          ],
          if (failed || retry > 0) ...[
            const SizedBox(height: 8),
            Text(
                failed
                    ? '执行未完成，可编辑时间后重新安排。'
                    : '下次尝试：${_date(DateTime.fromMillisecondsSinceEpoch(retry))} ${_clock(DateTime.fromMillisecondsSinceEpoch(retry))}',
                style: TextStyle(color: color, fontSize: 11, height: 1.4)),
          ],
          const SizedBox(height: 4),
          Row(children: [
            FutureTaskButton(
                foregroundColor: theme.textWeak,
                onPressed: () => setState(() {
                      if (expanded) {
                        _expanded.remove(id);
                      } else {
                        _expanded.add(id);
                      }
                    }),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(expanded ? '收起' : '详情',
                      style: const TextStyle(fontSize: 12)),
                  Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16),
                ])),
            const Spacer(),
            FutureTaskButton(
                foregroundColor: theme.primary,
                onPressed: disabled ? null : () => _edit(task),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_outlined, size: 15),
                  SizedBox(width: 5),
                  Text('编辑', style: TextStyle(fontSize: 12)),
                ])),
            FutureTaskButton(
                foregroundColor: theme.textWeak,
                onPressed: disabled ? null : () => _delete(task),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_outline_rounded, size: 16),
                  SizedBox(width: 5),
                  Text('删除', style: TextStyle(fontSize: 12)),
                ])),
          ]),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final tasks = _tasks
        .where((t) => _filter == 'all' || t['frequency'] == _filter)
        .toList();
    return TideBackground(
        child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          title: const Text('未来任务'),
          backgroundColor: Colors.transparent,
          leading: FutureTaskButton(
              tooltip: '返回',
              foregroundColor: theme.textStrong,
              onPressed: () => Navigator.maybePop(context),
              child: const Icon(Icons.arrow_back_rounded, size: 22)),
          actions: [
            FutureTaskButton(
                tooltip: '刷新',
                foregroundColor: theme.textWeak,
                onPressed: _load,
                child: const Icon(Icons.refresh_rounded, size: 22)),
            const SizedBox(width: 8)
          ]),
      floatingActionButton: DecoratedBox(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: theme.primary.withValues(alpha: .22),
                    blurRadius: 16,
                    offset: const Offset(0, 6))
              ]),
          child: FutureTaskButton(
              color: theme.primary,
              foregroundColor: Colors.white,
              onPressed: () => _edit(),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 20),
                SizedBox(width: 6),
                Text('添加任务',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ]))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: theme.primary,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      color:
                                          theme.primary.withValues(alpha: .1),
                                      borderRadius: BorderRadius.circular(14)),
                                  child: Icon(Icons.schedule_rounded,
                                      color: theme.primary, size: 22)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('${widget.botName} 的安排',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: theme.textStrong,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text('共 ${_tasks.length} 项 · 到时间后交给TA执行',
                                        style: TextStyle(
                                            color: theme.textWeak,
                                            fontSize: 12)),
                                  ])),
                            ])),
                    Row(children: [
                      for (final entry in const {
                        'all': '全部',
                        'daily': '每天',
                        'once': '仅一次'
                      }.entries)
                        Expanded(
                            child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: Semantics(
                                    selected: _filter == entry.key,
                                    child: FutureTaskButton(
                                        color: _filter == entry.key
                                            ? theme.primary
                                                .withValues(alpha: .12)
                                            : theme.surface,
                                        foregroundColor: _filter == entry.key
                                            ? theme.primary
                                            : theme.textWeak,
                                        onPressed: () =>
                                            setState(() => _filter = entry.key),
                                        child: Text(entry.value,
                                            style: const TextStyle(
                                                fontSize: 13)))))),
                    ]),
                    const SizedBox(height: 12),
                    if (_failed)
                      _surface(
                          theme,
                          Column(children: [
                            Text('暂时无法读取任务',
                                style: TextStyle(color: theme.textStrong)),
                            FutureTaskButton(
                                onPressed: _load,
                                child: Text('重新加载',
                                    style: TextStyle(color: theme.primary))),
                          ]))
                    else if (tasks.isEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 52),
                          child: Column(children: [
                            Icon(Icons.event_available_rounded,
                                size: 44, color: theme.textFaint),
                            const SizedBox(height: 16),
                            Text(_tasks.isEmpty ? '还没有未来任务' : '这里暂时没有任务',
                                style: TextStyle(
                                    color: theme.textStrong,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text('让TA安排一件事，或点击下方添加任务',
                                style: TextStyle(
                                    color: theme.textWeak, fontSize: 13)),
                          ]))
                    else
                      ...tasks.expand((task) =>
                          [_card(theme, task), const SizedBox(height: 12)]),
                  ]),
            ),
    ));
  }
}

class _FutureTaskEditor extends StatefulWidget {
  const _FutureTaskEditor({required this.botId, this.task});
  final String botId;
  final Map<String, dynamic>? task;
  @override
  State<_FutureTaskEditor> createState() => _FutureTaskEditorState();
}

class _FutureTaskEditorState extends State<_FutureTaskEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _prompt, _day, _time;
  late String _frequency;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final task = widget.task;
    final date = task == null
        ? DateTime.now().add(const Duration(hours: 1))
        : _taskTime(task);
    _title = TextEditingController(text: task?['title']?.toString() ?? '');
    _prompt = TextEditingController(
        text: task?['prompt']?.toString() ?? task?['note']?.toString() ?? '');
    _day = TextEditingController(text: _date(date));
    _time = TextEditingController(text: _clock(date));
    _frequency = task?['frequency'] == 'daily' ? 'daily' : 'once';
  }

  @override
  void dispose() {
    for (final controller in [_title, _prompt, _day, _time]) {
      controller.dispose();
    }
    super.dispose();
  }

  DateTime? _runAt() {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time.text.trim());
    if (match == null) return null;
    final h = int.parse(match[1]!), m = int.parse(match[2]!);
    if (h > 23 || m > 59) return null;
    final now = DateTime.now();
    DateTime day = now;
    if (_frequency == 'once') {
      final raw = _day.text.trim();
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return null;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null || _date(parsed) != raw) return null;
      day = parsed;
    }
    var run = DateTime(day.year, day.month, day.day, h, m);
    if (_frequency == 'daily' && !run.isAfter(now))
      run = DateTime(day.year, day.month, day.day + 1, h, m);
    return run.isAfter(now) ? run : null;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final run = _runAt();
    if (run == null) {
      GlobalNotice.show('请填写有效时间；一次任务须晚于当前时间');
      return;
    }
    setState(() => _saving = true);
    try {
      final db = DBManager();
      final old = widget.task;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = old?['id']?.toString() ?? 'task_${widget.botId}_$now';
      if (old != null) {
        final latest = await db.querySchedules(widget.botId);
        final found = latest.where((t) => t['id'] == id).toList();
        if (found.isEmpty || found.first['status'] == 'running') {
          GlobalNotice.show('任务已执行或正在执行，请返回刷新');
          return;
        }
      }
      final task = <String, dynamic>{
        'id': id,
        'bot_id': widget.botId,
        'title': _title.text.trim(),
        'prompt': _prompt.text.trim(),
        'note': _prompt.text.trim(),
        'time': old?['time'] ?? now,
        'run_at': run.millisecondsSinceEpoch,
        'frequency': _frequency,
        'status': 'pending',
        'is_done': 0,
        'attempts': 0,
        'last_error': null,
        'retry_at': null,
        'locked_at': null,
      };
      if (old == null) {
        await db.insertFutureTask(task);
      } else {
        final database = await db.database;
        final updated = await database.update('schedule_tasks', task,
            where:
                "id = ? AND bot_id = ? AND COALESCE(status, 'pending') != 'running'",
            whereArgs: [id, widget.botId]);
        if (updated == 0) {
          GlobalNotice.show('任务已执行或正在执行，请返回刷新');
          return;
        }
      }
      final scheduled = await FutureTaskScheduler.schedule(task);
      if (!mounted) return;
      Navigator.pop(context);
      GlobalNotice.show(scheduled ? '任务已安排' : '任务已保存，将由后台任务队列处理');
    } catch (_) {
      if (mounted) GlobalNotice.show('保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TideTheme theme, String label, TextEditingController controller,
      String hint,
      {int lines = 1}) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              color: theme.textWeak,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 9),
      TextFormField(
          controller: controller,
          contextMenuBuilder: androidTextContextMenu,
          minLines: lines,
          maxLines: lines == 1 ? 1 : 8,
          enabled: !_saving,
          cursorColor: theme.primary,
          style: TextStyle(color: theme.textStrong, height: 1.6),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '请填写$label' : null,
          decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: theme.textFaint, fontSize: 13),
              filled: true,
              fillColor: theme.surfaceVariant,
              border: border,
              enabledBorder: border,
              focusedBorder: border,
              errorBorder: border,
              focusedErrorBorder: border,
              disabledBorder: border,
              contentPadding: const EdgeInsets.all(16))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TideBackground(
        child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          title: Text(widget.task == null ? '添加未来任务' : '编辑未来任务'),
          backgroundColor: Colors.transparent,
          leading: FutureTaskButton(
              tooltip: '返回',
              foregroundColor: theme.textStrong,
              onPressed: () => Navigator.maybePop(context),
              child: const Icon(Icons.arrow_back_rounded, size: 22))),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text('在对的时间，记得做这件事',
                style: TextStyle(
                    color: theme.textStrong,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('把要求写清楚，机器人会在约定时间收到这段任务。',
                style: TextStyle(color: theme.textWeak, height: 1.6)),
            const SizedBox(height: 28),
            _field(theme, '任务名称', _title, '例如：早间天气预报'),
            const SizedBox(height: 22),
            _field(theme, '交给TA的任务', _prompt, '例如：查询杭州今天的天气，告诉我气温和出门建议。',
                lines: 4),
            const SizedBox(height: 24),
            Text('执行频率',
                style: TextStyle(
                    color: theme.textWeak,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, children: [
              for (final option in const {'once': '仅一次', 'daily': '每天'}.entries)
                Semantics(
                    selected: _frequency == option.key,
                    child: FutureTaskButton(
                        color: _frequency == option.key
                            ? theme.primary.withValues(alpha: .14)
                            : theme.surface,
                        foregroundColor: _frequency == option.key
                            ? theme.primary
                            : theme.textWeak,
                        onPressed: _saving
                            ? null
                            : () => setState(() => _frequency = option.key),
                        child: Text(option.value)))
            ]),
            const SizedBox(height: 22),
            if (_frequency == 'once') ...[
              _field(theme, '执行日期', _day, 'YYYY-MM-DD'),
              const SizedBox(height: 22)
            ],
            _field(theme, _frequency == 'daily' ? '每天执行时间' : '执行时间', _time,
                'HH:mm，例如 10:00'),
            const SizedBox(height: 12),
            Text('使用本地时间；每日任务从下一个该时刻开始执行。',
                style: TextStyle(
                    color: theme.textFaint, fontSize: 12, height: 1.5)),
            const SizedBox(height: 32),
            FutureTaskButton(
                color: theme.primary,
                foregroundColor: Colors.white,
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '保存任务')),
            const SizedBox(height: 24),
          ])),
    ));
  }
}
