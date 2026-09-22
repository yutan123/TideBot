import 'dart:ui';

import 'package:flutter/material.dart';

import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

class WorldBookDetailPage extends StatefulWidget {
  final String botId;
  final String botName;

  const WorldBookDetailPage({
    super.key,
    required this.botId,
    required this.botName,
  });

  @override
  State<WorldBookDetailPage> createState() => _WorldBookDetailPageState();
}

class _WorldBookDetailPageState extends State<WorldBookDetailPage> {
  final _db = DBManager();
  final _search = TextEditingController();
  Map<String, dynamic> _bot = {};
  List<Map<String, dynamic>> _entries = [];
  final Set<String> _open = {};

  static const _categories = ['自我认知', '用户认知', '关系', '记忆', '日程', '事件'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bot = await _db.getBotById(widget.botId);
    final entries = await _db.queryMemories(widget.botId);
    if (!mounted) return;
    setState(() {
      _bot = bot ?? {};
      _entries = entries;
    });
  }

  String _text(Map<String, dynamic> row, String key) =>
      row[key]?.toString().trim() ?? '';

  String _category(Map<String, dynamic> row) {
    final value = _text(row, 'category');
    return _categories.contains(value) ? value : '记忆';
  }

  List<Map<String, dynamic>> get _visible {
    final query = _search.text.trim();
    if (query.isEmpty) return _entries;
    return _entries.where((row) {
      return '${_text(row, 'title')} ${_text(row, 'content')} ${_category(row)}'
          .contains(query);
    }).toList();
  }

  Map<String, dynamic>? _firstOf(String category) {
    for (final row in _entries) {
      if (_category(row) == category && _text(row, 'content').isNotEmpty) {
        return row;
      }
    }
    return null;
  }

  Color _dot(String category, TideTheme theme) {
    switch (category) {
      case '自我认知':
        return const Color(0xFF5AC8FA);
      case '用户认知':
        return const Color(0xFF34C759);
      case '关系':
        return const Color(0xFFFF2D55);
      case '日程':
        return const Color(0xFFFF9500);
      case '事件':
        return const Color(0xFFAF52DE);
      default:
        return theme.primary;
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final title =
        TextEditingController(text: row == null ? '' : _text(row, 'title'));
    final content =
        TextEditingController(text: row == null ? '' : _text(row, 'content'));
    var category = row == null ? '记忆' : _category(row);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = TideTheme.of(context);
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: StatefulBuilder(builder: (context, setSheet) {
            return Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(row == null ? '添加条目' : '编辑条目',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: theme.textStrong)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: '标题'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '类别'),
                    items: [
                      for (final item in _categories)
                        DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: (value) =>
                        setSheet(() => category = value ?? category),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: content,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: '内容'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    const Spacer(),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('保存')),
                  ]),
                ],
              ),
            );
          }),
        );
      },
    );
    if (saved == true && content.text.trim().isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (row == null) {
        await _db.insertMemory({
          'id': 'mem_${widget.botId}_${now}_${content.text.hashCode.abs()}',
          'bot_id': widget.botId,
          'title': title.text.trim(),
          'type': 'long',
          'content': content.text.trim(),
          'category': category,
          'importance': 3,
          'timestamp': now,
          'updated_at': now,
        });
      } else {
        await _db.updateMemory(row['id'].toString(), {
          'title': title.text.trim(),
          'content': content.text.trim(),
          'category': category,
          'updated_at': now,
        });
      }
      await _load();
    }
    title.dispose();
    content.dispose();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记忆？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteMemory(row['id'].toString());
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final userView = _firstOf('用户认知');
    final selfView = _firstOf('自我认知');
    final relation = _firstOf('关系');
    final entries = _visible;
    return Scaffold(
      backgroundColor: theme.bgColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        backgroundColor: theme.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: theme.textStrong, size: 18),
              ),
              Text('世界书',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: theme.textStrong)),
            ]),
            const SizedBox(height: 8),
            _glass(
              theme,
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                TideBotAvatar(
                  name: _text(_bot, 'name').isEmpty
                      ? widget.botName
                      : _text(_bot, 'name'),
                  path: _text(_bot, 'avatar'),
                  size: 62,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(_bot, 'name').isEmpty
                            ? widget.botName
                            : _text(_bot, 'name'),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: theme.textStrong),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (_text(_bot, 'prompt').isNotEmpty)
                            _text(_bot, 'prompt'),
                          if (_text(_bot, 'desc').isNotEmpty)
                            _text(_bot, 'desc'),
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: theme.textWeak),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: _relationCard(theme, '机器人对用户',
                      userView == null ? '还没有记录' : _text(userView, 'content'))),
              SizedBox(
                width: 42,
                child: Column(children: [
                  Icon(Icons.favorite_rounded, color: theme.primary, size: 18),
                  const SizedBox(height: 4),
                  Text(relation == null ? '关系' : _text(relation, 'title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: theme.textFaint)),
                ]),
              ),
              Expanded(
                  child: _relationCard(theme, '用户对机器人',
                      selfView == null ? '还没有记录' : _text(selfView, 'content'))),
            ]),
            const SizedBox(height: 18),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索',
                filled: true,
                fillColor: theme.surfaceVariant.withValues(alpha: .72),
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Center(
                    child:
                        Text('暂无条目', style: TextStyle(color: theme.textWeak))),
              ),
            for (final row in entries) _entry(theme, row),
          ],
        ),
      ),
    );
  }

  Widget _relationCard(TideTheme theme, String title, String body) {
    return _glass(
      theme,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.textStrong)),
            const SizedBox(height: 8),
            Expanded(
              child: Text(body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, height: 1.4, color: theme.textWeak)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entry(TideTheme theme, Map<String, dynamic> row) {
    final id = row['id'].toString();
    final open = _open.contains(id);
    final category = _category(row);
    final content = _text(row, 'content');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _glass(
        theme,
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() => open ? _open.remove(id) : _open.add(id)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                    color: _dot(category, theme), shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _text(row, 'title').isEmpty
                            ? category
                            : _text(row, 'title'),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.textStrong)),
                    const SizedBox(height: 4),
                    Text(content.isEmpty ? '无内容' : content,
                        maxLines: open ? null : 1,
                        overflow: open ? null : TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: theme.textWeak)),
                  ],
                ),
              ),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _edit(row),
                  icon: Icon(Icons.edit_outlined,
                      size: 18, color: theme.textWeak)),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _delete(row),
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 18, color: theme.textWeak)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glass(TideTheme theme,
      {required Widget child, required EdgeInsets padding}) {
    final glass = theme.hasGlobalBackground;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter:
            ImageFilter.blur(sigmaX: glass ? 18 : 0, sigmaY: glass ? 18 : 0),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: glass
                ? theme.glass.withValues(alpha: theme.isDark ? .42 : .55)
                : theme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: theme.border.withValues(alpha: glass ? .35 : .8)),
          ),
          child: child,
        ),
      ),
    );
  }
}
