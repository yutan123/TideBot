import 'package:flutter/material.dart';
import 'db.dart';
import 'theme.dart';

class DataDashboardPage extends StatefulWidget {
  const DataDashboardPage({super.key});
  @override
  State<DataDashboardPage> createState() => _DataDashboardPageState();
}

class _DataDashboardPageState extends State<DataDashboardPage> {
  final Map<String, int> _values = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DBManager().database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final week = today - 6 * Duration.millisecondsPerDay;
    final month = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final starts = [today, week, month, null];
    const keys = ['today', 'week', 'month', 'all'];
    for (var i = 0; i < keys.length; i++) {
      final from = starts[i];
      final usage = await db.rawQuery(
        'SELECT COALESCE(SUM(total_tokens), 0) AS tokens, COALESCE(SUM(reply_count), 0) AS replies FROM ai_usage_events${from == null ? '' : ' WHERE timestamp >= ?'}',
        from == null ? null : [from],
      );
      final legacy = await db.query('chat_history',
          columns: ['content'],
          where: from == null
              ? "role = 'assistant'"
              : "role = 'assistant' AND timestamp >= ?",
          whereArgs: from == null ? null : [from]);
      final ledgerReplies = (usage.first['replies'] as num?)?.toInt() ?? 0;
      // Old replies made before the usage ledger are retained as an estimate.
      final legacyTokens = legacy.fold<int>(
          0,
          (sum, row) =>
              sum + ((row['content']?.toString().length ?? 0) / 3.2).ceil());
      _values['${keys[i]}Messages'] =
          ledgerReplies > 0 ? ledgerReplies : legacy.length;
      _values['${keys[i]}Tokens'] = ledgerReplies > 0
          ? ((usage.first['tokens'] as num?)?.toInt() ?? 0)
          : legacyTokens;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    Widget card(String title, String key, IconData icon) => Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: theme.surfaceVariant,
              borderRadius: BorderRadius.circular(18)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: theme.primary),
            const SizedBox(height: 18),
            Text('${_values[key] ?? 0}',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: theme.textStrong,
                    fontFamily: 'TideFont')),
            const SizedBox(height: 4),
            Text(title,
                style:
                    TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
          ]),
        );
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
          title: const Text('数据大盘', style: TextStyle(fontFamily: 'TideFont')),
          backgroundColor: Colors.transparent),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('所有机器人的使用概览',
                style:
                    TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
            const SizedBox(height: 18),
            GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.28,
                children: [
                  card('今日消耗 Token（估算）', 'todayTokens', Icons.bolt_rounded),
                  card('今日机器人回复', 'todayMessages', Icons.chat_bubble_rounded),
                  card('本周消耗 Token（估算）', 'weekTokens', Icons.bolt_rounded),
                  card('本周机器人回复', 'weekMessages', Icons.chat_bubble_rounded),
                  card('本月消耗 Token（估算）', 'monthTokens', Icons.bolt_rounded),
                  card('本月机器人回复', 'monthMessages', Icons.chat_bubble_rounded),
                  card('累计消耗 Token（估算）', 'allTokens',
                      Icons.all_inclusive_rounded),
                  card('累计机器人回复', 'allMessages', Icons.forum_rounded),
                ]),
            const SizedBox(height: 18),
            Text('新产生的 AI 调用优先采用服务端 usage；不返回 usage 的提供商按文本长度估算。历史记录仍保留估算值。',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.textFaint,
                    fontFamily: 'TideFont')),
          ])),
    );
  }
}
