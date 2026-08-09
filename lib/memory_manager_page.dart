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
  bool _loading = true;
  String get _label => _type == 'long'
      ? '长期记忆'
      : _type == 'medium'
          ? '中期记忆'
          : '短期记忆';
  IconData get _icon => _type == 'long'
      ? Icons.auto_awesome_rounded
      : _type == 'medium'
          ? Icons.bookmark_rounded
          : Icons.bolt_rounded;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
    final title = TextEditingController(text: item?['title']?.toString() ?? '');
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
                    controller: title,
                    decoration: decoration.copyWith(labelText: '标题（可选）')),
                const SizedBox(height: 12),
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
        'title': title.text.trim(),
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
    title.dispose();
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
          Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: accent.withValues(alpha: .25))),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(11),
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: Icon(_icon, color: Colors.white)),
                const SizedBox(width: 13),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_label,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: theme.textStrong,
                              fontFamily: 'TideFont')),
                      Text('${_items.length} 条已保存 · 点击卡片即可编辑',
                          style: TextStyle(
                              color: theme.textWeak,
                              fontSize: 12,
                              fontFamily: 'TideFont'))
                    ]))
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: 'long',
                        icon: Icon(Icons.auto_awesome_rounded),
                        label: Text('长期')),
                    ButtonSegment(
                        value: 'medium',
                        icon: Icon(Icons.bookmark_rounded),
                        label: Text('中期')),
                    ButtonSegment(
                        value: 'short',
                        icon: Icon(Icons.bolt_rounded),
                        label: Text('短期'))
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) {
                    setState(() {
                      _type = v.first;
                      _loading = true;
                    });
                    _load();
                  })),
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
                                final title =
                                    item['title']?.toString().trim() ?? '';
                                return InkWell(
                                    borderRadius: BorderRadius.circular(22),
                                    onTap: () => _edit(item),
                                    child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                            color: theme.surfaceVariant,
                                            borderRadius:
                                                BorderRadius.circular(22),
                                            border: Border.all(
                                                color: theme.border)),
                                        child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                  width: 4,
                                                  height: 54,
                                                  decoration: BoxDecoration(
                                                      color: accent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4))),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    Text(
                                                        title.isEmpty
                                                            ? _label
                                                            : title,
                                                        style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: theme
                                                                .textStrong,
                                                            fontFamily:
                                                                'TideFont')),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                        item['content']
                                                                ?.toString() ??
                                                            '',
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                            height: 1.45,
                                                            fontSize: 13,
                                                            color:
                                                                theme.textWeak,
                                                            fontFamily:
                                                                'TideFont')),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                        _date(
                                                            item['timestamp']),
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                theme.textFaint,
                                                            fontFamily:
                                                                'TideFont'))
                                                  ])),
                                              IconButton(
                                                  onPressed: () =>
                                                      _delete(item),
                                                  icon: Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                      size: 20,
                                                      color: theme.textFaint))
                                            ])));
                              })))
        ]));
  }
}
