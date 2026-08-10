import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'ui_components.dart';
import 'db.dart';
import 'theme.dart';
import 'ai.dart';
import 'game_arena_page.dart';
import 'memory_manager_page.dart';

// ==================== 空间页 ====================
class SpacePage extends StatefulWidget {
  final PageController? pageController;
  const SpacePage({super.key, this.pageController});
  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  String _botId = '';
  String _botName = '';
  String _dailyQuote = '';
  int _daysSince = 0;
  String _moodIcon = 'smile';
  String _moodLabel = '';
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _memories = [];
  final ScrollController _diaryScrollController = ScrollController();
  Timer? _diaryTimer;
  bool _diaryAutoScrolling = false;
  int _diaryScrollIndex = 0;
  bool _loading = true;
  final Map<String, IconData> _moodIcons = {
    'smile': Icons.sentiment_satisfied_rounded,
    'heart': Icons.favorite_rounded,
    'sad': Icons.sentiment_dissatisfied_rounded,
    'angry': Icons.sentiment_very_dissatisfied_rounded,
    'sleep': Icons.bedtime_rounded,
    'think': Icons.psychology_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _diaryTimer?.cancel();
    _diaryScrollController.dispose();
    super.dispose();
  }

  void _toggleDiaryAutoScroll() {
    if (_memories.length < 2) return;
    if (_diaryAutoScrolling) {
      _diaryTimer?.cancel();
      setState(() => _diaryAutoScrolling = false);
      return;
    }
    setState(() => _diaryAutoScrolling = true);
    _diaryTimer?.cancel();
    _diaryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_diaryScrollController.hasClients) return;
      _diaryScrollIndex = (_diaryScrollIndex + 1) % _memories.length;
      final maxExtent = _diaryScrollController.position.maxScrollExtent;
      final target = _memories.length <= 1
          ? 0.0
          : maxExtent * _diaryScrollIndex / (_memories.length - 1);
      _diaryScrollController.animateTo(target,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  Future<void> _loadData() async {
    final db = DBManager();
    final bots = await db.queryBots();
    if (bots.isNotEmpty) {
      // 选择跨页面/重启持久化；当机器人被删除时再安全回退到首个。
      final savedBotId = await db.getKV('space_selected_bot_id') ?? '';
      Map<String, dynamic>? b;
      final preferredId = _botId.isNotEmpty ? _botId : savedBotId;
      if (preferredId.isNotEmpty) {
        try {
          b = bots.firstWhere((x) => x['id'] == preferredId);
        } catch (_) {
          b = null;
        }
      }
      b ??= bots.first;
      _botId = b['id'] as String? ?? '';
      await db.setKV('space_selected_bot_id', _botId);
      _botName = b['name'] as String? ?? '';
      _dailyQuote = b['daily_quote'] as String? ?? '';
      final created = b['created_at'];
      final createdMillis = created is num
          ? created.toInt()
          : int.tryParse(created?.toString() ?? '');
      final metAt = createdMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(createdMillis)
          : DateTime.tryParse(created?.toString() ?? '') ?? DateTime.now();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final metDate = DateTime(metAt.year, metAt.month, metAt.day);
      _daysSince = (today.difference(metDate).inDays + 1).clamp(1, 1 << 30);
      final sch = await db.querySchedules(_botId, limit: 3);
      final mem = await db.queryMemories(_botId, type: 'medium', limit: 50);
      final messages = await db.queryMessages(_botId, limit: 30);
      final latestMood = messages.reversed.firstWhere(
        (m) =>
            m['role'] == 'assistant' &&
            (m['mood']?.toString().isNotEmpty ?? false),
        orElse: () => <String, dynamic>{},
      );
      final mood = latestMood['mood']?.toString() ?? '平静';
      _moodLabel = mood;
      _moodIcon = mood == '开心'
          ? 'smile'
          : mood == '伤心'
              ? 'sad'
              : mood == '生气'
                  ? 'angry'
                  : 'think';
      _schedules = sch;
      _memories = mem;
      if (_diaryScrollIndex >= _memories.length) _diaryScrollIndex = 0;
      // Generates once per calendar day and returns cached text on later opens.
      if (_dailyQuote.isEmpty ||
          await db.getKV('quote_date_$_botId') !=
              '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}') {
        _dailyQuote = await AIManager().getDailyQuote(_botId);
      }
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } else {
      _daysSince = 0;
      _dailyQuote = '';
      _schedules = [];
      _memories = [];
      _botId = '';
      _botName = '';
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showScheduleDetail(Map<String, dynamic> s) {
    final theme = TideTheme.of(context);
    showTideSheet(
        context: context,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['title'] ?? '',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: theme.textStrong,
                      fontFamily: 'TideFont')),
              const SizedBox(height: 8),
              Text(s['note'] ?? '',
                  style: TextStyle(
                      fontSize: 15,
                      color: theme.textWeak,
                      fontFamily: 'TideFont')),
              const SizedBox(height: 12),
              Text(formatTime(s['time']),
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.textFaint,
                      fontFamily: 'TideFont'))
            ])));
  }

  Future<void> _openMemoryManager() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                MemoryManagerPage(botId: _botId, botName: _botName)));
    if (mounted) _loadData();
  }

  void _showMemoryDetail(Map<String, dynamic> m) {
    final theme = TideTheme.of(context);
    showTideSheet(
        context: context,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['content'] ?? '',
                  style: TextStyle(
                      fontSize: 15,
                      color: theme.textStrong,
                      fontFamily: 'TideFont',
                      height: 1.5)),
              const SizedBox(height: 12),
              Text(formatTime(m['timestamp']),
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.textFaint,
                      fontFamily: 'TideFont'))
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr = '${now.year}.${now.month}.${now.day}';
    return Scaffold(
        backgroundColor: theme.bgColor,
        body: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(timeStr, dateStr, theme),
                        const SizedBox(height: 20),
                        if (_botId.isNotEmpty) ...[
                          _buildQuoteCard(theme),
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(child: _buildDaysCard(theme)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildMoodCard(theme))
                          ]),
                        ] else
                          const FrostCard(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                  child: Text('还没有创建机器人\n点击底部聊天 Tab 开始',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 15,
                                          color: Color(0xFF8E8E93),
                                          fontFamily: 'TideFont',
                                          height: 1.6)))),
                        const SizedBox(height: 16),
                        if (_schedules.isNotEmpty) ...[
                          _buildSectionTitle('最近日程'),
                          const SizedBox(height: 8),
                          ..._schedules.map((s) => BouncyTap(
                              onTap: () => _showScheduleDetail(s),
                              child: _buildScheduleCard(s, theme))),
                        ],
                        if (_botId.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(child: _buildSectionTitle('TA 的日记')),
                            TextButton.icon(
                              onPressed: _openMemoryManager,
                              icon: const Icon(Icons.open_in_full_rounded,
                                  size: 16),
                              label: const Text('管理',
                                  style: TextStyle(fontFamily: 'TideFont')),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          if (_memories.isEmpty)
                            Text('TA 还没有写下日记',
                                style: TextStyle(
                                    color: theme.textFaint,
                                    fontFamily: 'TideFont'))
                          else
                            GestureDetector(
                              onTap: _toggleDiaryAutoScroll,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 196,
                                    child: ListView.separated(
                                      controller: _diaryScrollController,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      padding: EdgeInsets.zero,
                                      itemCount: _memories.length,
                                      separatorBuilder: (_, __) => Divider(
                                          height: 1,
                                          thickness: 0.5,
                                          color: theme.divider),
                                      itemBuilder: (_, index) {
                                        final m = _memories[index];
                                        return BouncyTap(
                                          onTap: () => _showMemoryDetail(m),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(m['content'] ?? '',
                                                    style: TextStyle(
                                                        fontSize: 14,
                                                        height: 1.4,
                                                        color: theme.textStrong,
                                                        fontFamily:
                                                            'TideFont')),
                                                if (m['timestamp'] != null) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                      formatTime(
                                                          m['timestamp']),
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              theme.textFaint,
                                                          fontFamily:
                                                              'TideFont')),
                                                ],
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _memories.length < 2
                                        ? '点击查看正文'
                                        : _diaryAutoScrolling
                                            ? '正在每 5 秒滚动 · 点击此处停止'
                                            : '点击日记区域后，每 5 秒自动滚动',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: theme.textFaint,
                                        fontFamily: 'TideFont'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ])),
        ));
  }

  Widget _buildHeader(String time, String date, TideTheme theme) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(time,
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                  fontFamily: 'TideFont',
                  color: theme.textStrong)),
          Text(date,
              style: TextStyle(
                  fontSize: 14, color: theme.textWeak, fontFamily: 'TideFont')),
        ]),
        if (_botId.isNotEmpty)
          BouncyTap(
              onTap: () async {
                final db = DBManager();
                final bots = await db.queryBots();
                if (!mounted) return;
                showTideSheet(
                    context: context,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(height: 12),
                      const Text('切换机器人',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'TideFont')),
                      const SizedBox(height: 12),
                      ...bots.map((b) => Column(children: [
                            ListTile(
                              title: Text(b['name'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      const TextStyle(fontFamily: 'TideFont')),
                              trailing: _botId == b['id']
                                  ? Icon(Icons.check_rounded,
                                      color: TideTheme.of(context).primary)
                                  : null,
                              onTap: () async {
                                final selectedId = b['id'] as String? ?? '';
                                await db.setKV(
                                    'space_selected_bot_id', selectedId);
                                if (!mounted) return;
                                setState(() {
                                  _botId = selectedId;
                                  _botName = b['name'] as String? ?? '';
                                });
                                Navigator.pop(context);
                                _loadData();
                              },
                            ),
                            const Divider(height: 1),
                          ])),
                    ]));
              },
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: theme.surface
                          .withValues(alpha: theme.isDark ? 0.82 : 0.80),
                      border: Border.all(color: theme.border)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_botName,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'TideFont',
                            color: theme.primary)),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: theme.primary)
                  ]))),
      ]);

  Widget _buildQuoteCard(TideTheme theme) => FrostCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.format_quote_rounded, color: theme.primary, size: 20),
          const SizedBox(width: 8),
          Text('今日一言',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'TideFont',
                  color: theme.primary))
        ]),
        const SizedBox(height: 10),
        Text(_dailyQuote.isNotEmpty ? _dailyQuote : '点击刷新今日一言',
            style: TextStyle(
                fontSize: 16,
                fontFamily: 'TideFont',
                color:
                    _dailyQuote.isNotEmpty ? theme.textStrong : theme.textFaint,
                height: 1.5))
      ]));

  Widget _buildDaysCard(TideTheme theme) => FrostCard(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Text('$_daysSince',
            style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w300,
                fontFamily: 'TideFont',
                color: theme.primary)),
        const SizedBox(height: 4),
        const Text('相遇天数',
            style: TextStyle(
                fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont'))
      ]));
  Widget _buildMoodCard(TideTheme theme) {
    final icon = _moodIcons[_moodIcon] ?? Icons.sentiment_satisfied_rounded;
    return FrostCard(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Icon(icon, size: 36, color: theme.primary),
          const SizedBox(height: 4),
          Text(_moodLabel,
              style: TextStyle(
                  fontSize: 13,
                  color: theme.textStrong,
                  fontFamily: 'TideFont')),
          const SizedBox(height: 8),
          Text('由 TA 的最近回复决定',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  color: theme.textFaint,
                  fontFamily: 'TideFont')),
        ]));
  }

  Widget _buildSectionTitle(String title) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFamily: 'TideFont',
              color: TideTheme.of(context).textStrong)));

  Widget _buildScheduleCard(Map<String, dynamic> s, TideTheme theme) =>
      FrostCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: theme.primary)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(s['title'] ?? '',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'TideFont')),
                  if ((s['note'] ?? '').toString().isNotEmpty)
                    Text(s['note'] ?? '',
                        style: TextStyle(fontSize: 13, color: theme.textWeak),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                ])),
            Text(formatTime(s['time']),
                style: TextStyle(
                    fontSize: 13,
                    color: theme.textWeak,
                    fontFamily: 'TideFont'))
          ]));
}

// ==================== 广场页 ====================
class SquarePage extends StatefulWidget {
  final GlobalKey<SquarePageState>? pageKey;
  const SquarePage({super.key, this.pageKey});
  @override
  State<SquarePage> createState() => SquarePageState();
}

class SquarePageState extends State<SquarePage>
    with SingleTickerProviderStateMixin {
  bool _showGames = false;
  late AnimationController _switchCtrl;
  late Animation<Offset> _slideAnim;
  final ScrollController _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _feeds = [];
  int _feedPage = 0;
  static const _pageSize = 10;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _showParticles = false;
  int _particleRun = 0;
  final List<Offset> _particleOrigins = [];
  final _games = [
    {'name': '五子棋', 'desc': '和 TA 真实对弈', 'icon': 'grid'},
    {'name': '井字棋', 'desc': '和 TA 真实对弈', 'icon': 'circle'},
    {'name': '20问猜物', 'desc': '由 TA 发问和猜测', 'icon': 'help'},
    {'name': '斗地主', 'desc': '32 张牌双人对局', 'icon': 'casino'},
  ];
  final Map<String, IconData> _gameIcons = {
    'grid': Icons.grid_4x4_rounded,
    'circle': Icons.circle_outlined,
    'help': Icons.help_outline_rounded,
    'casino': Icons.casino_rounded,
    'book': Icons.menu_book_rounded,
    'favorite': Icons.favorite_rounded,
  };

  @override
  void initState() {
    super.initState();
    _switchCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _switchCtrl, curve: Curves.easeOutCubic));
    _switchCtrl.forward();
    _scrollCtrl.addListener(_onScroll);
    _prepareBotPosts().whenComplete(_loadFeeds);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _switchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadFeeds();
    }
  }

  void _toggle() {
    setState(() {
      _showGames = !_showGames;
      _switchCtrl.reset();
      _switchCtrl.forward();
    });
  }

  Future<void> _prepareBotPosts() async {
    final db = DBManager();
    if (await db.getKV('bot_posts_enabled') != 'true') return;
    final day = DateTime.now();
    final dayKey = '${day.year}-${day.month}-${day.day}';
    final perDay =
        (int.tryParse(await db.getKV('bot_posts_per_day') ?? '') ?? 1)
            .clamp(1, 10);
    final bots = await db.queryBots();
    for (final bot in bots) {
      final botId = bot['id']?.toString() ?? '';
      if (botId.isEmpty || bot['chat_model']?.toString().isEmpty != false) {
        continue;
      }
      for (var index = 0; index < perDay; index++) {
        final marker = 'bot_post_date_${botId}_$index';
        if (await db.getKV(marker) == dayKey) continue;
        final res = await AIManager().sendMessage(
          botId: botId,
          text:
              '请以第一人称写一条适合公开空间的简短生活动态（20到60字）。这是今天第 ${index + 1} 条，请避免重复已有内容；自然、友好，不要使用心情标签或话题标签。',
          persistResponse: false,
        );
        if (res['success'] != true) continue;
        final content = res['reply']?.toString().trim() ?? '';
        if (content.isEmpty) continue;
        // 均匀分布在一天内，避免所有机器人同时刻发布，也便于广场按时间排序。
        final dayStart =
            DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
        final slot = (botId.hashCode.abs() + index * 7919) % (24 * 60);
        final scheduledAt = dayStart + slot * Duration.millisecondsPerMinute;
        final postId = 'botpost_${botId}_${dayKey}_$index';
        // 动态本体不含伪造的互动数据——点赞与评论必须来自真实发生的机器人互动。
        await db.insertPost({
          'id': postId,
          'author_id': bot['name'] ?? '机器人',
          'content': content,
          'image_path': '',
          'likes': 0,
          'comments': 0,
          'user_liked': 0,
          'user_collected': 0,
          'timestamp': scheduledAt,
        });
        // 真实互动：让其他机器人真实地查看这条由 ${bot['name']} 发布的动态，
        // 每个互动机器人都调用它自己的模型产出一条第一人称评论（非模板/非随机），
        // 并把"点赞"与"评论"作为持久化事件写入 feed_events / post_comments。
        final otherBots = bots
            .where((cb) =>
                (cb['id']?.toString() ?? '') != botId &&
                (cb['chat_model']?.toString().isNotEmpty ?? false))
            .toList();
        for (var i = 0; i < otherBots.length && i < 2; i++) {
          final reactor = otherBots[i];
          final reactorId = reactor['id']?.toString() ?? '';
          if (reactorId.isEmpty) continue;
          // 每个互动事件幂等：同一天同一机器人对同一条动态只真实互动一次。
          final reactKey = 'bot_react_${reactorId}_$postId';
          if (await db.getKV(reactKey) == '1') continue;
          // 先记录点赞事件（真实发生的互动，非模拟数）。
          await db.recordFeedEvent(
            postId: postId,
            actorId: reactorId,
            eventType: 'like',
          );
          // 让该机器人真实阅读动态并生产一条第一人称评论。
          try {
            final reactRes = await AIManager().sendMessage(
              botId: reactorId,
              text:
                  '你在空间广场看到${bot['name'] ?? '另一个机器人'}发布了一条动态："$content"。请用你自己的第一人称口吻写一句简短评论（15字以内）回应这条动态，语气自然，不要出现心情标签、话题标签或"评论"二字。',
              persistResponse: false,
              includeChatHistory: false,
              enableAutoSummary: false,
            );
            final commentText = (reactRes['reply']?.toString() ?? '').trim();
            if (commentText.isNotEmpty) {
              await db.insertRealPostComment(
                postId: postId,
                authorId: reactor['name']?.toString() ?? '机器人',
                content: commentText,
                timestamp: scheduledAt + 60000 + i * 900000,
              );
            }
          } catch (_) {
            // 任一机器人模型不可用不影响其他机器人，也不影响动态本身落库。
          }
          await db.setKV(reactKey, '1');
        }
        await db.setKV(marker, dayKey);
      }
    }
  }

  Future<void> _loadFeeds() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final db = DBManager();
    final rows =
        await db.queryPosts(offset: _feedPage * _pageSize, limit: _pageSize);
    if (rows.isEmpty || rows.length < _pageSize) _hasMore = false;
    // 点赞数与评论数不再读取 posts 上的伪造整数字段，改为从
    // feed_events / post_comments 真实聚合计数。
    final feeds = <Map<String, dynamic>>[];
    for (final r in rows) {
      final postId = r['id']?.toString() ?? '';
      final likes = postId.isEmpty ? 0 : await db.countPostLikes(postId);
      final comments = postId.isEmpty ? 0 : await db.countPostComments(postId);
      feeds.add({
        'user': r['author_id'] ?? '匿名',
        'content': r['content'] ?? '',
        'image': r['image_path'] ?? '',
        'likes': likes,
        'comments': comments,
        'favorited': (r['user_liked'] as int? ?? 0) == 1,
        'collected': (r['user_collected'] as int? ?? 0) == 1,
        'time': r['timestamp'] != null ? formatTime(r['timestamp']) : '',
        'id': r['id'],
      });
    }
    if (mounted) {
      setState(() {
        _feeds.addAll(feeds);
        _feedPage++;
        _loadingMore = false;
      });
    }
  }

  Future<void> _shareFeed(Map<String, dynamic> f) async {
    final db = DBManager();
    final bots = await db.queryBots();
    if (!mounted || bots.isEmpty) return;
    final botId = await showTideSheet<String>(
      context: context,
      height: 420,
      child: ListView(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text('分享给机器人',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'TideFont')),
        ),
        ...bots.map((bot) => ListTile(
              leading: TideBotAvatar(
                  name: bot['name']?.toString() ?? 'TA',
                  path: bot['avatar']?.toString(),
                  size: 42),
              title: Text(bot['name']?.toString() ?? '未命名机器人',
                  style: const TextStyle(fontFamily: 'TideFont')),
              onTap: () => Navigator.pop(context, bot['id']?.toString()),
            )),
      ]),
    );
    if (botId == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode({
      'author': f['user']?.toString() ?? '匿名',
      'content': f['content']?.toString() ?? '',
      'image_path': f['image']?.toString() ?? '',
      'timestamp': f['timestamp'] ?? now,
    });
    await db.insertMessage({
      'id': 'share_$now',
      'bot_id': botId,
      'role': 'user',
      'type': 'shared_post',
      'content': payload,
      'file_path': f['image']?.toString(),
      'timestamp': now,
    });
    // A share is a real chat turn, not merely an archived card. Ask the bot
    // immediately while keeping the JSON payload out of its natural-language UI.
    final readable =
        '用户分享了一条动态。作者：${f['user'] ?? '匿名'}；发布时间：${formatTime(f['timestamp'] ?? now)}；内容：${f['content'] ?? ''}；${(f['image']?.toString().isNotEmpty == true) ? '动态附有一张图片。' : ''} 请针对这条动态自然回应。';
    final reply = await AIManager().sendMessage(botId: botId, text: readable);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          reply['success'] == true ? '动态已发送，机器人已回复' : '动态已发送；机器人回复失败，可在聊天页重试',
          style: const TextStyle(fontFamily: 'TideFont')),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void publishFeed() {
    Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (c, a, s) =>
              _PublishFeedPage(onPublished: (text, imagePath) async {
            final db = DBManager();
            final now = DateTime.now().millisecondsSinceEpoch;
            final postId = 'post_$now';
            await db.insertPost({
              'id': postId,
              'author_id': '我',
              'content': text,
              'image_path': imagePath ?? '',
              'likes': 0,
              'comments': 0,
              'user_liked': 0,
              'user_collected': 0,
              'timestamp': now,
            });
            setState(() => _feeds.insert(0, {
                  'user': '我',
                  'content': text,
                  'image': imagePath ?? '',
                  'likes': 0,
                  'comments': 0,
                  'favorited': false,
                  'collected': false,
                  'time': '刚刚',
                  'id': postId
                }));
          }),
          transitionsBuilder: (c, a, s, child) => SlideTransition(
              position: Tween<Offset>(
                      begin: const Offset(0, 0.3), end: Offset.zero)
                  .animate(
                      CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: FadeTransition(opacity: a, child: child)),
        ));
  }

  void _openFeedDetail(Map<String, dynamic> f) {
    Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (c, a, s) => _FeedDetailPage(
              feed: f,
              onUpdate: () {
                if (mounted) setState(() {});
              }),
          transitionsBuilder: (c, a, s, child) => SlideTransition(
              position: Tween<Offset>(
                      begin: const Offset(0, 0.15), end: Offset.zero)
                  .animate(
                      CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: FadeTransition(opacity: a, child: child)),
        ));
  }

  void _deleteFeed(Map<String, dynamic> f, GlobalKey cardKey) async {
    final confirm = await TideDialogs.show<bool>(
      context: context,
      builder: (ctx) => TideDialogSurface(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: TideDialogs.glassContent(context: ctx, children: [
          const Center(
              child: Text('删除动态',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'TideFont'))),
          const SizedBox(height: 10),
          const Center(
              child: Text('确定删除这条动态吗？\n此操作不可恢复。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF636366),
                      fontFamily: 'TideFont'))),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
                child: TideDialogs.glassButton('取消',
                    onTap: () => Navigator.pop(ctx, false),
                    color: const Color(0xFFE8E8F0),
                    textColor: const Color(0xFF1C1C1E))),
            const SizedBox(width: 12),
            Expanded(
                child: TideDialogs.glassButton('删除',
                    onTap: () => Navigator.pop(ctx, true),
                    color: const Color(0xFFE74C3C))),
          ]),
        ]),
      ),
    );
    if (confirm == true) {
      final box = cardKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final position = box.localToGlobal(Offset.zero);
        _particleOrigins.clear();
        for (var i = 0; i < 12; i++) {
          _particleOrigins.add(Offset(
            position.dx + box.size.width * (0.1 + 0.8 * i / 11),
            position.dy + box.size.height * (0.2 + 0.6 * ((i * 7) % 11) / 10),
          ));
        }
        setState(() {
          _particleRun++;
          _showParticles = true;
        });
      }
      await DBManager().deletePost(f['id'] as String? ?? '');
      if (mounted) {
        setState(() => _feeds.removeWhere((x) => x['id'] == f['id']));
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _showParticles = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final content = Stack(children: [
      Container(
        color: theme.bgColor,
        child: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(children: [
                const Spacer(),
                BouncyTap(
                    onTap: _toggle,
                    child: AnimatedRotation(
                      turns: _showGames ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: theme.primary.withValues(alpha: 0.12),
                        ),
                        child: Icon(
                            _showGames
                                ? Icons.videogame_asset_rounded
                                : Icons.article_rounded,
                            size: 22,
                            color: theme.primary),
                      ),
                    )),
                const SizedBox(width: 8),
              ])),
          Expanded(
              child: SlideTransition(
                  position: _slideAnim,
                  child: _showGames ? _buildGames(theme) : _buildFeeds(theme))),
        ])),
      ),
    ]);
    return _showParticles
        ? ParticleOverlay(
            key: ValueKey(_particleRun),
            origins: _particleOrigins,
            onDone: () {
              if (mounted) setState(() => _showParticles = false);
            },
            child: content,
          )
        : content;
  }

  Widget _buildFeeds(TideTheme theme) => _feeds.isEmpty
      ? ListView(
          key: const ValueKey('feeds_empty'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: const [
              FrostCard(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('还没有动态\n点击右下角 + 发布第一条',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF8E8E93),
                              fontFamily: 'TideFont',
                              height: 1.6))))
            ])
      : ListView.builder(
          key: const ValueKey('feeds'),
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          physics: const BouncingScrollPhysics(),
          itemCount: _feeds.length,
          itemBuilder: (ctx, i) {
            final f = _feeds[i];
            final cardKey = GlobalKey();
            return FrostCard(
                key: cardKey,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                onTap: () => _openFeedDetail(f),
                onLongPress: () => _deleteFeed(f, cardKey),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _openFeedDetail(f),
                        child: Row(children: [
                          CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  theme.primary.withValues(alpha: 0.15),
                              child: Icon(Icons.person_rounded,
                                  size: 20, color: theme.primary)),
                          const SizedBox(width: 10),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f['user'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'TideFont')),
                                Text(f['time'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFFC7C7CC),
                                        fontFamily: 'TideFont'))
                              ]),
                          const Spacer(),
                          BouncyTap(
                              onTap: () => _shareFeed(f),
                              child: const Icon(Icons.share_rounded,
                                  size: 18, color: Color(0xFFC7C7CC))),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _openFeedDetail(f),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (f['image'] != null &&
                                  (f['image'] as String).isNotEmpty)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.file(
                                            File(f['image'] as String),
                                            width: double.infinity,
                                            fit: BoxFit.cover))),
                              Text(f['content'] ?? '',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontFamily: 'TideFont',
                                      color: theme.isDark
                                          ? Colors.white
                                          : const Color(0xFF3C3C43),
                                      height: 1.5)),
                            ]),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        BouncyTap(
                            onTap: () async {
                              final wasLiked = f['favorited'] as bool;
                              setState(() {
                                f['favorited'] = !wasLiked;
                                f['likes'] = (f['likes'] as int) +
                                    (f['favorited'] == true ? 1 : -1);
                              });
                              // 用户的点赞是真实互动事件，落库 feed_events。
                              final nowLiked = await DBManager()
                                  .toggleFeedEvent(
                                      postId: f['id'] as String? ?? '',
                                      actorId: 'me',
                                      eventType: 'like');
                              if (nowLiked != (f['favorited'] as bool) &&
                                  mounted) {
                                setState(() {
                                  f['favorited'] = nowLiked;
                                  f['likes'] =
                                      (f['likes'] as int) + (nowLiked ? 1 : -1);
                                });
                              }
                            },
                            child: Row(children: [
                              Icon(
                                  f['favorited'] == true
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 18,
                                  color: f['favorited'] == true
                                      ? const Color(0xFFE74C3C)
                                      : const Color(0xFFC7C7CC)),
                              const SizedBox(width: 4),
                              Text('${f['likes']}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFC7C7CC),
                                      fontFamily: 'TideFont')),
                            ])),
                        const SizedBox(width: 20),
                        BouncyTap(
                            onTap: () => _commentFeed(f, theme),
                            child: Row(children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  size: 18, color: theme.primary),
                              const SizedBox(width: 4),
                              Text('${f['comments']}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: theme.primary,
                                      fontFamily: 'TideFont')),
                            ])),
                        const Spacer(),
                        BouncyTap(
                            onTap: () async {
                              setState(() =>
                                  f['collected'] = !(f['collected'] as bool));
                              // 收藏是真实互动事件（feed_events collect，幂等切换）。
                              await DBManager().toggleFeedEvent(
                                  postId: f['id'] as String? ?? '',
                                  actorId: 'me',
                                  eventType: 'collect');
                            },
                            child: Icon(
                                f['collected'] == true
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                                size: 18,
                                color: f['collected'] == true
                                    ? theme.primary
                                    : const Color(0xFFC7C7CC))),
                      ]),
                    ]));
          });

  void _commentFeed(Map<String, dynamic> f, TideTheme theme) {
    _openFeedDetail(f);
  }

  Future<void> _startGame(String game) async {
    final bots = await DBManager().queryBots();
    if (!mounted) return;
    if (bots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请先创建机器人', style: TextStyle(fontFamily: 'TideFont'))));
      return;
    }
    final theme = TideTheme.of(context);
    await showTideSheet(
      context: context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择对战机器人',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: theme.textStrong,
                      fontFamily: 'TideFont')),
              const SizedBox(height: 6),
              Text('本局 $game 会和选中的 TA 进行，游戏内也能直接聊天。',
                  style:
                      TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
              const SizedBox(height: 10),
              ...bots.map((bot) => ListTile(
                    leading: TideBotAvatar(
                        name: bot['name']?.toString() ?? '未命名机器人',
                        path: bot['avatar']?.toString(),
                        size: 44),
                    title: Text(bot['name']?.toString() ?? '未命名机器人',
                        style: TextStyle(
                            color: theme.textStrong, fontFamily: 'TideFont')),
                    subtitle: Text(
                        bot['chat_model']?.toString().isNotEmpty == true
                            ? '已配置模型'
                            : '未配置模型，仍可进行本地回合',
                        style: TextStyle(
                            color: theme.textWeak,
                            fontSize: 12,
                            fontFamily: 'TideFont')),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  GameArenaPage(game: game, bot: bot)));
                    },
                  )),
            ]),
      ),
    );
  }

  Widget _buildGames(TideTheme theme) => GridView.builder(
      key: const ValueKey('games'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          // 仅四款游戏，使用更高的入口卡片以提升可点性与可读性。
          childAspectRatio: 0.78),
      itemCount: _games.length,
      itemBuilder: (ctx, i) {
        final g = _games[i];
        final icon = _gameIcons[g['icon']] ?? Icons.extension_rounded;
        return BouncyTap(
            onTap: () => _startGame(g['name']?.toString() ?? ''),
            child: FrostCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 52, color: theme.primary),
                      const SizedBox(height: 14),
                      Text(g['name'] ?? '',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'TideFont',
                              color: theme.textStrong)),
                      const SizedBox(height: 4),
                      Text(g['desc'] ?? '',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFC7C7CC),
                              fontFamily: 'TideFont'))
                    ])));
      });
}

// ==================== 全屏发布页 ====================
class _PublishFeedPage extends StatefulWidget {
  final Function(String, String?) onPublished;
  const _PublishFeedPage({required this.onPublished});
  @override
  State<_PublishFeedPage> createState() => _PublishFeedPageState();
}

class _PublishFeedPageState extends State<_PublishFeedPage> {
  final ctrl = TextEditingController();
  String? _imagePath;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _pickImage() async {
    final p = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1024);
    if (p != null) setState(() => _imagePath = p.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
        title: Text('发布动态',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontFamily: 'TideFont',
                color: theme.textStrong)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
            onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(
              onPressed: () {
                final text = ctrl.text.trim();
                if (text.isNotEmpty) {
                  widget.onPublished(text, _imagePath);
                  Navigator.pop(context);
                }
              },
              child: Text('发布',
                  style: TextStyle(
                      color: theme.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'TideFont'))),
        ],
      ),
      body: Column(children: [
        Expanded(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                      fontSize: 16, fontFamily: 'TideFont', height: 1.8),
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '分享你的想法...',
                    hintStyle: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFC7C7CC),
                        fontFamily: 'TideFont'),
                    border: InputBorder.none,
                  ),
                ))),
        if (_imagePath != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(children: [
                    Image.file(File(_imagePath!),
                        height: 120, width: double.infinity, fit: BoxFit.cover),
                    Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                            onTap: () => setState(() => _imagePath = null),
                            child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black54),
                                child: const Icon(Icons.close,
                                    size: 16, color: Colors.white)))),
                  ]))),
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: BouncyTap(
                onTap: _pickImage,
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: theme.primary.withValues(alpha: 0.1)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.image_rounded, size: 20, color: theme.primary),
                      const SizedBox(width: 8),
                      Text('添加图片',
                          style: TextStyle(
                              color: theme.primary,
                              fontFamily: 'TideFont',
                              fontSize: 14))
                    ])))),
      ]),
    );
  }
}

// ==================== 动态详情页 ====================
class _FeedDetailPage extends StatefulWidget {
  final Map<String, dynamic> feed;
  final VoidCallback onUpdate;
  const _FeedDetailPage({required this.feed, required this.onUpdate});

  @override
  State<_FeedDetailPage> createState() => _FeedDetailPageState();
}

class _FeedDetailPageState extends State<_FeedDetailPage> {
  final _commentCtrl = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final rows =
        await DBManager().queryPostComments(widget.feed['id'] as String? ?? '');
    if (mounted) {
      setState(() {
        _comments = rows;
        _loading = false;
      });
    }
  }

  Future<void> _toggleLike() async {
    final db = DBManager();
    final wasLiked = widget.feed['favorited'] as bool;
    // 先乐观更新 UI，再写入真实互动事件。
    setState(() {
      widget.feed['favorited'] = !wasLiked;
      widget.feed['likes'] = (widget.feed['likes'] as int) +
          (widget.feed['favorited'] == true ? 1 : -1);
    });
    // 用户的点赞是真实发生的互动事件：写 feed_events（actor 固定为 'me'）。
    final nowLiked = await db.toggleFeedEvent(
      postId: widget.feed['id'] as String? ?? '',
      actorId: 'me',
      eventType: 'like',
    );
    // 若写入失败（如空 postId），回滚 UI。
    if (nowLiked != (widget.feed['favorited'] as bool) && mounted) {
      setState(() {
        widget.feed['favorited'] = nowLiked;
        widget.feed['likes'] =
            (widget.feed['likes'] as int) + (nowLiked ? 1 : -1);
      });
    }
    widget.onUpdate();
  }

  Future<void> _toggleCollect() async {
    final db = DBManager();
    setState(() {
      widget.feed['collected'] = !(widget.feed['collected'] as bool);
    });
    // 收藏同样是真实互动事件（存在 feed_events 的 collect 事件）。
    await db.toggleFeedEvent(
      postId: widget.feed['id'] as String? ?? '',
      actorId: 'me',
      eventType: 'collect',
    );
    widget.onUpdate();
  }

  Future<void> _sendComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final comment = <String, dynamic>{
      'id': 'pc_$now',
      'post_id': widget.feed['id'],
      'author_id': '我',
      'content': content,
      'timestamp': now,
    };
    await DBManager().insertPostComment(comment);
    // 评论数不再写 posts.fake 整数，真实值由 post_comments 表聚合得出。
    // 详情页这里直接基于已插入的评论累加展示即可。
    final count = (widget.feed['comments'] as int) + 1;
    if (!mounted) return;
    setState(() {
      widget.feed['comments'] = count;
      _comments.add(comment);
      _commentCtrl.clear();
    });
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final feed = widget.feed;
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
        title: Text(
          '动态详情',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: 'TideFont',
            color: theme.textStrong,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.iconMuted),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: theme.primary.withValues(alpha: 0.15),
                      child: Icon(
                        Icons.person_rounded,
                        size: 24,
                        color: theme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feed['user'] ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'TideFont',
                            color: theme.textStrong,
                          ),
                        ),
                        Text(
                          feed['time'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textFaint,
                            fontFamily: 'TideFont',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if ((feed['image'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(feed['image'] as String),
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Text(
                  feed['content'] ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'TideFont',
                    color: theme.textStrong,
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    BouncyTap(
                      onTap: _toggleLike,
                      child: Row(
                        children: [
                          Icon(
                            feed['favorited'] == true
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 22,
                            color: feed['favorited'] == true
                                ? const Color(0xFFE74C3C)
                                : theme.iconMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${feed['likes']} 点赞',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.textWeak,
                              fontFamily: 'TideFont',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 22,
                      color: theme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${feed['comments']} 评论',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.primary,
                        fontFamily: 'TideFont',
                      ),
                    ),
                    const Spacer(),
                    BouncyTap(
                      onTap: _toggleCollect,
                      child: Icon(
                        feed['collected'] == true
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 22,
                        color: feed['collected'] == true
                            ? theme.primary
                            : theme.iconMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  '全部评论',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'TideFont',
                    color: theme.textStrong,
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircularProgressIndicator(color: theme.primary),
                    ),
                  )
                else if (_comments.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '还没有评论，来说点什么吧',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textFaint,
                          fontFamily: 'TideFont',
                        ),
                      ),
                    ),
                  )
                else
                  ..._comments.map(
                    (comment) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor:
                                theme.primary.withValues(alpha: 0.12),
                            child: Icon(
                              Icons.person_rounded,
                              size: 16,
                              color: theme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  comment['author_id'] ?? '匿名',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textStrong,
                                    fontFamily: 'TideFont',
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  comment['content'] ?? '',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: theme.textWeak,
                                    fontFamily: 'TideFont',
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: theme.surface,
                border: Border(top: BorderSide(color: theme.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendComment(),
                      style: TextStyle(
                        color: theme.textStrong,
                        fontFamily: 'TideFont',
                      ),
                      decoration: InputDecoration(
                        hintText: '写评论...',
                        hintStyle: TextStyle(
                          color: theme.textFaint,
                          fontFamily: 'TideFont',
                        ),
                        filled: true,
                        fillColor: theme.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sendComment,
                    icon: Icon(Icons.send_rounded, color: theme.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
