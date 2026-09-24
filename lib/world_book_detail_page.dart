import 'dart:io';
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
  String _userName = '用户';
  String _userAvatar = '';
  bool _loading = true;
  final Set<String> _expanded = {};

  static const _categories = <String>[
    '自我认知',
    '用户认知',
    '关系',
    '人物',
    '地点',
    '规则',
    '事件',
    '偏好',
    '日程',
    '记忆',
  ];

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
    final results = await Future.wait<dynamic>([
      _db.getBotById(widget.botId),
      _db.queryMemories(widget.botId),
      _db.getKV('user_name'),
      _db.getKV('user_avatar'),
    ]);
    if (!mounted) return;
    setState(() {
      _bot = (results[0] as Map<String, dynamic>?) ?? {};
      _entries = List<Map<String, dynamic>>.from(results[1] as List);
      final name = results[2]?.toString().trim() ?? '';
      final avatar = results[3]?.toString().trim() ?? '';
      _userName = name.isEmpty ? '用户' : name;
      _userAvatar = avatar;
      _loading = false;
    });
  }

  String _text(Map<String, dynamic> row, String key) =>
      row[key]?.toString().trim() ?? '';

  String get _botName {
    final value = _text(_bot, 'name');
    return value.isEmpty ? widget.botName : value;
  }

  String _category(Map<String, dynamic> row) {
    final value = _text(row, 'category');
    return _categories.contains(value) ? value : '记忆';
  }

  List<Map<String, dynamic>> get _visibleEntries {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries.where((row) {
      final target = [
        _text(row, 'title'),
        _text(row, 'content'),
        _category(row),
      ].join(' ').toLowerCase();
      return target.contains(query);
    }).toList();
  }

  Map<String, dynamic>? _firstEntry(String category) {
    for (final row in _entries) {
      if (_category(row) == category && _text(row, 'content').isNotEmpty) {
        return row;
      }
    }
    return null;
  }

  String _profileSummary() {
    final values = <String>[
      if (_text(_bot, 'prompt').isNotEmpty) _text(_bot, 'prompt'),
      if (_text(_bot, 'desc').isNotEmpty) _text(_bot, 'desc'),
    ];
    return values.isEmpty ? '还没有填写说话方式和人设概述' : values.join(' · ');
  }

  Color _categoryColor(String category, TideTheme theme) {
    switch (category) {
      case '自我认知':
        return const Color(0xFF5AC8FA);
      case '用户认知':
        return const Color(0xFF34C759);
      case '关系':
        return const Color(0xFFFF2D55);
      case '人物':
        return const Color(0xFF5856D6);
      case '地点':
        return const Color(0xFF00A7A5);
      case '规则':
        return const Color(0xFFFF3B30);
      case '事件':
        return const Color(0xFFAF52DE);
      case '偏好':
        return const Color(0xFFFFCC00);
      case '日程':
        return const Color(0xFFFF9500);
      default:
        return theme.primary;
    }
  }

  String _summary(String content) {
    final compact = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 72) return compact;
    return '${compact.substring(0, 72)}…';
  }

  Future<void> _editEntry([Map<String, dynamic>? row]) async {
    final title = TextEditingController(
      text: row == null ? '' : _text(row, 'title'),
    );
    final content = TextEditingController(
      text: row == null ? '' : _text(row, 'content'),
    );
    var category = row == null ? '记忆' : _category(row);
    final saved = await showTideSheet<bool>(
      context: context,
      height: MediaQuery.sizeOf(context).height * .82,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          final theme = TideTheme.of(context);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 18,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row == null ? '添加世界书条目' : '编辑世界书条目',
                    style: TextStyle(
                      color: theme.textStrong,
                      fontFamily: 'TideFont',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sheetField(
                    theme,
                    controller: title,
                    label: '标题',
                    hint: '例如：喜欢的食物、重要约定',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '类别',
                    style: TextStyle(
                      color: theme.textStrong,
                      fontFamily: 'TideFont',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in _categories)
                        _categoryChoice(
                          theme,
                          item,
                          selected: category == item,
                          onTap: () => setSheetState(() => category = item),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sheetField(
                    theme,
                    controller: content,
                    label: '完整内容',
                    hint: '写下需要长期保留和用于对话的信息',
                    minLines: 5,
                    maxLines: 10,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TideDialogs.glassButton(
                          '取消',
                          onTap: () => Navigator.pop(context, false),
                          color: theme.surfaceVariant,
                          textColor: theme.textStrong,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TideDialogs.glassButton(
                          '保存',
                          onTap: () {
                            if (content.text.trim().isNotEmpty) {
                              Navigator.pop(context, true);
                            }
                          },
                          color: theme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (saved == true) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = <String, dynamic>{
        'title': title.text.trim(),
        'type': row?['type']?.toString() ?? 'long',
        'content': content.text.trim(),
        'category': category,
        'importance': row?['importance'] ?? 3,
        'timestamp': row?['timestamp'] ?? now,
        'updated_at': now,
      };
      if (row == null) {
        await _db.insertMemory({
          'id': 'mem_${widget.botId}_${now}_${content.text.hashCode.abs()}',
          'bot_id': widget.botId,
          ...values,
        });
      } else {
        await _db.updateMemory(row['id'].toString(), values);
      }
      await _load();
    }
    title.dispose();
    content.dispose();
  }

  Widget _categoryChoice(
    TideTheme theme,
    String category, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = _categoryColor(category, theme);
    return BouncyTap(
      onTap: onTap,
      scaleAmount: .035,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: .16)
              : theme.surfaceVariant.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color.withValues(alpha: .55) : theme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              category,
              style: TextStyle(
                color: selected ? color : theme.textWeak,
                fontFamily: 'TideFont',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEntry(Map<String, dynamic> row) async {
    final confirmed = await showTideDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = TideTheme.of(dialogContext);
        return TideDialogSurface(
          child: TideDialogs.glassContent(
            context: dialogContext,
            children: [
              Text(
                '删除这条世界书？',
                style: TextStyle(
                  color: theme.textStrong,
                  fontFamily: 'TideFont',
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _text(row, 'title').isEmpty
                    ? '删除后无法恢复。'
                    : '“${_text(row, 'title')}”删除后无法恢复。',
                style: TextStyle(
                  color: theme.textWeak,
                  fontFamily: 'TideFont',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TideDialogs.glassButton(
                      '取消',
                      onTap: () => Navigator.pop(dialogContext, false),
                      color: theme.surfaceVariant,
                      textColor: theme.textStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TideDialogs.glassButton(
                      '删除',
                      onTap: () => Navigator.pop(dialogContext, true),
                      color: theme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true) {
      await _db.deleteMemory(row['id'].toString());
      _expanded.remove(row['id'].toString());
      await _load();
    }
  }

  InputDecoration _fieldDecoration(TideTheme theme, String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: theme.surfaceVariant.withValues(alpha: .56),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.border.withValues(alpha: .65)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.primary, width: 1.2),
      ),
    );
  }

  Widget _sheetField(
    TideTheme theme, {
    required TextEditingController controller,
    required String label,
    required String hint,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: _fieldDecoration(theme, label).copyWith(hintText: hint),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final entries = _visibleEntries;
    final botView = _firstEntry('用户认知');
    final userView = _firstEntry('自我认知');
    final relationship = _firstEntry('关系');

    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: _loading
            ? null
            : BouncyTap(
                onTap: _editEntry,
                scaleAmount: .04,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: theme.primary,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: theme.primary.withValues(alpha: .28),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 21),
                      SizedBox(width: 7),
                      Text(
                        '添加条目',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'TideFont',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        body: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: theme.primary,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(child: _header(theme)),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        sliver: SliverList.list(
                          children: [
                            _identityCard(theme),
                            const SizedBox(height: 14),
                            _relationshipCard(
                              theme,
                              botView: botView,
                              userView: userView,
                              relationship: relationship,
                            ),
                            const SizedBox(height: 22),
                            _sectionHeader(theme),
                            const SizedBox(height: 10),
                            _searchField(theme),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      if (entries.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _emptyState(theme),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                          sliver: SliverList.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, index) =>
                                _entryCard(theme, entries[index]),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _header(TideTheme theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 10),
      child: Row(
        children: [
          BouncyTap(
            onTap: () => Navigator.pop(context),
            scaleAmount: .045,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.surfaceVariant.withValues(alpha: .58),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.border.withValues(alpha: .65),
                ),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: theme.textStrong,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '世界书',
                  style: TextStyle(
                    color: theme.textStrong,
                    fontFamily: 'TideFont',
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_entries.length} 条记忆与设定',
                  style: TextStyle(
                    color: theme.textFaint,
                    fontFamily: 'TideFont',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityCard(TideTheme theme) {
    return _GlassPanel(
      radius: 30,
      padding: const EdgeInsets.all(20),
      accent: theme.primary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Hero(
            tag: 'world_book_avatar_${widget.botId}',
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [theme.primaryLight, theme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.primary.withValues(alpha: .25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: TideBotAvatar(
                name: _botName,
                path: _text(_bot, 'avatar'),
                size: 78,
              ),
            ),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _botName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textStrong,
                          fontFamily: 'TideFont',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.primary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '角色档案',
                        style: TextStyle(
                          color: theme.primary,
                          fontFamily: 'TideFont',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _profileSummary(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textWeak,
                    fontFamily: 'TideFont',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _relationshipCard(
    TideTheme theme, {
    Map<String, dynamic>? botView,
    Map<String, dynamic>? userView,
    Map<String, dynamic>? relationship,
  }) {
    final relationTitle = relationship == null
        ? '关系状态'
        : (_text(relationship, 'title').isEmpty
            ? '关系状态'
            : _text(relationship, 'title'));
    final relationContent =
        relationship == null ? '还没有形成明确的关系记录' : _text(relationship, 'content');
    return _GlassPanel(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _perspective(
                  theme,
                  icon: Icons.smart_toy_rounded,
                  avatarPath: _text(_bot, 'avatar'),
                  avatarName: _botName,
                  title: '$_botName 眼中的你',
                  body: botView == null
                      ? '还没有记录对你的认知'
                      : _text(botView, 'content'),
                  color: const Color(0xFF34C759),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2D55).withValues(alpha: .12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFF2D55).withValues(alpha: .22),
                        ),
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFFF2D55),
                        size: 17,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 18,
                      color: theme.border.withValues(alpha: .75),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _perspective(
                  theme,
                  icon: Icons.person_rounded,
                  avatarPath: _userAvatar,
                  avatarName: _userName,
                  title: '你眼中的 $_botName',
                  body: userView == null
                      ? '还没有记录对机器人的认知'
                      : _text(userView, 'content'),
                  color: const Color(0xFF5AC8FA),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFF2D55).withValues(alpha: .075),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFF2D55).withValues(alpha: .13),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.link_rounded,
                  size: 17,
                  color: Color(0xFFFF2D55),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        color: theme.textWeak,
                        fontFamily: 'TideFont',
                        fontSize: 11,
                        height: 1.35,
                      ),
                      children: [
                        TextSpan(
                          text: '$relationTitle  ',
                          style: TextStyle(
                            color: theme.textStrong,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(text: relationContent),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _perspective(
    TideTheme theme, {
    required IconData icon,
    required String avatarPath,
    required String avatarName,
    required String title,
    required String body,
    required Color color,
  }) {
    final hasAvatar = avatarPath.isNotEmpty && File(avatarPath).existsSync();
    return Container(
      height: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: theme.isDark ? .10 : .075),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: Container(
              width: 30,
              height: 30,
              color: color.withValues(alpha: .14),
              child: hasAvatar
                  ? Image.file(File(avatarPath), fit: BoxFit.cover)
                  : Center(
                      child: avatarName.isEmpty
                          ? Icon(icon, color: color, size: 17)
                          : Text(
                              avatarName.characters.first,
                              style: TextStyle(
                                color: color,
                                fontFamily: 'TideFont',
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.textStrong,
              fontFamily: 'TideFont',
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Text(
              body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.textWeak,
                fontFamily: 'TideFont',
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(TideTheme theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '世界书条目',
                style: TextStyle(
                  color: theme.textStrong,
                  fontFamily: 'TideFont',
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '点击条目展开完整内容',
                style: TextStyle(
                  color: theme.textFaint,
                  fontFamily: 'TideFont',
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.primary.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${_visibleEntries.length} 条',
            style: TextStyle(
              color: theme.primary,
              fontFamily: 'TideFont',
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchField(TideTheme theme) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: theme.hasGlobalBackground
            ? theme.glass.withValues(alpha: theme.isDark ? .34 : .50)
            : theme.surfaceVariant.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border.withValues(alpha: .65)),
      ),
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索标题、内容或类别',
          hintStyle: TextStyle(color: theme.textFaint, fontSize: 13),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: theme.textFaint,
            size: 20,
          ),
          suffixIcon: _search.text.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.all(7),
                  child: BouncyTap(
                    onTap: () {
                      _search.clear();
                      setState(() {});
                    },
                    scaleAmount: .05,
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.surfaceVariant.withValues(alpha: .72),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cancel_rounded,
                        color: theme.textFaint,
                        size: 18,
                      ),
                    ),
                  ),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }

  Widget _entryCard(TideTheme theme, Map<String, dynamic> row) {
    final id = row['id'].toString();
    final expanded = _expanded.contains(id);
    final category = _category(row);
    final content = _text(row, 'content');
    final color = _categoryColor(category, theme);
    final title = _text(row, 'title').isEmpty ? category : _text(row, 'title');
    return _GlassPanel(
      radius: 22,
      padding: EdgeInsets.zero,
      child: BouncyTap(
        onTap: () => setState(() {
          expanded ? _expanded.remove(id) : _expanded.add(id);
        }),
        scaleAmount: .012,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: .36),
                        blurRadius: 7,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: theme.textStrong,
                              fontFamily: 'TideFont',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              color: color,
                              fontFamily: 'TideFont',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Text(
                        expanded
                            ? (content.isEmpty ? '无内容' : content)
                            : (content.isEmpty ? '无内容' : _summary(content)),
                        maxLines: expanded ? null : 2,
                        overflow: expanded ? null : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textWeak,
                          fontFamily: 'TideFont',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                    if (expanded) ...[
                      const SizedBox(height: 11),
                      Divider(height: 1, color: theme.divider),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          BouncyTap(
                            onTap: () => _editEntry(row),
                            scaleAmount: .04,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.primary.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                    color: theme.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '编辑',
                                    style: TextStyle(
                                      color: theme.primary,
                                      fontFamily: 'TideFont',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          BouncyTap(
                            onTap: () => _deleteEntry(row),
                            scaleAmount: .04,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.surfaceVariant.withValues(
                                  alpha: .72,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.border.withValues(alpha: .65),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                    color: theme.textWeak,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '删除',
                                    style: TextStyle(
                                      color: theme.textWeak,
                                      fontFamily: 'TideFont',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              BouncyTap(
                onTap: () => setState(() {
                  expanded ? _expanded.remove(id) : _expanded.add(id);
                }),
                scaleAmount: .04,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: expanded ? .5 : 0,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: theme.textFaint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(TideTheme theme) {
    final searching = _search.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 38, 36, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              searching ? Icons.search_off_rounded : Icons.menu_book_rounded,
              color: theme.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            searching ? '没有找到相关条目' : '世界书还是空的',
            style: TextStyle(
              color: theme.textStrong,
              fontFamily: 'TideFont',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            searching ? '换一个关键词试试' : '点击右下角添加第一条记忆或设定',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textFaint,
              fontFamily: 'TideFont',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? accent;

  const _GlassPanel({
    required this.child,
    required this.padding,
    required this.radius,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final glass = theme.hasGlobalBackground;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: glass
            ? theme.glass.withValues(alpha: theme.isDark ? .35 : .48)
            : theme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: accent == null
              ? theme.border.withValues(alpha: glass ? .54 : .82)
              : accent!.withValues(alpha: .20),
          width: .7,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.isDark ? .14 : .055,
            ),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
          if (glass)
            BoxShadow(
              color: Colors.white.withValues(alpha: theme.isDark ? .035 : .18),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: child,
    );
    if (!glass) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: content,
      ),
    );
  }
}
