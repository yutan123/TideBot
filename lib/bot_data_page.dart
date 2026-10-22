import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'bot_vital_model.dart';
import 'bot_vital_signs_service.dart';
import 'theme.dart';
import 'sleep_timeline.dart';
import 'ui_components.dart';

const vitalTitles = ['睡眠状况', '心情趋势', '压力水平', '身体指标', '今日步数', '健康状况'];
const vitalIcons = [
  Icons.bedtime_rounded,
  Icons.sentiment_satisfied_alt_rounded,
  Icons.spa_rounded,
  Icons.favorite_rounded,
  Icons.directions_walk_rounded,
  Icons.health_and_safety_rounded
];
const vitalColors = [
  Color(0xff8974dc),
  Color(0xffef9b58),
  Color(0xff64b8ad),
  Color(0xffe77691),
  Color(0xff698cdb),
  Color(0xff80b579)
];
String vitalClock(dynamic value) {
  final t = DateTime.fromMillisecondsSinceEpoch(vitalInt(value));
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String vitalDate(dynamic value) {
  final d = DateTime.fromMillisecondsSinceEpoch(vitalInt(value));
  return '${d.month}月${d.day}日';
}

Color moodTrendColor(num value) => value < 35
    ? const Color(0xff6488D8)
    : value < 50
        ? const Color(0xff8A83B8)
        : value < 65
            ? const Color(0xff44A9A1)
            : value < 82
                ? const Color(0xff39A873)
                : const Color(0xffE6A84B);

IconData moodTrendIcon(num value) => value < 35
    ? Icons.sentiment_very_dissatisfied_rounded
    : value < 50
        ? Icons.sentiment_dissatisfied_rounded
        : value < 65
            ? Icons.sentiment_neutral_rounded
            : value < 82
                ? Icons.sentiment_satisfied_alt_rounded
                : Icons.sentiment_very_satisfied_rounded;

String vitalDuration(int minutes) => '${minutes ~/ 60}小时${minutes % 60}分';
Map<String, dynamic>? latestSleep(Map<String, dynamic> s) {
  final list = vitalList(s['sleep_history']);
  return list.isEmpty ? null : list.last;
}

String metricValue(Map<String, dynamic> s, int index) {
  switch (index) {
    case 0:
      final sleep = latestSleep(s);
      return s['sleep'] is Map
          ? '睡眠中'
          : sleep == null
              ? '等待第一晚'
              : '${(vitalInt(sleep['minutes']) / 60).toStringAsFixed(1)} 小时';
    case 1:
      return BotVitalSignsService.instance.moodName(vitalDouble(s['mood'], 65));
    case 2:
      return '${vitalDouble(s['stress'], 3).toStringAsFixed(1)} / 10';
    case 3:
      return '${vitalDouble(s['weight'], 55).toStringAsFixed(1)} kg';
    case 4:
      return '${vitalInt(s['steps'])} 步';
    default:
      return '${s['health'] ?? '健康'}';
  }
}

String metricNote(Map<String, dynamic> s, int index) {
  switch (index) {
    case 0:
      final sleep = latestSleep(s);
      return sleep == null
          ? '睡眠结束后结算'
          : '睡眠质量 ${sleep['quality']} · 清醒${sleep['awake_minutes']}分';
    case 1:
      return '心情 ${vitalDouble(s['mood'], 65).round()} · 每小时更新';
    case 2:
      return vitalDouble(s['stress'], 3) < 4
          ? '节奏轻松，状态平稳'
          : '${s['activity'] ?? '日常活动'} · 注意休息';
    case 3:
      return '${vitalDouble(s['temperature'], 36.5).toStringAsFixed(1)} °C · ${vitalInt(s['heart'], 72)} 次/分';
    case 4:
      return '${s['activity'] ?? '根据日程逐时累计'}';
    default:
      return s['health'] == '健康'
          ? '生活与睡眠共同影响状态'
          : '${s['illness'] ?? ''} · 恢复${vitalDouble(s['recovery']).round()}%';
  }
}

List<Map<String, dynamic>> metricPoints(Map<String, dynamic> s, int index,
    {String body = 'weight', int days = 7}) {
  final now = DateTime.now();
  final since = (days == 1
          ? DateTime(now.year, now.month, now.day)
          : now.subtract(Duration(days: days)))
      .millisecondsSinceEpoch;
  if (index == 0)
    return vitalList(s['sleep_history'])
        .where((e) => vitalInt(e['end']) >= since)
        .map((e) => {
              'time': e['end'],
              'value': vitalInt(e['minutes']) / 60,
              'note':
                  '${vitalDuration(vitalInt(e['minutes']))} · 质量${e['quality']}'
            })
        .toList();
  final samples = vitalList(s['samples'])
      .where((e) => vitalInt(e['time']) >= since)
      .toList();
  final key = index == 1
      ? 'mood'
      : index == 2
          ? 'stress'
          : index == 3
              ? body
              : index == 4
                  ? 'steps'
                  : 'recovery';
  if ((index == 3 && body != 'heart') || (index == 4 && days > 1)) {
    final daily = <String, Map<String, dynamic>>{};
    for (final e in samples) {
      daily['${e['day']}'] = e;
    }
    return daily.values
        .map((e) => {
              'time': e['time'],
              'value': vitalDouble(
                  e[key], key == 'height' ? vitalDouble(s['height']) : 0),
              'note': index == 4 ? '${e['activity']}' : '${e['day']}'
            })
        .toList();
  }
  return samples
      .map((e) => {
            'time': e['time'],
            'value': vitalDouble(
                e[key], key == 'height' ? vitalDouble(s['height']) : 0),
            'note': index == 5 ? '${e['health']}' : '${e['activity']}'
          })
      .toList();
}

/// One square, generous typography and a quiet chart; no nested fixed heights.
class VitalMetricCard extends StatelessWidget {
  const VitalMetricCard(
      {super.key, required this.data, required this.index, this.onTap});
  final Map<String, dynamic> data;
  final int index;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final moodValue = vitalDouble(data['mood'], 65);
    final color = index == 1
        ? moodTrendColor(moodValue)
        : index == 0
            ? theme.primary
            : vitalColors[index];
    final points = metricPoints(data, index);
    return BouncyTap(
        onTap: onTap ?? () {},
        child: FrostCard(
            liquid: true,
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(index == 1 ? moodTrendIcon(moodValue) : vitalIcons[index],
                    color: color, size: 19),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(vitalTitles[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: theme.textStrong,
                            fontSize: 13,
                            fontWeight: FontWeight.w600))),
                Icon(Icons.chevron_right_rounded,
                    color: theme.textFaint, size: 17)
              ]),
              const SizedBox(height: 9),
              Text(metricValue(data, index),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      color: theme.textStrong)),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: VitalChart(
                          points: points,
                          color: color,
                          compact: true,
                          moodTrend: index == 1))),
              Text(metricNote(data, index),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10, height: 1.4, color: theme.textWeak)),
            ])));
  }
}

class VitalChart extends StatefulWidget {
  const VitalChart(
      {super.key,
      required this.points,
      required this.color,
      this.compact = false,
      this.moodTrend = false,
      this.onSelected});
  final List<Map<String, dynamic>> points;
  final Color color;
  final bool compact;
  final bool moodTrend;
  final ValueChanged<Map<String, dynamic>>? onSelected;
  @override
  State<VitalChart> createState() => _VitalChartState();
}

class _VitalChartState extends State<VitalChart> {
  int? selected;
  void pick(Offset local, double width) {
    if (widget.points.isEmpty) return;
    if (width <= 0) return;
    final i = (local.dx / width * (widget.points.length - 1))
        .round()
        .clamp(0, widget.points.length - 1);
    setState(() => selected = i);
    widget.onSelected?.call(widget.points[i]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    if (widget.points.isEmpty)
      return Center(
          child: Text(widget.compact ? '记录积累中' : '第一条记录生成后，趋势会显示在这里',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.textFaint, fontSize: widget.compact ? 10 : 13)));
    return LayoutBuilder(
        builder: (context, c) => GestureDetector(
            onTapDown: (d) => pick(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => pick(d.localPosition, c.maxWidth),
            child: CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _VitalPainter(
                    widget.points,
                    widget.color,
                    theme.textFaint,
                    widget.compact,
                    selected,
                    widget.moodTrend))));
  }
}

class _VitalPainter extends CustomPainter {
  _VitalPainter(this.points, this.color, this.ink, this.compact, this.selected,
      this.moodTrend);
  final List<Map<String, dynamic>> points;
  final Color color, ink;
  final bool compact, moodTrend;
  final int? selected;

  Color _colorAt(int index) =>
      moodTrend ? moodTrendColor(vitalDouble(points[index]['value'])) : color;

  @override
  void paint(Canvas canvas, Size size) {
    final top = compact ? 4.0 : 20.0;
    final bottom = compact ? 4.0 : 30.0;
    final values = points.map((e) => vitalDouble(e['value'])).toList();
    var low = values.reduce(min), high = values.reduce(max);
    if (high - low < 1) {
      low -= .5;
      high += .5;
    }
    final pad = (high - low) * .15;
    low -= pad;
    high += pad;
    Offset p(int i) => Offset(
          points.length == 1
              ? size.width / 2
              : i / (points.length - 1) * size.width,
          top +
              (1 - (values[i] - low) / (high - low)) *
                  (size.height - top - bottom),
        );
    final grid = Paint()
      ..color = ink.withValues(alpha: .15)
      ..strokeWidth = .7;
    for (var i = 0; i < 3; i++) {
      final y = top + i / 2 * (size.height - top - bottom);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final line = Path()..moveTo(p(0).dx, p(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(p(i).dx, p(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(p(points.length - 1).dx, size.height - bottom)
      ..lineTo(p(0).dx, size.height - bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .20), color.withValues(alpha: .01)],
        ).createShader(Offset.zero & size),
    );
    if (moodTrend && points.length > 1) {
      for (var i = 0; i < points.length - 1; i++) {
        final segment = Path()
          ..moveTo(p(i).dx, p(i).dy)
          ..lineTo(p(i + 1).dx, p(i + 1).dy);
        canvas.drawPath(
          segment,
          Paint()
            ..shader = LinearGradient(
              colors: [_colorAt(i), _colorAt(i + 1)],
            ).createShader(Rect.fromLTRB(p(i).dx, 0, p(i + 1).dx, size.height))
            ..strokeWidth = compact ? 2.4 : 3
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(
            p(i), compact ? 2 : 2.7, Paint()..color = _colorAt(i));
      }
    } else {
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..strokeWidth = compact ? 2 : 2.8
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (points.length == 1)
      canvas.drawCircle(p(0), 3, Paint()..color = _colorAt(0));
    if (selected != null && selected! < points.length) {
      final point = p(selected!);
      final selectedColor = _colorAt(selected!);
      canvas.drawLine(
        Offset(point.dx, top),
        Offset(point.dx, size.height - bottom),
        Paint()..color = selectedColor.withValues(alpha: .45),
      );
      canvas.drawCircle(point, 5, Paint()..color = selectedColor);
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }
    if (!compact) {
      for (final i in [0, points.length - 1]) {
        final text = TextPainter(
          text: TextSpan(
            text:
                '${vitalDate(points[i]['time'])} ${vitalClock(points[i]['time'])}',
            style: TextStyle(color: ink, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas,
            Offset(i == 0 ? 0 : size.width - text.width, size.height - 16));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VitalPainter old) => true;
}

class BotDataPage extends StatefulWidget {
  const BotDataPage({super.key, required this.botId, required this.botName});
  final String botId, botName;
  @override
  State<BotDataPage> createState() => _BotDataPageState();
}

class _BotDataPageState extends State<BotDataPage> {
  Map<String, dynamic>? data;
  Object? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final value = await BotVitalSignsService.instance.snapshot(widget.botId);
      if (mounted)
        setState(() {
          data = value;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TideBackground(
        child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
                title: const Text('TA的数据'),
                backgroundColor: Colors.transparent),
            body: data == null
                ? Center(
                    child: error == null
                        ? const CircularProgressIndicator()
                        : TextButton(
                            onPressed: load, child: const Text('读取失败，点击重试')))
                : RefreshIndicator(
                    onRefresh: load,
                    child: ListView(
                        addRepaintBoundaries: true,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          Text('${widget.botName} 的生活轨迹',
                              style: TextStyle(
                                  color: theme.textStrong,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(
                              '${data!['sleep'] is Map ? '正在休息' : '${data!['activity'] ?? '日常生活'}'} · 最近更新 ${vitalClock(vitalInt(data!['last_hour']) * 3600000)}',
                              style: TextStyle(
                                  color: theme.textWeak, fontSize: 12)),
                          const SizedBox(height: 20),
                          GridView.builder(
                              addRepaintBoundaries: true,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 6,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 14,
                                      crossAxisSpacing: 14,
                                      childAspectRatio: 1),
                              itemBuilder: (context, i) => VitalMetricCard(
                                  data: data!,
                                  index: i,
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          allowSnapshotting: false,
                                          builder: (_) => VitalDetailPage(
                                              botId: widget.botId,
                                              botName: widget.botName,
                                              index: i))))),
                          const SizedBox(height: 20),
                          FrostCard(
                              child: Text(
                                  '睡眠、日程和心情共同构成TA的生活节奏。点击曲线可以查看具体记录。身高保持稳定，体重与体温每日更新，平均心率、心情、压力和步数每小时更新。',
                                  style: TextStyle(
                                      color: theme.textWeak,
                                      height: 1.6,
                                      fontSize: 12))),
                        ]))));
  }
}

class VitalDetailPage extends StatefulWidget {
  const VitalDetailPage(
      {super.key,
      required this.botId,
      required this.botName,
      required this.index});
  final String botId, botName;
  final int index;
  @override
  State<VitalDetailPage> createState() => _VitalDetailPageState();
}

class _VitalDetailPageState extends State<VitalDetailPage> {
  Map<String, dynamic>? data, selected;
  int days = 7;
  String body = 'weight';
  Map<String, dynamic>? sleep;
  Timer? timer;
  Object? error;
  late final TextEditingController _heightCtrl,
      _weightCtrl,
      _temperatureCtrl,
      _heartCtrl;
  final _bodyCardKey = GlobalKey();
  bool _bodyLifted = false, _bodyEditing = false, _savingBody = false;
  @override
  void initState() {
    super.initState();
    _heightCtrl = TextEditingController();
    _weightCtrl = TextEditingController();
    _temperatureCtrl = TextEditingController();
    _heartCtrl = TextEditingController();
    load();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _temperatureCtrl.dispose();
    _heartCtrl.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final v = await BotVitalSignsService.instance.snapshot(widget.botId);
      if (mounted)
        setState(() {
          data = v;
          error = null;
          sleep ??= v['sleep'] is Map
              ? Map<String, dynamic>.from(v['sleep'] as Map)
              : latestSleep(v);
        });
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Widget text(String value, {double size = 14, Color? color}) => Text(value,
      style: TextStyle(
          fontSize: size,
          color: color ?? TideTheme.of(context).textStrong,
          height: 1.5));
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context),
        i = widget.index,
        color = i == 1
            ? moodTrendColor(vitalDouble(data?['mood'], 65))
            : i == 0
                ? theme.primary
                : vitalColors[i];
    if (data == null)
      return TideBackground(
          child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                  title: Text(vitalTitles[i]),
                  backgroundColor: Colors.transparent),
              body: Center(
                  child: error == null
                      ? const CircularProgressIndicator()
                      : TextButton(
                          onPressed: load, child: const Text('读取失败，点击重试')))));
    final points = metricPoints(data!, i, body: body, days: days);
    final samples = vitalList(data!['samples']);
    final clock = DateTime.now();
    final since = (days == 1
            ? DateTime(clock.year, clock.month, clock.day)
            : clock.subtract(Duration(days: days)))
        .millisecondsSinceEpoch;
    final recent = samples
        .where((e) => vitalInt(e['time']) >= since)
        .toList()
        .reversed
        .take(48)
        .toList();
    final values = points.map((p) => vitalDouble(p['value'])).toList();
    return TideBackground(
        child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
                title: Text(vitalTitles[i]),
                backgroundColor: Colors.transparent),
            body: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
                    children: [
                      Row(children: [
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(18)),
                            child: Icon(
                                i == 1
                                    ? moodTrendIcon(
                                        vitalDouble(data?['mood'], 65))
                                    : vitalIcons[i],
                                color: color,
                                size: 26)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              text('${widget.botName} · ${vitalTitles[i]}',
                                  size: 12, color: theme.textWeak),
                              text(metricValue(data!, i), size: 30)
                            ]))
                      ]),
                      const SizedBox(height: 12),
                      text(metricNote(data!, i),
                          size: 13, color: theme.textWeak),
                      const SizedBox(height: 18),
                      Wrap(spacing: 8, runSpacing: 10, children: [
                        for (final d in [1, 7, 30])
                          _buildPeriodChip(
                              theme, d == 1 ? '今天' : '近$d天', days == d, () {
                            setState(() {
                              days = d;
                              selected = null;
                            });
                          })
                      ]),
                      if (i == 3)
                        Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Wrap(spacing: 8, runSpacing: 10, children: [
                              for (final e in {
                                'height': '身高',
                                'weight': '体重',
                                'temperature': '体温',
                                'heart': '平均心率'
                              }.entries)
                                _buildPeriodChip(theme, e.value, body == e.key,
                                    () {
                                  setState(() {
                                    body = e.key;
                                    selected = null;
                                  });
                                })
                            ])),
                      const SizedBox(height: 14),
                      FrostCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            text('变化趋势', size: 16),
                            if (i == 1) ...[
                              const SizedBox(height: 10),
                              Wrap(spacing: 12, runSpacing: 8, children: [
                                for (final value in [20, 40, 55, 70, 90])
                                  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(moodTrendIcon(value),
                                            size: 14,
                                            color: moodTrendColor(value)),
                                        const SizedBox(width: 4),
                                        text(
                                            BotVitalSignsService.instance
                                                .moodName(value),
                                            size: 11,
                                            color: moodTrendColor(value)),
                                      ]),
                              ]),
                            ],
                            const SizedBox(height: 12),
                            SizedBox(
                                height: 190,
                                child: VitalChart(
                                    points: points,
                                    color: color,
                                    moodTrend: i == 1,
                                    onSelected: (p) => setState(() {
                                          selected = p;
                                          if (i == 0) {
                                            final matches = vitalList(
                                                    data!['sleep_history'])
                                                .where((e) =>
                                                    e['end'] == p['time']);
                                            if (matches.isNotEmpty)
                                              sleep = matches.first;
                                          }
                                        }))),
                            const SizedBox(height: 12),
                            text(
                                selected == null
                                    ? '点击或滑动曲线，查看时间与数值'
                                    : '${vitalDate(selected!['time'])} ${vitalClock(selected!['time'])} · ${vitalDouble(selected!['value']).toStringAsFixed(1)}\n${selected!['note'] ?? ''}',
                                size: 12,
                                color: theme.textWeak)
                          ])),
                      const SizedBox(height: 14),
                      if (values.isNotEmpty)
                        FrostCard(
                            child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                              stat(
                                  '平均',
                                  (values.reduce((a, b) => a + b) /
                                          values.length)
                                      .toStringAsFixed(1)),
                              stat('最高', values.reduce(max).toStringAsFixed(1)),
                              stat('最低', values.reduce(min).toStringAsFixed(1))
                            ])),
                      if (i == 0) ...sleepContent(theme),
                      if (i == 3) ...[
                        const SizedBox(height: 16),
                        _buildDisplayBodyCard(theme),
                      ],
                      if (i == 5) ...[
                        const SizedBox(height: 16),
                        FrostCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              text('当前状况', size: 16),
                              const SizedBox(height: 8),
                              text(data!['health'] == '健康'
                                  ? '状态平稳，继续保持自己的生活节奏。'
                                  : '${data!['illness']}，${data!['health']}。恢复进度 ${vitalDouble(data!['recovery']).round()}%。'),
                              if (data!['health'] != '健康') ...[
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                    value: vitalDouble(data!['recovery']) / 100,
                                    color: color)
                              ]
                            ]))
                      ],
                      if (i != 0) ...[
                        const SizedBox(height: 22),
                        text('记录明细', size: 18),
                        const SizedBox(height: 10),
                        if (recent.isEmpty)
                          text('还没有历史记录。', color: theme.textWeak),
                        for (final e in recent)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: FrostCard(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(children: [
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          text(
                                              '${vitalDate(e['time'])} ${vitalClock(e['time'])}',
                                              size: 12),
                                          text('${e['activity'] ?? '日常生活'}',
                                              size: 11, color: theme.textWeak)
                                        ])),
                                    text(i == 1
                                        ? '${BotVitalSignsService.instance.moodName(vitalDouble(e['mood']))} ${vitalDouble(e['mood']).round()}'
                                        : i == 2
                                            ? '${vitalDouble(e['stress']).toStringAsFixed(1)} / 10'
                                            : i == 3
                                                ? vitalDouble(e[body])
                                                    .toStringAsFixed(1)
                                                : i == 4
                                                    ? '${e['steps']} 步'
                                                    : '${e['health']}')
                                  ])))
                      ]
                    ]))));
  }

  Widget stat(String title, String value) => Column(children: [
        text(value, size: 20),
        text(title, size: 11, color: TideTheme.of(context).textWeak)
      ]);
  Widget info(String name, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: text(name, color: TideTheme.of(context).textWeak)),
        text(value)
      ]));
  List<Widget> sleepContent(TideTheme theme) {
    final sleeps = vitalList(data!['sleep_history']).reversed.toList();
    if (data!['sleep'] is Map)
      sleeps.insert(0, Map<String, dynamic>.from(data!['sleep'] as Map));
    if (sleeps.isEmpty)
      return [
        const SizedBox(height: 18),
        FrostCard(child: text('今晚的睡眠结束后，会在这里展示睡眠时长、清醒时段与质量。'))
      ];
    final current = sleeps.firstWhere((e) => e['start'] == sleep?['start'],
        orElse: () => sleeps.first);
    final end = vitalInt(
        current['end'],
        min(DateTime.now().millisecondsSinceEpoch,
            vitalInt(current['planned_end'])));
    final settled = settleSleep({...current, 'end': end});
    final segments = sleepSegments(current, until: end);
    return [
      const SizedBox(height: 18),
      text('睡眠时间线', size: 18),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 10, children: [
        for (final e in sleeps.where((e) =>
            vitalInt(e['end'], vitalInt(e['planned_end'])) >=
            (days == 1
                    ? DateTime(DateTime.now().year, DateTime.now().month,
                        DateTime.now().day)
                    : DateTime.now().subtract(Duration(days: days)))
                .millisecondsSinceEpoch))
          _buildPeriodChip(
              theme, vitalDate(e['start']), current['start'] == e['start'], () {
            setState(() => sleep = e);
          })
      ]),
      const SizedBox(height: 12),
      FrostCard(
          child: Column(children: [
        info('入睡',
            '${vitalDate(current['start'])} ${vitalClock(current['start'])}'),
        info(current['end'] == null ? '预计起床' : '起床',
            '${vitalDate(current['planned_end'])} ${vitalClock(current['planned_end'])}'),
        info('实际睡眠', vitalDuration(vitalInt(settled['minutes']))),
        info('清醒合计', vitalDuration(vitalInt(settled['awake_minutes']))),
        info(current['end'] == null ? '质量' : '睡眠质量',
            current['end'] == null ? '醒来后结算' : '${settled['quality']} / 100'),
        const SizedBox(height: 10),
        _buildSleepTimeline(theme, segments),
        const SizedBox(height: 12),
      ])),
      const SizedBox(height: 16),
      for (final e in segments)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
                onTap: () => showSegment(e),
                borderRadius: BorderRadius.circular(16),
                child: FrostCard(
                    padding: const EdgeInsets.all(13),
                    child: Row(children: [
                      SleepStateMark(
                          asleep: e['state'] == '睡眠',
                          color: e['state'] == '睡眠'
                              ? theme.primary
                              : const Color(0xffc89e65)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            text(
                                '${vitalClock(e['start'])} — ${vitalClock(e['end'])} · ${e['state']}',
                                size: 13),
                            text(
                                '${e['reason']} · ${vitalDuration((vitalInt(e['end']) - vitalInt(e['start'])) ~/ 60000)}',
                                size: 11,
                                color: theme.textWeak)
                          ])),
                      Icon(Icons.chevron_right_rounded, color: theme.textFaint)
                    ]))))
    ];
  }

  Widget _buildPeriodChip(
          TideTheme theme, String label, bool selected, VoidCallback onTap) =>
      BouncyTap(
          onTap: onTap,
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: selected
                    ? theme.primary
                    : Colors.white.withValues(alpha: 0.9),
                boxShadow: selected
                    ? [
                        BoxShadow(
                            color: theme.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ]
                    : [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ],
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? Colors.white : theme.textStrong))));

  Widget _bodyReadOnly(TideTheme theme) => FrostCard(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        info('身高', '${vitalDouble(data!['height']).toStringAsFixed(1)} cm'),
        info('体重', '${vitalDouble(data!['weight']).toStringAsFixed(1)} kg'),
        info(
            '体温', '${vitalDouble(data!['temperature']).toStringAsFixed(1)} °C'),
        info('平均心率', '${vitalInt(data!['heart'], 72)} 次/分'),
      ]));

  Widget _buildDisplayBodyCard(TideTheme theme) => GestureDetector(
      onLongPressDown: (_) => setState(() => _bodyLifted = true),
      onLongPressCancel: () => setState(() => _bodyLifted = false),
      onLongPress: _showBodyEditor,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
        scale: _bodyLifted ? 1.025 : 1,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
          offset: _bodyLifted ? const Offset(0, -.025) : Offset.zero,
          child: Opacity(
            opacity: _bodyEditing ? 0 : 1,
            child: AnimatedContainer(
              key: _bodyCardKey,
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: _bodyLifted ? .10 : 0),
                    blurRadius: _bodyLifted ? 28 : 0,
                    offset: Offset(0, _bodyLifted ? 14 : 0),
                  )
                ],
              ),
              child: _bodyReadOnly(theme),
            ),
          ),
        ),
      ));

  Future<void> _showBodyEditor() async {
    if (_bodyEditing) return;
    final box = _bodyCardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    _heightCtrl.text = vitalDouble(data!['height']).toStringAsFixed(1);
    _weightCtrl.text = vitalDouble(data!['weight']).toStringAsFixed(1);
    _temperatureCtrl.text =
        vitalDouble(data!['temperature']).toStringAsFixed(1);
    _heartCtrl.text = '${vitalInt(data!['heart'], 72)}';
    final preview = _bodyReadOnly(TideTheme.of(context));
    setState(() {
      _bodyEditing = true;
      _bodyLifted = false;
    });
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭身体指标编辑',
        barrierColor: Colors.black.withValues(alpha: .30),
        transitionDuration: const Duration(milliseconds: 560),
        pageBuilder: (dialogContext, _, __) => StatefulBuilder(
          builder: (dialogContext, refresh) => Material(
            color: Colors.transparent,
            child: _buildEditableBodyCard(
                TideTheme.of(dialogContext), dialogContext, refresh),
          ),
        ),
        transitionBuilder: (dialogContext, animation, _, child) {
          final media = MediaQuery.of(dialogContext);
          final top = media.padding.top + 20;
          final available = max(
              0.0,
              media.size.height -
                  top -
                  max(media.viewInsets.bottom, media.padding.bottom) -
                  20);
          final height = min(390.0 * media.textScaler.scale(1), available);
          final width = min(media.size.width - 32, 440.0);
          final target = Rect.fromLTWH((media.size.width - width) / 2,
              top + (available - height) / 2, width, height);
          final progress =
              Curves.easeInOutCubicEmphasized.transform(animation.value);
          final rect = Rect.lerp(origin, target, progress)!;
          return Stack(children: [
            Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SingleChildScrollView(
                  child: Stack(children: [
                    Opacity(opacity: 1 - progress, child: preview),
                    Opacity(
                        opacity: progress,
                        child: IgnorePointer(
                            ignoring: progress < .95, child: child)),
                  ]),
                ),
              ),
            ),
          ]);
        },
      );
    } finally {
      if (mounted)
        setState(() {
          _bodyEditing = false;
          _savingBody = false;
        });
    }
  }

  Widget _buildEditableBodyCard(
          TideTheme theme, BuildContext dialogContext, StateSetter refresh) =>
      FrostCard(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: text('身体指标', size: 18)),
            IconButton(
                tooltip: '取消',
                onPressed:
                    _savingBody ? null : () => Navigator.pop(dialogContext),
                icon:
                    Icon(Icons.close_rounded, size: 20, color: theme.textWeak)),
          ]),
          _editField('身高', _heightCtrl, 'cm'),
          _editField('体重', _weightCtrl, 'kg'),
          _editField('体温', _temperatureCtrl, '°C'),
          _editField('平均心率', _heartCtrl, '次/分'),
          const SizedBox(height: 12),
          SizedBox(
              width: double.infinity,
              child: TideDialogs.glassButton(_savingBody ? '保存中…' : '保存',
                  color: theme.primary, onTap: () async {
                if (_savingBody) return;
                final h = double.tryParse(_heightCtrl.text);
                final w = double.tryParse(_weightCtrl.text);
                final t = double.tryParse(_temperatureCtrl.text);
                final hr = int.tryParse(_heartCtrl.text);
                if (h == null ||
                    !h.isFinite ||
                    h <= 0 ||
                    w == null ||
                    !w.isFinite ||
                    w <= 0 ||
                    t == null ||
                    !t.isFinite ||
                    t < 30 ||
                    t > 45 ||
                    hr == null ||
                    hr < 45 ||
                    hr > 135) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('请输入有效的身体指标，平均心率范围为 45–135')));
                  return;
                }
                refresh(() => _savingBody = true);
                try {
                  await BotVitalSignsService.instance.updateBodyMetrics(
                      widget.botId,
                      height: h,
                      weight: w,
                      temperature: t,
                      heart: hr);
                  await load();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (_) {
                  if (dialogContext.mounted) refresh(() => _savingBody = false);
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('保存失败，请稍后重试')));
                }
              })),
        ]),
      );
  Widget _editField(String label, TextEditingController ctrl, String unit) {
    final theme = TideTheme.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: text(label, color: theme.textWeak)),
          SizedBox(
              width: 80,
              child: TextField(
                  controller: ctrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 14, color: theme.textStrong),
                  decoration: const InputDecoration(
                      isDense: true, border: InputBorder.none))),
          text(' $unit', size: 14)
        ]));
  }

  void showSegment(Map<String, dynamic> e) => showTideDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = TideTheme.of(dialogContext);
        final asleep = e['state'] == '睡眠';
        final color = asleep ? theme.primary : const Color(0xffedb66f);
        return TideDialogSurface(
          child: TideDialogs.glassContent(
            context: dialogContext,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SleepStateMark(asleep: asleep, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text('${e['state']}',
                        style: TextStyle(
                            color: theme.textStrong,
                            fontSize: 22,
                            fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 14),
              Text('${e['reason'] ?? ''}',
                  style: TextStyle(color: theme.textWeak, height: 1.5)),
              const SizedBox(height: 12),
              info('开始', '${vitalDate(e['start'])} ${vitalClock(e['start'])}'),
              info('结束', '${vitalDate(e['end'])} ${vitalClock(e['end'])}'),
              info(
                  '持续时间',
                  vitalDuration(
                      (vitalInt(e['end']) - vitalInt(e['start'])) ~/ 60000)),
              const SizedBox(height: 18),
              SizedBox(
                  width: double.infinity,
                  child: TideDialogs.glassButton('完成',
                      color: theme.primary,
                      onTap: () => Navigator.pop(dialogContext))),
            ],
          ),
        );
      });

  Widget _buildSleepTimeline(
          TideTheme theme, List<Map<String, dynamic>> segments) =>
      SleepTimeline(segments: segments, onSelect: showSegment);
}
