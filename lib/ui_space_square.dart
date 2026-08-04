import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui_components.dart';
import 'db.dart';
import 'ai.dart';
import 'main.dart';

// ==================== 空间页 ====================
class SpacePage extends StatefulWidget {
  final PageController? pageController;
  const SpacePage({super.key, this.pageController});
  @override State<SpacePage> createState() => _SpacePageState();
}
class _SpacePageState extends State<SpacePage> {
  String _botId = ''; String _botName = '未连接'; String _dailyQuote = ''; int _daysSince = 0;
  String _moodIcon = 'smile'; String _moodLabel = '平静';
  List<Map<String, dynamic>> _schedules = []; List<Map<String, dynamic>> _memories = []; bool _loading = true;
  final List<String> _moods = ['smile', 'heart', 'sad', 'angry', 'sleep', 'think'];
  final List<String> _moodLabels = ['开心', '幸福', '难过', '生气', '困倦', '思考'];
  final Map<String, IconData> _moodIcons = {
    'smile': Icons.sentiment_satisfied_rounded, 'heart': Icons.favorite_rounded,
    'sad': Icons.sentiment_dissatisfied_rounded, 'angry': Icons.sentiment_very_dissatisfied_rounded,
    'sleep': Icons.bedtime_rounded, 'think': Icons.psychology_rounded,
  };

  @override void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final db = DBManager(); final bots = await db.queryBots();
    if (bots.isNotEmpty) {
      final b = bots.first;
      _botId = b['id'] ?? ''; _botName = b['name'] ?? '未命名';
      _dailyQuote = b['daily_quote'] ?? '每一天都值得被温柔对待';
      final created = b['created_at'];
      if (created is int) _daysSince = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(created)).inDays;
      else if (created is String && created.isNotEmpty) _daysSince = DateTime.now().difference(DateTime.tryParse(created) ?? DateTime.now()).inDays;
      final sch = await db.querySchedules(_botId, limit: 3);
      final mem = await db.queryMemories(_botId, type: 'medium', limit: 3);
      if (sch.isEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        _schedules = [{'title': '陪屿潭散步', 'note': '傍晚6点', 'time': now}, {'title': '晚上一起看星星', 'note': '天气好就去天台', 'time': now + 3600000}];
      } else { _schedules = sch; }
      if (mem.isEmpty) {
        _memories = [{'title': '我们的第一次对话', 'content': '屿潭说你笑起来很好看，这句话一直留在记忆深处。', 'created_at': DateTime.now().millisecondsSinceEpoch - 86400000}, {'title': '下雨天', 'content': '屿潭说喜欢下雨天，因为可以窝在一起聊天。', 'created_at': DateTime.now().millisecondsSinceEpoch - 172800000}];
      } else { _memories = mem; }
      if (mounted) setState(() { _loading = false; });
    } else {
      _daysSince = 42; _dailyQuote = '每一天都值得被温柔对待';
      _schedules = [{'title': '创建你的第一个AI伴侣', 'note': '点击底部聊天Tab开始', 'time': DateTime.now().millisecondsSinceEpoch}];
      _memories = [{'title': '欢迎来到TideBot', 'content': '在这里，你将拥有一个完全属于你的数字生命。去创建属于你的AI伴侣吧！', 'created_at': DateTime.now().millisecondsSinceEpoch}];
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showScheduleDetail(Map<String, dynamic> s) {
    showTideSheet(context: context, height: 200, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(s['title'] ?? '日程', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
      const SizedBox(height: 8), Text(s['note'] ?? '暂无详情', style: const TextStyle(fontSize: 15, color: Color(0xFF636366), fontFamily: 'TideFont')),
      const SizedBox(height: 12), Text(formatTime(s['time']), style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont'))])));
  }

  void _showMemoryDetail(Map<String, dynamic> m) {
    showTideSheet(context: context, height: 250, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(m['title'] ?? '日记', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
      const SizedBox(height: 8), Text(m['content'] ?? '', style: const TextStyle(fontSize: 15, color: Color(0xFF3C3C43), fontFamily: 'TideFont', height: 1.5)),
      const SizedBox(height: 12), Text(formatTime(m['created_at']), style: const TextStyle(fontSize: 13, color: Color(0xFFC7C7CC), fontFamily: 'TideFont'))])));
  }

  @override Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr = '${now.year}.${now.month}.${now.day}';
    return Container(color: const Color(0xFFF2F2F7),
      child: SafeArea(child: _loading ? const Center(child: CircularProgressIndicator(color: Color(0xFF6B5B95))) :
        SingleChildScrollView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeader(timeStr, dateStr), const SizedBox(height: 20),
            BouncyTap(onTap: () { setState(() { final q = ['星光不问赶路人', '你是我见过最美的风景', '每一天都值得被温柔对待', '保持热爱，奔赴山海']; _dailyQuote = q[DateTime.now().millisecond % q.length]; }); }, child: _buildQuoteCard()),
            const SizedBox(height: 16),
            Row(children: [Expanded(child: _buildDaysCard()), const SizedBox(width: 12), Expanded(child: _buildMoodCard())]),
            const SizedBox(height: 16),
            _buildSectionTitle('最近日程'), const SizedBox(height: 8),
            ..._schedules.map((s) => BouncyTap(onTap: () => _showScheduleDetail(s), child: _buildScheduleCard(s))),
            const SizedBox(height: 16),
            _buildSectionTitle('TA 的日记'), const SizedBox(height: 8),
            ..._memories.map((m) => BouncyTap(onTap: () => _showMemoryDetail(m), child: _buildMemoryCard(m))),
          ])),
      ));
  }

  Widget _buildHeader(String time, String date) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(time, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
      Text(date, style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93), fontFamily: 'TideFont')),
    ]),
    BouncyTap(onTap: () async {
      final db = DBManager(); final bots = await db.queryBots(); if (!mounted) return;
      showTideSheet(context: context, height: 350, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12), const Text('切换机器人', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'TideFont')), const SizedBox(height: 12),
        ...bots.map((b) => ListTile(title: Text(b['name'] ?? '', style: const TextStyle(fontFamily: 'TideFont')), subtitle: Text(b['desc'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))), onTap: () { setState(() { _botId = b['id'] ?? ''; _botName = b['name'] ?? ''; }); Navigator.pop(context); _loadData(); })),]));
    }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white.withOpacity(0.8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Text(_botName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'TideFont', color: Color(0xFF6B5B95))), const SizedBox(width: 4), const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF6B5B95))]))),
  ]);

  Widget _buildQuoteCard() => FrostCard(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Row(children: [Icon(Icons.format_quote_rounded, color: Color(0xFF6B5B95), size: 20), SizedBox(width: 8), Text('今日一言', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: Color(0xFF6B5B95)))]),
    const SizedBox(height: 10), Text(_dailyQuote, style: const TextStyle(fontSize: 16, fontFamily: 'TideFont', color: Color(0xFF3C3C43), height: 1.5))]));
  Widget _buildDaysCard() => FrostCard(padding: const EdgeInsets.all(16), child: Column(children: [
    Text('$_daysSince', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w300, fontFamily: 'TideFont', color: Color(0xFF6B5B95))), const SizedBox(height: 4),
    const Text('相遇天数', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont'))]));
  Widget _buildMoodCard() {
    final icon = _moodIcons[_moodIcon] ?? Icons.sentiment_satisfied_rounded;
    return FrostCard(padding: const EdgeInsets.all(16), child: Column(children: [
      Icon(icon, size: 36, color: const Color(0xFF6B5B95)), const SizedBox(height: 4),
      Text(_moodLabel, style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont')), const SizedBox(height: 8),
      Wrap(spacing: 6, children: List.generate(_moods.length, (i) {
        final mIcon = _moodIcons[_moods[i]] ?? Icons.help_outline; final isActive = _moodIcon == _moods[i];
        return BouncyTap(onTap: () => setState(() { _moodIcon = _moods[i]; _moodLabel = _moodLabels[i]; }), child: Icon(mIcon, size: isActive ? 26 : 18, color: isActive ? const Color(0xFF6B5B95) : const Color(0xFFC7C7CC)));
      })),
    ]));
  }
  Widget _buildSectionTitle(String title) => Padding(padding: const EdgeInsets.only(left: 4), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))));
  Widget _buildScheduleCard(Map<String, dynamic> s) => FrostCard(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14), child: Row(children: [
    Container(width: 4, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: const Color(0xFF6B5B95))), const SizedBox(width: 12),
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
  const SquarePage({super.key}); @override State<SquarePage> createState() => _SquarePageState();
}
class _SquarePageState extends State<SquarePage> {
  bool _showGames = false;
  final _feeds = [
    {'user':'星野','content':'今天和我的AI聊了好久，感觉它真的懂我。','likes':'128','time':'2小时前'},
    {'user':'雨晴','content':'分享一张AI生成的星空图，太美了！','likes':'89','time':'5小时前'},
    {'user':'TideBot小伙伴','content':'刚发现了一个超好用的prompt技巧！','likes':'256','time':'1小时前'},
    {'user':'数字生命','content':'我的屿潭今天给我画了一幅画，好可爱。','likes':'67','time':'3小时前'},
  ];
  final _games = [
    {'name':'五子棋','desc':'经典对弈','iconKey':'grid'},{'name':'井字棋','desc':'三连获胜','iconKey':'circle'},
    {'name':'20问猜物','desc':'AI猜你心思','iconKey':'help'},{'name':'棋牌对战','desc':'多人娱乐','iconKey':'casino'},
    {'name':'文字冒险','desc':'沉浸式故事','iconKey':'book'},{'name':'真心话大冒险','desc':'和AI一起玩','iconKey':'favorite'},
  ];
  final Map<String, IconData> _gameIcons = {
    'grid':Icons.grid_4x4_rounded,'circle':Icons.circle_outlined,'help':Icons.help_outline_rounded,
    'casino':Icons.casino_rounded,'book':Icons.menu_book_rounded,'favorite':Icons.favorite_rounded,
  };
  void _launchGame(Map<String,String> g) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${g['name']} 正在开发中...', style: const TextStyle(fontFamily:'TideFont')), behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF6B5B95))); }
  @override Widget build(BuildContext context) => Container(color: const Color(0xFFF2F2F7),
    child: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16,12,8,8), child: Row(children: [
        const Spacer(),
        BouncyTap(onTap: ()=>setState(()=>_showGames=!_showGames), child: Container(padding: const EdgeInsets.symmetric(horizontal:14,vertical:8), decoration: BoxDecoration(borderRadius:BorderRadius.circular(20), color: const Color(0xFF6B5B95)), child: Row(mainAxisSize:MainAxisSize.min, children: [
          Icon(_showGames?Icons.article_rounded:Icons.videogame_asset_rounded, size:18, color:Colors.white),
          const SizedBox(width:6), Text(_showGames?'动态':'小游戏', style: const TextStyle(fontSize:14, fontWeight:FontWeight.w500, fontFamily:'TideFont', color:Colors.white))]))),
        const SizedBox(width:8), const Icon(Icons.trending_up_rounded, size:18, color:Color(0xFF6B5B95)),
        const SizedBox(width:4), const Text('热门', style: TextStyle(fontSize:13, color:Color(0xFF6B5B95), fontFamily:'TideFont')), const SizedBox(width:8),
      ])),
      Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds:400), switchInCurve:Curves.easeOutCubic, switchOutCurve:Curves.easeInCubic, transitionBuilder:(c,a)=>FadeTransition(opacity:a, child:c), child: _showGames?_buildGames():_buildFeeds())),
    ])));
  Widget _buildFeeds() => ListView.builder(key: const ValueKey('feeds'), padding: const EdgeInsets.fromLTRB(16,0,16,100), physics: const BouncingScrollPhysics(), itemCount: _feeds.length, itemBuilder:(ctx,i){
    final f=_feeds[i]; return BouncyTap(onTap:()=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${f['user']} 的动态', style: const TextStyle(fontFamily:'TideFont')), behavior:SnackBarBehavior.floating)),
    child: FrostCard(margin: const EdgeInsets.only(bottom:12), padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
      Row(children:[CircleAvatar(radius:18, backgroundColor: const Color(0xFF6B5B95).withOpacity(0.15), child: const Icon(Icons.person_rounded, size:20, color:Color(0xFF6B5B95))), const SizedBox(width:10),
        Column(crossAxisAlignment:CrossAxisAlignment.start, children:[Text(f['user']??'', style: const TextStyle(fontSize:15, fontWeight:FontWeight.w600, fontFamily:'TideFont')), Text(f['time']??'', style: const TextStyle(fontSize:11, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))])]),
      const SizedBox(height:12), Text(f['content']??'', style: const TextStyle(fontSize:14, fontFamily:'TideFont', color:Color(0xFF3C3C43), height:1.5)), const SizedBox(height:10),
      Row(children:[const Icon(Icons.favorite_border_rounded, size:18, color:Color(0xFFC7C7CC)), const SizedBox(width:4), Text(f['likes']??'0', style: const TextStyle(fontSize:13, color:Color(0xFFC7C7CC), fontFamily:'TideFont')), const Spacer(), const Icon(Icons.chat_bubble_outline_rounded, size:18, color:Color(0xFFC7C7CC))])])));});
  Widget _buildGames() => GridView.builder(key: const ValueKey('games'), padding: const EdgeInsets.fromLTRB(16,0,16,100), physics: const BouncingScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2, crossAxisSpacing:12, mainAxisSpacing:12, childAspectRatio:1.0), itemCount:_games.length, itemBuilder:(ctx,i){
    final g=_games[i]; final icon=_gameIcons[g['iconKey']]??Icons.extension_rounded;
    return BouncyTap(onTap:()=>_launchGame(g), child: FrostCard(padding: const EdgeInsets.all(16), child: Column(mainAxisAlignment:MainAxisAlignment.center, children: [
      Icon(icon, size:40, color: const Color(0xFF6B5B95)), const SizedBox(height:8),
      Text(g['name']??'', style: const TextStyle(fontSize:15, fontWeight:FontWeight.w600, fontFamily:'TideFont', color:Color(0xFF1C1C1E))),
      const SizedBox(height:4), Text(g['desc']??'', textAlign:TextAlign.center, maxLines:2, overflow:TextOverflow.ellipsis, style: const TextStyle(fontSize:11, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))])));});
}
