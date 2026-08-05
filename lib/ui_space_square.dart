import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'ui_components.dart';
import 'db.dart';
import 'theme.dart';

// ==================== 空间页 ====================
class SpacePage extends StatefulWidget {
  final PageController? pageController;
  const SpacePage({super.key, this.pageController});
  @override State<SpacePage> createState() => _SpacePageState();
}
class _SpacePageState extends State<SpacePage> {
  String _botId = ''; String _botName = ''; String _dailyQuote = ''; int _daysSince = 0;
  String _moodIcon = 'smile'; String _moodLabel = '';
  List<Map<String, dynamic>> _schedules = []; List<Map<String, dynamic>> _memories = []; bool _loading = true;
  final List<String> _moods = ['smile', 'heart', 'sad', 'angry', 'sleep', 'think'];
  final List<String> _moodLabels = ['开心','幸福','难过','生气','困倦','思考'];
  final Map<String, IconData> _moodIcons = {
    'smile': Icons.sentiment_satisfied_rounded, 'heart': Icons.favorite_rounded,
    'sad': Icons.sentiment_dissatisfied_rounded, 'angry': Icons.sentiment_very_dissatisfied_rounded,
    'sleep': Icons.bedtime_rounded, 'think': Icons.psychology_rounded,
  };

  @override void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final db = DBManager(); final bots = await db.queryBots();
    if (bots.isNotEmpty) {
      // 如果已有选中的 bot 且在列表中，保持选中；否则选第一个
      Map<String, dynamic>? b;
      if (_botId.isNotEmpty) {
        try { b = bots.firstWhere((x) => x['id'] == _botId); } catch (_) { b = null; }
      }
      b ??= bots.first;
      _botId = b['id'] as String? ?? ''; _botName = b['name'] as String? ?? '';
      _dailyQuote = b['daily_quote'] as String? ?? '';
      final created = b['created_at'];
      if (created is int) _daysSince = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(created)).inDays;
      else if (created is String && created.isNotEmpty) _daysSince = DateTime.now().difference(DateTime.tryParse(created) ?? DateTime.now()).inDays;
      final sch = await db.querySchedules(_botId, limit: 3);
      final mem = await db.queryMemories(_botId, type: 'medium', limit: 3);
      _schedules = sch; _memories = mem;
      if (mounted) setState(() { _loading = false; });
    } else {
      _daysSince = 0; _dailyQuote = '';
      _schedules = []; _memories = []; _botId = ''; _botName = '';
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showScheduleDetail(Map<String, dynamic> s) {
    showTideSheet(context: context, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(s['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
      const SizedBox(height: 8), Text(s['note'] ?? '', style: const TextStyle(fontSize: 15, color: Color(0xFF636366), fontFamily: 'TideFont')),
      const SizedBox(height: 12), Text(formatTime(s['time']), style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont'))])));
  }

  void _showMemoryDetail(Map<String, dynamic> m) {
    showTideSheet(context: context, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(m['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
      const SizedBox(height: 8), Text(m['content'] ?? '', style: const TextStyle(fontSize: 15, color: Color(0xFF3C3C43), fontFamily: 'TideFont', height: 1.5)),
      const SizedBox(height: 12), Text(formatTime(m['created_at']), style: const TextStyle(fontSize: 13, color: Color(0xFFC7C7CC), fontFamily: 'TideFont'))])));
  }

  @override Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr = '${now.year}.${now.month}.${now.day}';
    return Container(color: const Color(0xFFF2F2F7),
      child: SafeArea(child: _loading ? Center(child: CircularProgressIndicator(color: theme.primary)) :
        SingleChildScrollView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeader(timeStr, dateStr, theme), const SizedBox(height: 20),
            if (_botId.isNotEmpty) ...[
              BouncyTap(onTap: () { setState(() { final q = ['世界很大，好在有你。','今天也是充满希望的一天。','活在当下，珍惜眼前。','心之所向，素履以往。']; _dailyQuote = q[DateTime.now().millisecond % q.length]; }); }, child: _buildQuoteCard(theme)),
              const SizedBox(height: 16),
              Row(children: [Expanded(child: _buildDaysCard(theme)), const SizedBox(width: 12), Expanded(child: _buildMoodCard(theme))]),
            ] else
              FrostCard(padding: const EdgeInsets.all(24), child: const Center(child: Text('还没有创建机器人\n点击底部聊天 Tab 开始', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93), fontFamily: 'TideFont', height: 1.6)))),
            const SizedBox(height: 16),
            if (_schedules.isNotEmpty) ...[
              _buildSectionTitle('最近日程'), const SizedBox(height: 8),
              ..._schedules.map((s) => BouncyTap(onTap: () => _showScheduleDetail(s), child: _buildScheduleCard(s, theme))),
            ],
            if (_memories.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionTitle('TA 的日记'), const SizedBox(height: 8),
              ..._memories.map((m) => BouncyTap(onTap: () => _showMemoryDetail(m), child: _buildMemoryCard(m))),
            ],
          ])),
      ));
  }

  Widget _buildHeader(String time, String date, TideTheme theme) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(time, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
      Text(date, style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93), fontFamily: 'TideFont')),
    ]),
    if (_botId.isNotEmpty) BouncyTap(onTap: () async {
      final db = DBManager(); final bots = await db.queryBots(); if (!mounted) return;
      showTideSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12), const Text('切换机器人', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'TideFont')), const SizedBox(height: 12),
        ...bots.map((b) => ListTile(title: Text(b['name'] ?? '', style: const TextStyle(fontFamily: 'TideFont')), subtitle: Text(b['desc'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))), onTap: () { setState(() { _botId = b['id'] as String? ?? ''; _botName = b['name'] as String? ?? ''; }); Navigator.pop(context); _loadData(); })),]));
    }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white.withOpacity(0.8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Text(_botName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'TideFont', color: theme.primary)), const SizedBox(width: 4), Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: theme.primary)]))),
  ]);

  Widget _buildQuoteCard(TideTheme theme) => FrostCard(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Icon(Icons.format_quote_rounded, color: theme.primary, size: 20), const SizedBox(width: 8), Text('今日一言', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: theme.primary))]),
    const SizedBox(height: 10), Text(_dailyQuote.isNotEmpty ? _dailyQuote : '点击刷新今日一言', style: TextStyle(fontSize: 16, fontFamily: 'TideFont', color: _dailyQuote.isNotEmpty ? const Color(0xFF3C3C43) : const Color(0xFFC7C7CC), height: 1.5))]));
  Widget _buildDaysCard(TideTheme theme) => FrostCard(padding: const EdgeInsets.all(16), child: Column(children: [
    Text('$_daysSince', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300, fontFamily: 'TideFont', color: theme.primary)), const SizedBox(height: 4),
    const Text('相遇天数', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont'))]));
  Widget _buildMoodCard(TideTheme theme) {
    final icon = _moodIcons[_moodIcon] ?? Icons.sentiment_satisfied_rounded;
    return FrostCard(padding: const EdgeInsets.all(16), child: Column(children: [
      Icon(icon, size: 36, color: theme.primary), const SizedBox(height: 4),
      Text(_moodLabel, style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont')), const SizedBox(height: 8),
      Wrap(spacing: 6, children: List.generate(_moods.length, (i) {
        final mIcon = _moodIcons[_moods[i]] ?? Icons.help_outline; final isActive = _moodIcon == _moods[i];
        return BouncyTap(onTap: () => setState(() { _moodIcon = _moods[i]; _moodLabel = _moodLabels[i]; }), child: Icon(mIcon, size: isActive ? 26 : 18, color: isActive ? theme.primary : const Color(0xFFC7C7CC)));
      })),
    ]));
  }
  Widget _buildSectionTitle(String title) => Padding(padding: const EdgeInsets.only(left: 4), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))));
  Widget _buildScheduleCard(Map<String, dynamic> s, TideTheme theme) => FrostCard(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14), child: Row(children: [
    Container(width: 4, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: theme.primary)), const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s['title'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'TideFont')),
      if ((s['note'] ?? '').toString().isNotEmpty) Text(s['note'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)), maxLines: 2, overflow: TextOverflow.ellipsis),])),
    Text(formatTime(s['time']), style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont'))]));
  Widget _buildMemoryCard(Map<String, dynamic> m) => FrostCard(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(m['title'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'TideFont')), const SizedBox(height: 4),
    Text(m['content'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF3C3C43)), maxLines: 3, overflow: TextOverflow.ellipsis), const SizedBox(height: 6),
    Text(formatTime(m['created_at']), style: const TextStyle(fontSize: 11, color: Color(0xFFC7C7CC), fontFamily: 'TideFont'))]));
}

// ==================== 广场页 ====================
class SquarePage extends StatefulWidget {
  final GlobalKey<SquarePageState>? pageKey;
  const SquarePage({super.key, this.pageKey}); @override State<SquarePage> createState() => SquarePageState();
}
class SquarePageState extends State<SquarePage> with SingleTickerProviderStateMixin {
  bool _showGames = false;
  late AnimationController _switchCtrl;
  late Animation<Offset> _slideAnim;
  final ScrollController _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _feeds = [];
  int _feedPage = 0; static const _pageSize = 10; bool _loadingMore = false; bool _hasMore = true;
  final _games = [
    {'name':'五子棋','desc':'经典对弈','icon':'grid'},{'name':'井字棋','desc':'休闲小游戏','icon':'circle'},
    {'name':'20问猜物','desc':'AI猜你心思','icon':'help'},{'name':'好运骰子','desc':'看看今天运气','icon':'casino'},
    {'name':'文字冒险','desc':'沉浸故事世界','icon':'book'},{'name':'真心话大冒险','desc':'拉近彼此距离','icon':'favorite'},
  ];
  final Map<String, IconData> _gameIcons = {
    'grid':Icons.grid_4x4_rounded,'circle':Icons.circle_outlined,'help':Icons.help_outline_rounded,
    'casino':Icons.casino_rounded,'book':Icons.menu_book_rounded,'favorite':Icons.favorite_rounded,
  };

  @override void initState() {
    super.initState();
    _switchCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _switchCtrl, curve: Curves.easeOutCubic));
    _switchCtrl.forward();
    _scrollCtrl.addListener(_onScroll);
    _loadFeeds();
  }
  @override void dispose() { _scrollCtrl.dispose(); _switchCtrl.dispose(); super.dispose(); }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 && !_loadingMore && _hasMore) {
      _loadFeeds();
    }
  }

  void _toggle() {
    setState(() {
      _showGames = !_showGames;
      _switchCtrl.reset(); _switchCtrl.forward();
    });
  }

  Future<void> _loadFeeds() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final db = DBManager();
    final rows = await db.queryPosts(offset: _feedPage * _pageSize, limit: _pageSize);
    if (rows.isEmpty || rows.length < _pageSize) _hasMore = false;
    if (mounted) {
      setState(() {
        _feeds.addAll(rows.map((r) => {
          'user': r['author_id'] ?? '匿名',
          'content': r['content'] ?? '',
          'image': r['image_path'] ?? '',
          'likes': r['likes'] as int? ?? 0,
          'comments': r['comments'] as int? ?? 0,
          'favorited': false,
          'collected': false,
          'time': r['timestamp'] != null ? formatTime(r['timestamp']) : '',
          'id': r['id'],
        }).toList());
        _feedPage++;
        _loadingMore = false;
      });
    }
  }

  Future<void> _shareFeed(Map<String, dynamic> f) async {
    final theme = TideTheme.of(context);
    TextEditingController ctrl = TextEditingController(text: '分享一条动态: ${f['content']}');
    TideDialogs.show(context: context, builder: (ctx) => AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero,
      content: TideDialogs.glassContent(context: ctx, maxWidth: 0.9, children: [
        const Text('分享给机器人', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
        const SizedBox(height: 12),
        TextField(controller: ctrl, maxLines: 3, style: const TextStyle(fontFamily: 'TideFont'), decoration: const InputDecoration(hintText: '编辑分享内容', border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))))),
        const SizedBox(height: 16),
        TideDialogs.glassButton('发送', onTap: () async {
          Navigator.pop(ctx);
          final db = DBManager();
          final bots = await db.queryBots();
          if (bots.isNotEmpty) {
            final bid = bots.first['id'] as String;
            final now = DateTime.now().millisecondsSinceEpoch;
            await db.insertMessage(<String, dynamic>{'id': 'm_$now', 'bot_id': bid, 'role': 'user', 'content': ctrl.text, 'timestamp': now});
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('已发送到聊天', style: TextStyle(fontFamily: 'TideFont')), behavior: SnackBarBehavior.floating, backgroundColor: theme.primary));
          } else {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先创建机器人', style: TextStyle(fontFamily: 'TideFont')), behavior: SnackBarBehavior.floating));
          }
        }),
      ])));
  }

  void publishFeed() {
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (c, a, s) => _PublishFeedPage(onPublished: (text, imagePath) async {
        final db = DBManager();
        final now = DateTime.now().millisecondsSinceEpoch;
        final postId = 'post_$now';
        await db.insertPost({'id': postId, 'author_id': '我', 'content': text, 'image_path': imagePath ?? '', 'likes': 0, 'comments': 0, 'timestamp': now});
        setState(() => _feeds.insert(0, {'user':'我','content':text,'image':imagePath ?? '','likes':0,'comments':0,'favorited':false,'collected':false,'time':'刚刚','id':postId}));
      }),
      transitionsBuilder: (c, a, s, child) => SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: FadeTransition(opacity: a, child: child)),
    ));
  }

  void _openFeedDetail(Map<String, dynamic> f) {
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (c, a, s) => _FeedDetailPage(feed: f, onUpdate: () { if (mounted) setState(() {}); }),
      transitionsBuilder: (c, a, s, child) => SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: FadeTransition(opacity: a, child: child)),
    ));
  }

  void _deleteFeed(Map<String, dynamic> f) async {
    final confirm = await TideDialogs.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero,
        content: TideDialogs.glassContent(context: ctx, children: [
          const Center(child: Text('删除动态', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'TideFont'))),
          const SizedBox(height: 10),
          const Center(child: Text('确定删除这条动态吗？\n此操作不可恢复。', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Color(0xFF636366), fontFamily: 'TideFont'))),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: TideDialogs.glassButton('取消', onTap: () => Navigator.pop(ctx, false), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E))),
            const SizedBox(width: 12),
            Expanded(child: TideDialogs.glassButton('删除', onTap: () => Navigator.pop(ctx, true), color: const Color(0xFFE74C3C))),
          ]),
        ]),
      ),
    );
    if (confirm == true) {
      await DBManager().deletePost(f['id'] as String? ?? '');
      if (mounted) setState(() => _feeds.removeWhere((x) => x['id'] == f['id']));
    }
  }

  @override Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Stack(children: [
      Container(color: const Color(0xFFF2F2F7),
        child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 4), child: Row(children: [
            const Spacer(),
            BouncyTap(onTap: _toggle, child: AnimatedRotation(
              turns: _showGames ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: theme.primary.withOpacity(0.12),
                ),
                child: Icon(_showGames ? Icons.videogame_asset_rounded : Icons.article_rounded, size: 22, color: theme.primary),
              ),
            )),
            const SizedBox(width: 8),
          ])),
          Expanded(child: SlideTransition(position: _slideAnim, child: _showGames ? _buildGames(theme) : _buildFeeds(theme))),
        ])),
      ),
    ]);
  }

  Widget _buildFeeds(TideTheme theme) => _feeds.isEmpty
    ? ListView(key: const ValueKey('feeds_empty'), padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: [FrostCard(padding: const EdgeInsets.all(24), child: const Center(child: Text('还没有动态\n点击右下角 + 发布第一条', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93), fontFamily: 'TideFont', height: 1.6))))])
    : ListView.builder(key: const ValueKey('feeds'), controller: _scrollCtrl, padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), physics: const BouncingScrollPhysics(), itemCount: _feeds.length, itemBuilder: (ctx, i) {
    final f = _feeds[i];
    return FrostCard(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), onTap: () => _openFeedDetail(f), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => _openFeedDetail(f),
        onLongPress: () => _deleteFeed(f),
        child: Row(children: [
          CircleAvatar(radius: 18, backgroundColor: theme.primary.withOpacity(0.15), child: Icon(Icons.person_rounded, size: 20, color: theme.primary)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f['user'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont')), Text(f['time'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFFC7C7CC), fontFamily: 'TideFont'))]),
          const Spacer(),
          BouncyTap(onTap: () => _shareFeed(f), child: const Icon(Icons.share_rounded, size: 18, color: Color(0xFFC7C7CC))),
        ]),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () => _openFeedDetail(f),
        onLongPress: () => _deleteFeed(f),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (f['image'] != null && (f['image'] as String).isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(borderRadius: BorderRadius.circular(12),
                child: Image.file(File(f['image'] as String), width: double.infinity, fit: BoxFit.cover))),
          Text(f['content'] ?? '', style: const TextStyle(fontSize: 14, fontFamily: 'TideFont', color: Color(0xFF3C3C43), height: 1.5)),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        BouncyTap(onTap: () => setState(() {
          f['favorited'] = !(f['favorited'] as bool);
          f['likes'] = f['favorited'] ? (f['likes'] as int) + 1 : (f['likes'] as int) - 1;
          DBManager().updatePostLikes(f['id'] as String? ?? '', f['likes'] as int);
        }), child: Row(children: [
          Icon(f['favorited'] == true ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 18, color: f['favorited'] == true ? const Color(0xFFE74C3C) : const Color(0xFFC7C7CC)),
          const SizedBox(width: 4), Text('${f['likes']}', style: const TextStyle(fontSize: 13, color: Color(0xFFC7C7CC), fontFamily: 'TideFont')),
        ])),
        const SizedBox(width: 20),
        BouncyTap(onTap: () => _commentFeed(f, theme), child: Row(children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 18, color: theme.primary),
          const SizedBox(width: 4), Text('${f['comments']}', style: TextStyle(fontSize: 13, color: theme.primary, fontFamily: 'TideFont')),
        ])),
        const Spacer(),
        BouncyTap(onTap: () => setState(() => f['collected'] = !(f['collected'] as bool)), child: Icon(f['collected'] == true ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 18, color: f['collected'] == true ? theme.primary : const Color(0xFFC7C7CC))),
      ]),
    ]));
  });

  void _commentFeed(Map<String, dynamic> f, TideTheme theme) {
    showTideSheet(context: context, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('评论', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'TideFont')),
      const SizedBox(height: 12),
      const Expanded(child: Center(child: Text('暂无评论', style: TextStyle(fontSize: 14, color: Color(0xFFC7C7CC), fontFamily: 'TideFont')))),
      Row(children: [
        Expanded(child: TextField(style: const TextStyle(fontFamily: 'TideFont'), decoration: InputDecoration(hintText: '写评论...', hintStyle: const TextStyle(fontFamily: 'TideFont'), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))))),
        const SizedBox(width: 8),
        TideDialogs.glassButton('发送', onTap: () {
          Navigator.pop(context);
          setState(() => f['comments'] = (f['comments'] as int) + 1);
          DBManager().updatePostComments(f['id'] as String? ?? '', f['comments'] as int);
        }),
      ]),
    ])));
  }

  Widget _buildGames(TideTheme theme) => GridView.builder(key: const ValueKey('games'), padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), physics: const BouncingScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.0), itemCount: _games.length, itemBuilder: (ctx, i) {
    final g = _games[i]; final icon = _gameIcons[g['icon']] ?? Icons.extension_rounded;
    return BouncyTap(onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${g['name']} 正在开发中...', style: const TextStyle(fontFamily: 'TideFont')), behavior: SnackBarBehavior.floating, backgroundColor: theme.primary)), child: FrostCard(padding: const EdgeInsets.all(16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 40, color: theme.primary), const SizedBox(height: 8),
      Text(g['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
      const SizedBox(height: 4), Text(g['desc'] ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFFC7C7CC), fontFamily: 'TideFont'))])));
  });
}

// ==================== 全屏发布页 ====================
class _PublishFeedPage extends StatefulWidget {
  final Function(String, String?) onPublished;
  const _PublishFeedPage({required this.onPublished});
  @override State<_PublishFeedPage> createState() => _PublishFeedPageState();
}
class _PublishFeedPageState extends State<_PublishFeedPage> {
  final ctrl = TextEditingController();
  String? _imagePath;

  @override void dispose() { ctrl.dispose(); super.dispose(); }

  void _pickImage() async {
    final p = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024);
    if (p != null) setState(() => _imagePath = p.path);
  }

  @override Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('发布动态', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size: 20), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(onPressed: () {
            final text = ctrl.text.trim();
            if (text.isNotEmpty) { widget.onPublished(text, _imagePath); Navigator.pop(context); }
          }, child: Text('发布', style: TextStyle(color: theme.primary, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'TideFont'))),
        ],
      ),
      body: Column(children: [
        Expanded(child: Padding(padding: const EdgeInsets.all(20), child: TextField(
          controller: ctrl, autofocus: true, maxLines: null, expands: true,
          style: const TextStyle(fontSize: 16, fontFamily: 'TideFont', height: 1.8),
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            hintText: '分享你的想法...',
            hintStyle: TextStyle(fontSize: 16, color: Color(0xFFC7C7CC), fontFamily: 'TideFont'),
            border: InputBorder.none,
          ),
        ))),
        if (_imagePath != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: ClipRRect(borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              Image.file(File(_imagePath!), height: 120, width: double.infinity, fit: BoxFit.cover),
              Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => setState(() => _imagePath = null), child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54), child: const Icon(Icons.close, size: 16, color: Colors.white)))),
            ]))),
        Padding(padding: const EdgeInsets.only(bottom: 16),
          child: BouncyTap(onTap: _pickImage, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: theme.primary.withOpacity(0.1)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.image_rounded, size: 20, color: theme.primary), const SizedBox(width: 8), Text('添加图片', style: TextStyle(color: theme.primary, fontFamily: 'TideFont', fontSize: 14))])))),
      ]),
    );
  }
}

// ==================== 动态详情页 ====================
class _FeedDetailPage extends StatelessWidget {
  final Map<String, dynamic> feed;
  final VoidCallback onUpdate;
  const _FeedDetailPage({required this.feed, required this.onUpdate});

  @override Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('动态详情', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 22, backgroundColor: theme.primary.withOpacity(0.15), child: Icon(Icons.person_rounded, size: 24, color: theme.primary)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(feed['user'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'TideFont')),
            Text(feed['time'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFFC7C7CC), fontFamily: 'TideFont')),
          ]),
        ]),
        const SizedBox(height: 20),
        if (feed['image'] != null && (feed['image'] as String).isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 16),
            child: ClipRRect(borderRadius: BorderRadius.circular(12),
              child: Image.file(File(feed['image'] as String), width: double.infinity, fit: BoxFit.cover))),
        Text(feed['content'] ?? '', style: const TextStyle(fontSize: 16, fontFamily: 'TideFont', color: Color(0xFF1C1C1E), height: 1.8)),
        const SizedBox(height: 24),
        Row(children: [
          Icon(feed['favorited'] == true ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 22, color: feed['favorited'] == true ? const Color(0xFFE74C3C) : const Color(0xFFC7C7CC)),
          const SizedBox(width: 6), Text('${feed['likes']} 点赞', style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93), fontFamily: 'TideFont')),
          const SizedBox(width: 24),
          Icon(Icons.chat_bubble_outline_rounded, size: 22, color: theme.primary),
          const SizedBox(width: 6), Text('${feed['comments']} 评论', style: TextStyle(fontSize: 14, color: theme.primary, fontFamily: 'TideFont')),
          const Spacer(),
          Icon(feed['collected'] == true ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 22, color: feed['collected'] == true ? theme.primary : const Color(0xFFC7C7CC)),
        ]),
        const SizedBox(height: 30),
        const Text('全部评论', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
        const SizedBox(height: 12),
        const Center(child: Text('暂无更多评论', style: TextStyle(fontSize: 13, color: Color(0xFFC7C7CC), fontFamily: 'TideFont'))),
      ])),
    );
  }
}
