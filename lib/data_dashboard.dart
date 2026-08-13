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

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await DBManager().database;
    final now = DateTime.now();
    final startMs = _dayStart(now.subtract(Duration(days: _rangeDays - 1)))
        .millisecondsSinceEpoch;

    final days = <DateTime>[];
    for (var i = _rangeDays - 1; i >= 0; i--) {
      days.add(_dayStart(now.subtract(Duration(days: i))));
    }

    final usageRows = await db.query('ai_usage_events',
        where: 'timestamp >= ? AND event_type = ?',
        whereArgs: [startMs, 'chat'],
        orderBy: 'timestamp ASC');

    final tokenByDay = <String, int>{};
    final replyByDay = <String, int>{};
    for (final r in usageRows) {
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
    var totalTokens = 0;
    var totalReplies = 0;
    for (final d in days) {
      final key = '${d.year}-${d.month}-${d.day}';
      final t = tokenByDay[key] ?? 0;
      final r = replyByDay[key] ?? 0;
      tokenSeries.add(t);
      replySeries.add(r);
      totalTokens += t;
      totalReplies += r;
    }

    if (!mounted) return;
    setState(() {
      _tokenSeries = tokenSeries;
      _replySeries = replySeries;
      _totalTokens = totalTokens;
      _totalReplies = totalReplies;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
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
                ),
                const SizedBox(height: 14),
                _ChartCard(
                  title: '机器人回复消息',
                  subtitle: '近 $_rangeDays 天',
                  color: const Color(0xFFB05E91),
                  series: _replySeries,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                          theme, Icons.bolt_rounded, '消耗 Token', _totalTokens),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(theme, Icons.chat_bubble_rounded,
                          '机器人回复', _totalReplies),
                    ),
                  ],
                ),
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
    );
  }

  Widget _buildRangeChips(TideTheme theme) {
    Widget chip(String label, int days) => BouncyTap(
          onTap: () {
            if (_rangeDays == days) return;
            _rangeDays = days;
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

  Widget _summaryCard(TideTheme theme, IconData icon, String label, int value) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.primary),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: theme.textStrong,
              fontFamily: 'TideFont',
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: theme.textWeak, fontFamily: 'TideFont')),
        ],
      ),
    );
  }
}

/// 自绘折线图（不引入第三方图表依赖，也不依赖系统原生控件）。
class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final List<int> series;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.series,
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
            child: CustomPaint(
              size: Size.infinite,
              painter: _LineChartPainter(
                color: color,
                series: series,
                gridColor: theme.divider,
              ),
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

  _LineChartPainter({
    required this.color,
    required this.gridColor,
    required this.series,
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
      final y = size.height - (series[i] / maxY) * (size.height - 16) - 8;
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
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.series != series || old.color != color;
}
