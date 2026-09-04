import 'package:flutter/material.dart';
import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

class DataDashboardPage extends StatefulWidget {
  const DataDashboardPage({super.key});
  @override
  State<DataDashboardPage> createState() => _DataDashboardPageState();
}

class _DataDashboardPageState extends State<DataDashboardPage> {
  int _rangeDays = 30;
  bool _loading = true;

  List<int> _tokenSeries = [];
  List<int> _replySeries = [];
  int _totalTokens = 0;
  int _totalReplies = 0;
  int _todayTokens = 0;
  int _monthTokens = 0;
  int _todayReplies = 0;
  int _monthReplies = 0;
  List<DateTime> _days = [];
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _load() async {
    // 仅首次进入显示加载态；切换范围时保留当前图表，避免整页闪成空白。
    if (_tokenSeries.isEmpty && _replySeries.isEmpty)
      setState(() => _loading = true);
    final db = await DBManager().database;
    final now = DateTime.now();
    final startMs = _dayStart(now.subtract(Duration(days: _rangeDays - 1)))
        .millisecondsSinceEpoch;

    final days = <DateTime>[];
    for (var i = _rangeDays - 1; i >= 0; i--) {
      days.add(_dayStart(now.subtract(Duration(days: i))));
    }

    final chartUsageRows = await db.query('ai_usage_events',
        where: 'timestamp >= ? AND event_type = ?',
        whereArgs: [startMs, 'chat'],
        orderBy: 'timestamp ASC');
    final allUsageRows = await db
        .query('ai_usage_events', where: 'event_type = ?', whereArgs: ['chat']);

    final tokenByDay = <String, int>{};
    final replyByDay = <String, int>{};
    for (final r in chartUsageRows) {
      final ts = (r['timestamp'] as num?)?.toInt();
      if (ts == null) continue;
      final d = _dayStart(DateTime.fromMillisecondsSinceEpoch(ts));
      final key = '${d.year}-${d.month}-${d.day}';
      tokenByDay[key] =
          (tokenByDay[key] ?? 0) + ((r['total_tokens'] as num?)?.toInt() ?? 0);
      replyByDay[key] =
          (replyByDay[key] ?? 0) + ((r['reply_count'] as num?)?.toInt() ?? 0);
    }

    // 历史账本之前的 assistant 文本作为估算兜底，避免丢失早期回复。
    final chatRows = await db.query('chat_history',
        columns: ['content', 'timestamp'],
        where:
            "role = 'assistant' AND type IN ('text', 'audio') AND timestamp >= ?",
        whereArgs: [startMs],
        orderBy: 'timestamp ASC');

    for (final r in chatRows) {
      final ts = (r['timestamp'] as num?)?.toInt();
      if (ts == null) continue;
      final d = _dayStart(DateTime.fromMillisecondsSinceEpoch(ts));
      final key = '${d.year}-${d.month}-${d.day}';
      if ((replyByDay[key] ?? 0) > 0) continue; // ledger 已覆盖，避免重复计数
      replyByDay[key] = (replyByDay[key] ?? 0) + 1;
      tokenByDay[key] = (tokenByDay[key] ?? 0) +
          estimateTokens(r['content']?.toString() ?? '');
    }

    final tokenSeries = <int>[];
    final replySeries = <int>[];
    final today = _dayStart(now);
    final monthStart = DateTime(now.year, now.month);
    var totalTokens = 0;
    var totalReplies = 0;
    var todayTokens = 0;
    var monthTokens = 0;
    var todayReplies = 0;
    var monthReplies = 0;
    for (final row in allUsageRows) {
      final timestamp = (row['timestamp'] as num?)?.toInt() ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final tokens = (row['total_tokens'] as num?)?.toInt() ?? 0;
      final replies = (row['reply_count'] as num?)?.toInt() ?? 0;
      totalTokens += tokens;
      totalReplies += replies;
      if (!date.isBefore(today)) {
        todayTokens += tokens;
        todayReplies += replies;
      }
      if (!date.isBefore(monthStart)) {
        monthTokens += tokens;
        monthReplies += replies;
      }
    }
    for (final d in days) {
      final key = '${d.year}-${d.month}-${d.day}';
      final t = tokenByDay[key] ?? 0;
      final r = replyByDay[key] ?? 0;
      tokenSeries.add(t);
      replySeries.add(r);
    }
    if (!mounted) return;
    setState(() {
      _tokenSeries = tokenSeries;
      _replySeries = replySeries;
      _totalTokens = totalTokens;
      _totalReplies = totalReplies;
      _todayTokens = todayTokens;
      _monthTokens = monthTokens;
      _todayReplies = todayReplies;
      _monthReplies = monthReplies;
      _days = days;
      _selectedIndex = days.isEmpty ? null : days.length - 1;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('数据大盘', style: TextStyle(fontFamily: 'TideFont')),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: theme.primary))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _buildRangeChips(theme),
                  const SizedBox(height: 12),
                  _ChartCard(
                    title: '消耗 Token',
                    subtitle: '近 $_rangeDays 天',
                    color: theme.primary,
                    series: _tokenSeries,
                    days: _days,
                    selectedIndex: _selectedIndex,
                    onSelect: (index) => setState(() => _selectedIndex = index),
                  ),
                  const SizedBox(height: 14),
                  _ChartCard(
                    title: '机器人回复消息',
                    subtitle: '近 $_rangeDays 天',
                    color: const Color(0xFFB05E91),
                    series: _replySeries,
                    days: _days,
                    selectedIndex: _selectedIndex,
                    onSelect: (index) => setState(() => _selectedIndex = index),
                  ),
                  const SizedBox(height: 24),
                  _summarySection(theme),
                  const SizedBox(height: 12),
                  Text(
                    '统计来自 AI 调用账本；不返回 usage 的提供商按文本长度估算。',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.textFaint,
                        fontFamily: 'TideFont'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildRangeChips(TideTheme theme) {
    Widget chip(String label, int days) => BouncyTap(
          onTap: () {
            if (_rangeDays == days) return;
            setState(() => _rangeDays = days);
            _load();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _rangeDays == days ? theme.primary : theme.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'TideFont',
                fontSize: 14,
                color: _rangeDays == days ? Colors.white : theme.textWeak,
              ),
            ),
          ),
        );
    return Row(
      children: [
        chip('近7天', 7),
        const SizedBox(width: 8),
        chip('近30天', 30),
        const SizedBox(width: 8),
        chip('近1年', 365),
      ],
    );
  }

  Widget _summarySection(TideTheme theme) {
    final cards = <(IconData, String, int, Color)>[
      // Each row is one time range: left = token usage, right = replies.
      (Icons.today_rounded, '今日消耗 Token', _todayTokens, theme.primary),
      (Icons.today_rounded, '今日机器人回复', _todayReplies, const Color(0xFFB05E91)),
      (Icons.calendar_month_rounded, '本月消耗 Token', _monthTokens, theme.primary),
      (
        Icons.calendar_month_rounded,
        '本月机器人回复',
        _monthReplies,
        const Color(0xFFB05E91)
      ),
      (Icons.all_inclusive_rounded, '累计消耗 Token', _totalTokens, theme.primary),
      (Icons.forum_rounded, '累计机器人回复', _totalReplies, const Color(0xFFB05E91)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('使用概览',
          style: TextStyle(
              fontFamily: 'TideFont',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: theme.textStrong)),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.42,
        children: cards
            .map((card) =>
                _summaryCard(theme, card.$1, card.$2, card.$3, card.$4))
            .toList(),
      ),
    ]);
  }

  Widget _summaryCard(
      TideTheme theme, IconData icon, String label, int value, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
          color: theme.surfaceVariant, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: accent, size: 25),
        const Spacer(),
        Text('$value',
            style: TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w700,
                color: theme.textStrong,
                fontFamily: 'TideFont')),
        const SizedBox(height: 3),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, color: theme.textWeak, fontFamily: 'TideFont')),
      ]),
    );
  }
}

/// 自绘折线图（不引入第三方图表依赖，也不依赖系统原生控件）。
class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final List<int> series;
  final List<DateTime> days;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.series,
    required this.days,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.textStrong,
                      fontFamily: 'TideFont')),
              const Spacer(),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.textFaint,
                      fontFamily: 'TideFont')),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(
                  '${subtitle}_${series.length}_${series.fold<int>(0, (a, b) => a + b)}'),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: 1),
              builder: (_, progress, __) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  if (series.isEmpty) return;
                  final box = context.findRenderObject() as RenderBox?;
                  final chartWidth = box?.size.width ?? 1;
                  final index = series.length == 1
                      ? 0
                      : ((details.localPosition.dx.clamp(0, chartWidth) /
                                  chartWidth) *
                              (series.length - 1))
                          .round()
                          .clamp(0, series.length - 1);
                  onSelect(index);
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _LineChartPainter(
                    color: color,
                    series: series,
                    gridColor: theme.divider,
                    selectedIndex: selectedIndex,
                    progress: progress,
                  ),
                ),
              ),
            ),
          ),
          if (selectedIndex != null && selectedIndex! < days.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${days[selectedIndex!].year}-${days[selectedIndex!].month.toString().padLeft(2, '0')}-${days[selectedIndex!].day.toString().padLeft(2, '0')}  ·  ${series[selectedIndex!]} $title',
                style: TextStyle(
                    fontFamily: 'TideFont',
                    fontSize: 12,
                    color: theme.textWeak),
              ),
            ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final Color color;
  final Color gridColor;
  final List<int> series;
  final int? selectedIndex;
  final double progress;

  _LineChartPainter({
    required this.color,
    required this.gridColor,
    required this.series,
    required this.selectedIndex,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxVal = series.fold<int>(0, (m, v) => v > m ? v : m);
    final maxY = maxVal == 0 ? 1.0 : maxVal.toDouble();

    final path = Path();
    for (var i = 0; i < series.length; i++) {
      final x = series.length == 1
          ? size.width / 2
          : size.width * i / (series.length - 1);
      final y =
          size.height - (series[i] / maxY) * (size.height - 16) * progress - 8;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final bounds = path.getBounds();
    final fill = Path.from(path)
      ..lineTo(bounds.right, size.height)
      ..lineTo(bounds.left, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < series.length) {
      final i = selectedIndex!;
      final x = series.length == 1
          ? size.width / 2
          : size.width * i / (series.length - 1);
      final y =
          size.height - (series[i] / maxY) * (size.height - 16) * progress - 8;
      final cross = Paint()
        ..color = color.withValues(alpha: 0.62)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), cross);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), cross);
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = color);
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.series != series ||
      old.color != color ||
      old.selectedIndex != selectedIndex ||
      old.progress != progress;
}
