import 'dart:math' as math;
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
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  final Set<String> _expanded = {};

  // 预设颜色池（扩展至30色）
  static const _colorPool = <Color>[
    Color(0xFF5AC8FA), // 蓝色
    Color(0xFF34C759), // 绿色
    Color(0xFFFF2D55), // 红色
    Color(0xFF5856D6), // 紫色
    Color(0xFF00A7A5), // 青色
    Color(0xFFFF3B30), // 橙红
    Color(0xFFAF52DE), // 粉紫
    Color(0xFFFFCC00), // 黄色
    Color(0xFFFF9500), // 橙色
    Color(0xFF32ADE6), // 天蓝
    Color(0xFF30D158), // 翠绿
    Color(0xFFFF453A), // 朱红
    Color(0xFFBF5AF2), // 紫罗兰
    Color(0xFF64D2FF), // 浅蓝
    Color(0xFFFFD60A), // 金黄
    Color(0xFF0A84FF), // 深蓝
    Color(0xFF30B0C7), // 青绿
    Color(0xFFFF6482), // 粉红
    Color(0xFF8E44AD), // 深紫
    Color(0xFF16A085), // 深青
    Color(0xFFE74C3C), // 深红
    Color(0xFFF39C12), // 深橙
    Color(0xFF27AE60), // 墨绿
    Color(0xFF2C3E50), // 深灰蓝
    Color(0xFFE67E22), // 胡萝卜橙
    Color(0xFF9B59B6), // 葡萄紫
    Color(0xFF1ABC9C), // 绿松石
    Color(0xFF3498DB), // 天青
    Color(0xFFF1C40F), // 向日葵黄
    Color(0xFFE91E63), // 玫瑰红
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
      _loadCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      _bot = (results[0] as Map<String, dynamic>?) ?? {};
      _entries = List<Map<String, dynamic>>.from(results[1] as List);
      _categories = results[2] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _loadCategories() async {
    final db = await _db.database;
    final rows = await db.query(
      'kv_store',
      where: 'key LIKE ?',
      whereArgs: ['wb_category_%'],
    );
    return rows.map((row) {
      final key = row['key'].toString();
      final name = key.replaceFirst('wb_category_', '');
      final colorValue = int.tryParse(row['value'].toString()) ?? 0xFF5AC8FA;
      return {'name': name, 'color': colorValue};
    }).toList();
  }

  String _text(Map<String, dynamic> row, String key) =>
      row[key]?.toString().trim() ?? '';

  String get _botName {
    final value = _text(_bot, 'name');
    return value.isEmpty ? widget.botName : value;
  }

  String _category(Map<String, dynamic> row) {
    final value = _text(row, 'category');
    return value.isEmpty ? '记忆' : value;
  }

  List<String> get _allCategoryNames {
    return _categories.map((c) => c['name'].toString()).toList();
  }

  Color _categoryColor(String category) {
    final existing = _categories.where((c) => c['name'] == category);
    if (existing.isNotEmpty) {
      return Color(existing.first['color'] as int);
    }
    return const Color(0xFF5AC8FA);
  }

  List<Map<String, dynamic>> get _visibleEntries {
    final query = _search.text.trim().toLowerCase();
    // 过滤掉特殊类别
    final filtered = _entries.where((row) {
      final cat = _category(row);
      return cat != '角色档案' &&
          cat != '角色眼中的你' &&
          cat != '角色的自我认知' &&
          cat != '关系';
    }).toList();
    if (query.isEmpty) return filtered;
    return filtered.where((row) {
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
      if (_category(row) == category) {
        return row;
      }
    }
    return null;
  }

  Future<void> _editProfile() async {
    final promptCtrl = TextEditingController(text: _text(_bot, 'prompt'));
    final descCtrl = TextEditingController(text: _text(_bot, 'desc'));

    final saved = await showTideSheet<bool>(
      context: context,
      height: MediaQuery.sizeOf(context).height * .75,
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
                    '编辑角色档案',
                    style: TextStyle(
                      color: theme.textStrong,
                      fontFamily: 'TideFont',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: promptCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: '说话方式',
                      hintText: '描述角色的说话风格、语气、用词习惯等',
                      hintStyle:
                          TextStyle(color: theme.textFaint, fontSize: 13),
                      filled: true,
                      fillColor: theme.surfaceVariant.withValues(alpha: .56),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descCtrl,
                    minLines: 5,
                    maxLines: 10,
                    decoration: InputDecoration(
                      labelText: '人设概述',
                      hintText: '描述角色的性格、背景、特点等',
                      hintStyle:
                          TextStyle(color: theme.textFaint, fontSize: 13),
                      filled: true,
                      fillColor: theme.surfaceVariant.withValues(alpha: .56),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
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
                          onTap: () => Navigator.pop(context, true),
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
      await _db.updateBot(widget.botId, {
        'prompt': promptCtrl.text.trim(),
        'desc': descCtrl.text.trim(),
      });
      await _load();
    }
    promptCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _deleteCategory(String category) async {
    final confirmed = await showTideDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = TideTheme.of(dialogContext);
        return TideDialogSurface(
          child: TideDialogs.glassContent(
            context: dialogContext,
            children: [
              Text(
                '删除类别',
                style: TextStyle(
                  color: theme.textStrong,
                  fontFamily: 'TideFont',
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '确定要删除"$category"类别吗？该类别下的所有条目将变为"记忆"类别。',
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
      final db = await _db.database;
      await db.delete('kv_store',
          where: 'key = ?', whereArgs: ['wb_category_$category']);
      // 将该类别下的所有条目改为"记忆"
      for (final entry in _entries) {
        if (_category(entry) == category) {
          await _db.updateMemory(entry['id'].toString(), {'category': '记忆'});
        }
      }
      await _load();
    }
  }

  Future<void> _editSpecialCard({
    required String category,
    required String title,
    required String hint,
    String? existingContent,
    String? existingId,
  }) async {
    final controller = TextEditingController(text: existingContent ?? '');
    final saved = await showTideSheet<bool>(
      context: context,
      height: MediaQuery.sizeOf(context).height * .75,
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
                    title,
                    style: TextStyle(
                      color: theme.textStrong,
                      fontFamily: 'TideFont',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    minLines: 8,
                    maxLines: 15,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        color: theme.textFaint,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: theme.surfaceVariant.withValues(alpha: .56),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
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
                            if (controller.text.trim().isNotEmpty) {
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
      final content = controller.text.trim();
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = <String, dynamic>{
        'title': '',
        'type': 'long',
        'content': content,
        'category': category,
        'importance': 5,
        'timestamp': now,
        'updated_at': now,
      };

      if (existingId != null) {
        await _db.updateMemory(existingId, values);
      } else {
        await _db.insertMemory({
          'id': 'mem_${widget.botId}_${now}_${content.hashCode.abs()}',
          'bot_id': widget.botId,
          ...values,
        });
      }
      await _load();
    }
    controller.dispose();
  }

  String _profileSummary() {
    final values = <String>[
      if (_text(_bot, 'prompt').isNotEmpty) _text(_bot, 'prompt'),
      if (_text(_bot, 'desc').isNotEmpty) _text(_bot, 'desc'),
    ];
    return values.isEmpty ? '还没有填写说话方式和人设概述' : values.join(' · ');
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
                      for (final item in _allCategoryNames)
                        _categoryChoice(
                          theme,
                          item,
                          selected: category == item,
                          onTap: () => setSheetState(() => category = item),
                        ),
                      _categoryChoice(
                        theme,
                        '+ 添加类别',
                        selected: false,
                        onTap: () async {
                          final newCat = await _addCategory(theme);
                          if (newCat != null) {
                            setSheetState(() => category = newCat);
                            await _load();
                          }
                        },
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
    final color = _categoryColor(category);
    final canDelete = !category.startsWith('+') &&
        category != '记忆' &&
        !_allCategoryNames.take(3).contains(category);

    return GestureDetector(
      onTap: onTap,
      onLongPress: canDelete ? () => _deleteCategory(category) : null,
      child: BouncyTap(
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
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!category.startsWith('+'))
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              if (!category.startsWith('+')) const SizedBox(width: 7),
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

  Future<String?> _addCategory(TideTheme theme) async {
    final nameCtrl = TextEditingController();
    Color selectedColor = _colorPool[math.Random().nextInt(_colorPool.length)];

    final result = await showTideSheet<String>(
      context: context,
      height: MediaQuery.sizeOf(context).height * .6,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
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
                    '添加类别',
                    style: TextStyle(
                      color: theme.textStrong,
                      fontFamily: 'TideFont',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: nameCtrl,
                    decoration: _fieldDecoration(theme, '类别名称').copyWith(
                      hintText: '例如：兴趣爱好、工作技能',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '选择颜色',
                    style: TextStyle(
                      color: theme.textStrong,
                      fontFamily: 'TideFont',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _colorPool.map((color) {
                      final colorValue = ((color.a * 255).toInt() << 24) |
                          ((color.r * 255).toInt() << 16) |
                          ((color.g * 255).toInt() << 8) |
                          (color.b * 255).toInt();
                      final isUsed =
                          _categories.any((c) => c['color'] == colorValue);
                      final selected = selectedColor == color;
                      return BouncyTap(
                        onTap: isUsed
                            ? null
                            : () => setSheetState(() => selectedColor = color),
                        scaleAmount: .05,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: .4),
                                      blurRadius: 12,
                                    )
                                  ]
                                : null,
                          ),
                          child: isUsed
                              ? Icon(
                                  Icons.close_rounded,
                                  color: Colors.white.withValues(alpha: .6),
                                  size: 20,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TideDialogs.glassButton(
                          '取消',
                          onTap: () => Navigator.pop(context),
                          color: theme.surfaceVariant,
                          textColor: theme.textStrong,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TideDialogs.glassButton(
                          '保存',
                          onTap: () {
                            final name = nameCtrl.text.trim();
                            if (name.isNotEmpty) {
                              Navigator.pop(context, name);
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

    if (result != null && result.isNotEmpty) {
      final colorValue = ((selectedColor.a * 255).toInt() << 24) |
          ((selectedColor.r * 255).toInt() << 16) |
          ((selectedColor.g * 255).toInt() << 8) |
          (selectedColor.b * 255).toInt();
      await _db.setKV('wb_category_$result', colorValue.toString());
      return result;
    }
    return null;
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
    final botView = _firstEntry('角色眼中的你');
    final userView = _firstEntry('角色的自我认知');
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
    return BouncyTap(
      onTap: _editProfile,
      scaleAmount: .015,
      child: _GlassPanel(
        radius: 24,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            TideBotAvatar(
              name: _botName,
              path: _text(_bot, 'avatar'),
              size: 56,
            ),
            const SizedBox(width: 14),
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
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '角色档案',
                          style: TextStyle(
                            color: theme.primary,
                            fontFamily: 'TideFont',
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _profileSummary(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textWeak,
                      fontFamily: 'TideFont',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.edit_outlined,
              color: theme.textFaint,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _relationshipCard(
    TideTheme theme, {
    Map<String, dynamic>? botView,
    Map<String, dynamic>? userView,
    Map<String, dynamic>? relationship,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: BouncyTap(
                onTap: () => _editSpecialCard(
                  category: '角色眼中的你',
                  title: '角色眼中的你',
                  hint: '角色如何看待你？你的特点、习惯、偏好是什么？',
                  existingContent:
                      botView == null ? null : _text(botView, 'content'),
                  existingId: botView?['id']?.toString(),
                ),
                scaleAmount: .015,
                child: _specialCard(
                  theme,
                  icon: Icons.visibility_outlined,
                  color: const Color(0xFF34C759),
                  title: '角色眼中的你',
                  content:
                      botView == null ? '还没有记录' : _text(botView, 'content'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BouncyTap(
                onTap: () => _editSpecialCard(
                  category: '角色的自我认知',
                  title: '角色的自我认知',
                  hint: '角色如何看待自己？角色的性格、习惯、偏好是什么？',
                  existingContent:
                      userView == null ? null : _text(userView, 'content'),
                  existingId: userView?['id']?.toString(),
                ),
                scaleAmount: .015,
                child: _specialCard(
                  theme,
                  icon: Icons.person_outline_rounded,
                  color: const Color(0xFF5AC8FA),
                  title: '角色的自我认知',
                  content:
                      userView == null ? '还没有记录' : _text(userView, 'content'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        BouncyTap(
          onTap: () => _editSpecialCard(
            category: '关系',
            title: '关系状态',
            hint: '你们之间的关系如何？有什么特殊的约定或故事？',
            existingContent:
                relationship == null ? null : _text(relationship, 'content'),
            existingId: relationship?['id']?.toString(),
          ),
          scaleAmount: .015,
          child: _GlassPanel(
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2D55).withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFFF2D55),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '关系',
                        style: TextStyle(
                          color: theme.textStrong,
                          fontFamily: 'TideFont',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        relationship == null
                            ? '还没有记录'
                            : _text(relationship, 'content'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textWeak,
                          fontFamily: 'TideFont',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  color: theme.textFaint,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _specialCard(
    TideTheme theme, {
    required IconData icon,
    required Color color,
    required String title,
    required String content,
  }) {
    return _GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
              Icon(
                Icons.edit_outlined,
                color: theme.textFaint,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: theme.textStrong,
              fontFamily: 'TideFont',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.textWeak,
              fontFamily: 'TideFont',
              fontSize: 10,
              height: 1.4,
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
      height: 44,
      decoration: BoxDecoration(
        color: theme.hasGlobalBackground
            ? theme.glass.withValues(alpha: theme.isDark ? .34 : .50)
            : theme.surfaceVariant.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(
          color: theme.textStrong,
          fontSize: 13,
        ),
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
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.surfaceVariant.withValues(alpha: .72),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: theme.textFaint,
                        size: 16,
                      ),
                    ),
                  ),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _entryCard(TideTheme theme, Map<String, dynamic> row) {
    final id = row['id'].toString();
    final expanded = _expanded.contains(id);
    final category = _category(row);
    final content = _text(row, 'content');
    final color = _categoryColor(category);
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

  const _GlassPanel({
    required this.child,
    required this.padding,
    required this.radius,
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
          color: theme.border.withValues(alpha: glass ? .54 : .82),
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
