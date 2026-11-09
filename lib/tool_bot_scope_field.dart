import 'dart:convert';
import 'package:flutter/material.dart';
import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';
import 'tool_bot_scope.dart';

/// Draft selection: changes reach the caller only after pressing Apply.
class ToolBotScopeField extends StatefulWidget {
  const ToolBotScopeField(
      {super.key, this.initialScope, required this.onChanged});
  final String? initialScope;
  final ValueChanged<String?> onChanged;
  @override
  State<ToolBotScopeField> createState() => _ToolBotScopeFieldState();
}

class _ToolBotScopeFieldState extends State<ToolBotScopeField> {
  String? _scope;
  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
  }

  Future<void> _choose() async {
    final result = await showToolBotScopePicker(context, initialScope: _scope);
    if (result == null || !mounted) return;
    setState(() => _scope = result.scope);
    widget.onChanged(result.scope);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    var label = '全部机器人';
    if (_scope != null) {
      try {
        final count = (jsonDecode(_scope!) as List).length;
        label = count == 0 ? '未选择机器人' : '已选择 $count 个机器人';
      } catch (_) {
        label = '请选择机器人';
      }
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.smart_toy_outlined, color: theme.primary),
      title: Text('启用机器人', style: TextStyle(color: theme.textStrong)),
      subtitle: Text(label, style: TextStyle(color: theme.textWeak)),
      trailing: Icon(Icons.chevron_right_rounded, color: theme.textWeak),
      onTap: _choose,
    );
  }
}

Future<({String? scope})?> showToolBotScopePicker(BuildContext context,
    {String? initialScope}) async {
  final bots = await DBManager().getAllBots();
  if (!context.mounted) return null;
  final selected = bots
      .where((bot) => toolEnabledForBot(initialScope, bot['id'].toString()))
      .map((bot) => bot['id'].toString())
      .toSet();
  // Preserve assignments to temporarily unavailable/imported bots.
  if (initialScope != null) {
    try {
      selected.addAll((jsonDecode(initialScope) as List).whereType<String>());
    } catch (_) {}
  }
  var all = initialScope == null;
  final applied = await TideDialogs.show<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
      final theme = TideTheme.of(ctx);
      return TideDialogSurface(
          child: TideDialogs.glassContent(
        context: ctx,
        children: [
          Text('选择启用的机器人',
              style: TextStyle(
                  color: theme.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(
                onPressed: () => update(() {
                      all = true;
                      selected.addAll(bots.map((bot) => bot['id'].toString()));
                    }),
                child: Text('全选', style: TextStyle(color: theme.primary))),
            TextButton(
                onPressed: () => update(() {
                      all = false;
                      selected.clear();
                    }),
                child: Text('取消全选', style: TextStyle(color: theme.primary))),
          ]),
          if (bots.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('暂无机器人')),
          ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .42),
            child: ListView(shrinkWrap: true, children: [
              for (final bot in bots)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.primary,
                  title: Text(bot['name']?.toString() ?? '未命名机器人',
                      style: TextStyle(color: theme.textStrong)),
                  value: all || selected.contains(bot['id'].toString()),
                  onChanged: (value) => update(() {
                    all = false;
                    if (value == true) {
                      selected.add(bot['id'].toString());
                    } else {
                      selected.remove(bot['id'].toString());
                    }
                  }),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: TideDialogs.glassButton('取消',
                    color: theme.surfaceVariant,
                    textColor: theme.textStrong,
                    onTap: () => Navigator.pop(ctx, false))),
            const SizedBox(width: 12),
            Expanded(
                child: TideDialogs.glassButton('应用',
                    onTap: () => Navigator.pop(ctx, true))),
          ]),
        ],
      ));
    }),
  );
  if (applied != true || !context.mounted) return null;
  final value = all ? null : jsonEncode(selected.toList()..sort());
  return (scope: value);
}
