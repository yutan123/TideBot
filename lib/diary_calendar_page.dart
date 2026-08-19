import 'package:flutter/material.dart';

import 'db.dart';
import 'theme.dart';

class DiaryCalendarPage extends StatefulWidget {
  final String botId;
  final String botName;
  const DiaryCalendarPage(
      {super.key, required this.botId, required this.botName});

  @override
  State<DiaryCalendarPage> createState() => _DiaryCalendarPageState();
}

class _DiaryCalendarPageState extends State<DiaryCalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Set<String> _dates = <String>{};
  bool _loading = true;

  String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  Future<void> _loadDates() async {
    final rows = await DBManager().queryDiaryDates(widget.botId);
    if (!mounted) return;
    setState(() {
      _dates = rows.map((row) => row['date_key'].toString()).toSet();
      _loading = false;
    });
  }

  Future<void> _open(DateTime date) async {
    final diary = await DBManager().getDiary(widget.botId, _key(date));
    if (!mounted || diary == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiaryDetailPage(
          botName: widget.botName,
          dateKey: _key(date),
          content: diary['content']?.toString() ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = (first.weekday - 1) % 7;
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
        title: Text('${widget.botName}的日记'),
        backgroundColor: theme.bgColor,
        actions: [
          IconButton(
            tooltip: '回到本月',
            icon: const Icon(Icons.today_rounded),
            onPressed: () => setState(() =>
                _month = DateTime(DateTime.now().year, DateTime.now().month)),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primary))
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                          onPressed: () => setState(() =>
                              _month = DateTime(_month.year, _month.month - 1)),
                          icon: const Icon(Icons.chevron_left_rounded)),
                      Text('${_month.year}年${_month.month}月',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: theme.textStrong)),
                      IconButton(
                          onPressed: () => setState(() =>
                              _month = DateTime(_month.year, _month.month + 1)),
                          icon: const Icon(Icons.chevron_right_rounded)),
                    ],
                  ),
                  Row(
                      children: ['一', '二', '三', '四', '五', '六', '日']
                          .map((label) => Expanded(
                              child: Center(
                                  child: Text(label,
                                      style: TextStyle(
                                          color: theme.textFaint,
                                          fontFamily: 'TideFont')))))
                          .toList()),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    itemCount: leading + days,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 4),
                    itemBuilder: (_, index) {
                      if (index < leading) return const SizedBox.shrink();
                      final day = index - leading + 1;
                      final date = DateTime(_month.year, _month.month, day);
                      final hasDiary = _dates.contains(_key(date));
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: hasDiary ? () => _open(date) : null,
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$day',
                                  style: TextStyle(
                                      color: hasDiary
                                          ? theme.textStrong
                                          : theme.textFaint,
                                      fontWeight: hasDiary
                                          ? FontWeight.w700
                                          : FontWeight.w400)),
                              const SizedBox(height: 4),
                              Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hasDiary
                                          ? theme.primary
                                          : Colors.transparent)),
                            ]),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text('点击有标记的日期查看全文',
                          style: TextStyle(
                              color: theme.textFaint, fontFamily: 'TideFont'))),
                ],
              ),
            ),
    );
  }
}

class DiaryDetailPage extends StatelessWidget {
  final String botName;
  final String dateKey;
  final String content;
  const DiaryDetailPage(
      {super.key,
      required this.botName,
      required this.dateKey,
      required this.content});

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar:
          AppBar(title: Text('$botName的日记'), backgroundColor: theme.bgColor),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateKey,
                        style: TextStyle(
                            color: theme.primary,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'TideFont')),
                    const SizedBox(height: 20),
                    Text(content,
                        style: TextStyle(
                            color: theme.textStrong,
                            fontSize: 17,
                            height: 1.7,
                            fontFamily: 'TideFont')),
                  ]))),
    );
  }
}
