import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'ui_components.dart';
import 'db.dart';
import 'ai.dart';
import 'main.dart';

// ==================== 空间页 ====================
class SpacePage extends StatefulWidget {
  final PageController? pageController;
  const SpacePage({super.key, this.pageController});
  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  String _botId = '';
  String _botName = '未连接';
  String _dailyQuote = '加载中...';
  int _daysSince = 0;
  String _moodIcon = 'smile';
  String _moodLabel = '平静';
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;

  final List<String> _moods = ['smile', 'heart', 'sad', 'angry', 'sleep', 'think'];
  final List<String> _moodLabels = ['开心', '幸福', '难过', '生气', '困倦', '思考'];
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

  Future<void> _loadData() async {
    final db = DBManager();
    final bots = await db.queryBots();
    if (bots.isNotEmpty) {
      final b = bots.first;
      _botId = b['id'] ?? '';
      _botName = b['name'] ?? '未命名';
      _dailyQuote = b['daily_quote'] ?? '每一天都值得被温柔对待';
      final created = b['created_at'] ?? '';
      if (created is String && created.isNotEmpty) {
        _daysSince = DateTime.now().difference(DateTime.tryParse(created) ?? DateTime.now()).inDays;
      }
      final sch = await db.querySchedules(_botId, limit: 2);
      final mem = await db.queryMemories(_botId, type: 'medium', limit: 2);
      if (mounted) {
        setState(() {
          _schedules = sch;
          _memories = mem;
          _loading = false;
        });
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr = '${now.year}.${now.month}.${now.day}';

    return Container(
      color: const Color(0xFFF2F2F7),
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF6B5B95)))
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildHeader(timeStr, dateStr),
                  const SizedBox(height: 20),
                  _buildQuoteCard(),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _buildDaysCard()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildMoodCard()),
                  ]),
                  const SizedBox(height: 16),
                  _buildSectionTitle('最近日程'),
                  const SizedBox(height: 8),
                  if (_schedules.isEmpty) _buildEmptyHint('暂无日程') else ..._schedules.map((s) => _buildScheduleCard(s)),
                  const SizedBox(height: 16),
                  _buildSectionTitle('TA 的日记'),
                  const SizedBox(height: 8),
                  if (_memories.isEmpty) _buildEmptyHint('暂无日记') else ..._memories.map((m) => _buildMemoryCard(m)),
                ]),
              ),
      ),
    );
  }

  Widget _buildHeader(String time, String date) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(time, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
        Text(date, style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93), fontFamily: 'TideFont')),
      ]),
      GestureDetector(
        onTap: () async {
          final db = DBManager();
          final bots = await db.queryBots();
          if (!mounted) return;
          showTideSheet(context, builder: (ctx) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('切换机器人', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'TideFont')),
                const SizedBox(height: 12),
                ...bots.map((b) => ListTile(
                      title: Text(b['name'] ?? '', style: const TextStyle(fontFamily: 'TideFont')),
                      subtitle: Text(b['personality'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                      onTap: () {
                        setState(() { _botId = b['id'] ?? ''; _botName = b['name'] ?? ''; });
                        Navigator.pop(ctx);
                        _loadData();
                      },
                    )),
              ]),
            );
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white.withOpacity(0.8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_botName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'TideFont', color: Color(0xFF6B5B95))),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF6B5B95)),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildQuoteCard() {
    return FrostCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.format_quote_rounded, color: Color(0xFF6B5B95), size: 20),
          SizedBox(width: 8),
          Text('今日一言', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: Color(0xFF6B5B95))),
        ]),
        const SizedBox(height: 10),
        Text(_dailyQuote, style: const TextStyle(fontSize: 16, fontFamily: 'TideFont', color: Color(0xFF3C3C43), height: 1.5)),
      ]),
    );
  }

  Widget _buildDaysCard() {
    return FrostCard(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Text('$_daysSince', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w300, fontFamily: 'TideFont', color: Color(0xFF6B5B95))),
        const SizedBox(height: 4),
        const Text('相遇天数', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont')),
      ]),
    );
  }

  Widget _buildMoodCard() {
    final icon = _moodIcons[_moodIcon] ?? Icons.sentiment_satisfied_rounded;
    return FrostCard(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Icon(icon, size: 36, color: const Color(0xFF6B5B95)),
        const SizedBox(height: 4),
        Text(_moodLabel, style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont')),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: List.generate(_moods.length, (i) {
          final mIcon = _moodIcons[_moods[i]] ?? Icons.help_outline;
          final isActive = _moodIcon == _moods[i];
          return GestureDetector(
            onTap: () => setState(() { _moodIcon = _moods[i]; _moodLabel = _moodLabels[i]; }),
            child: Icon(mIcon, size: isActive ? 26 : 18, color: isActive ? const Color(0xFF6B5B95) : const Color(0xFFC7C7CC)),
          );
        })),
      ]),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> s) {
    return FrostCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(width: 4, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: const Color(0xFF6B5B95))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['title'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'TideFont')),
          if ((s['note'] ?? '').toString().isNotEmpty)
            Text(s['note'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        Text(formatTime(s['time']), style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont')),
      ]),
    );
  }

  Widget _buildMemoryCard(Map<String, dynamic> m) {
    return FrostCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m['title'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'TideFont')),
        const SizedBox(height: 4),
        Text(m['content'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF3C3C43)), maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text(formatTime(m['created_at']), style: const TextStyle(fontSize: 11, color: Color(0xFFC7C7CC), fontFamily: 'TideFont')),
      ]),
    );
  }

  Widget _buildEmptyHint(String text) {
    return FrostCard(
      padding: const EdgeInsets.all(20),
      child: Center(child: Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFFC7C7CC), fontFamily: 'TideFont'))),
    );
  }
}

// ==================== 广场页 ====================
class SquarePage extends StatefulWidget {
  const SquarePage({super.key});
  @override
  State<SquarePage> createState() => _SquarePageState();
}

class _SquarePageState extends State<SquarePage> {
  int _tabIndex = 0;

  final List<Map<String, String>> _feeds = [
    {'user': '星野', 'content': '今天和我的AI聊了好久，感觉它真的懂我。', 'likes': '128', 'time': '2小时前'},
    {'user': '雨晴', 'content': '分享一张AI生成的星空图，太美了！', 'likes': '89', 'time': '5小时前'},
  ];

  final List<Map<String, String>> _games = [
    {'name': '五子棋', 'desc': '经典对弈', 'iconKey': 'grid'},
    {'name': '井字棋', 'desc': '三连获胜', 'iconKey': 'circle'},
    {'name': '20问猜物', 'desc': 'AI猜你心思', 'iconKey': 'help'},
    {'name': '棋牌对战', 'desc': '多人娱乐', 'iconKey': 'casino'},
  ];

  final Map<String, IconData> _gameIcons = {
    'grid': Icons.grid_4x4_rounded,
    'circle': Icons.circle_outlined,
    'help': Icons.help_outline_rounded,
    'casino': Icons.casino_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              _buildTabBtn('动态', 0),
              const SizedBox(width: 10),
              _buildTabBtn('小游戏', 1),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: Colors.white.withOpacity(0.7)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.trending_up_rounded, size: 16, color: Color(0xFF6B5B95)),
                  SizedBox(width: 4),
                  Text('热门', style: TextStyle(fontSize: 13, color: Color(0xFF6B5B95), fontFamily: 'TideFont')),
                ]),
              ),
            ]),
          ),
          Expanded(child: _tabIndex == 0 ? _buildFeeds() : _buildGames()),
        ]),
      ),
    );
  }

  Widget _buildTabBtn(String text, int idx) {
    final active = _tabIndex == idx;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: active ? const Color(0xFF6B5B95) : Colors.white.withOpacity(0.7),
        ),
        child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'TideFont', color: active ? Colors.white : const Color(0xFF8E8E93))),
      ),
    );
  }

  Widget _buildFeeds() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: _feeds.length,
      itemBuilder: (ctx, i) {
        final f = _feeds[i];
        return FrostCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 18, backgroundColor: const Color(0xFF6B5B95).withOpacity(0.15), child: const Icon(Icons.person_rounded, size: 20, color: Color(0xFF6B5B95))),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f['user'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont')),
                Text(f['time'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFFC7C7CC), fontFamily: 'TideFont')),
              ]),
            ]),
            const SizedBox(height: 12),
            Text(f['content'] ?? '', style: const TextStyle(fontSize: 14, fontFamily: 'TideFont', color: Color(0xFF3C3C43), height: 1.5)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.favorite_border_rounded, size: 18, color: Color(0xFFC7C7CC)),
              const SizedBox(width: 4),
              Text(f['likes'] ?? '0', style: const TextStyle(fontSize: 13, color: Color(0xFFC7C7CC), fontFamily: 'TideFont')),
              const Spacer(),
              const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Color(0xFFC7C7CC)),
            ]),
          ]),
        );
      },
    );
  }

  Widget _buildGames() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.1),
      itemCount: _games.length,
      itemBuilder: (ctx, i) {
        final g = _games[i];
        final icon = _gameIcons[g['iconKey']] ?? Icons.extension_rounded;
        return FrostCard(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 40, color: const Color(0xFF6B5B95)),
            const SizedBox(height: 8),
            Text(g['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
            const SizedBox(height: 4),
            Text(g['desc'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFFC7C7CC), fontFamily: 'TideFont')),
          ]),
        );
      },
    );
  }
}

// ==================== 我的页 ====================
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _userName = '用户';

  final List<Map<String, dynamic>> _settings = [
    {'icon': Icons.api_rounded, 'title': 'API 设置', 'page': 'api'},
    {'icon': Icons.cloud_download_rounded, 'title': '本地模型', 'page': 'local'},
    {'icon': Icons.palette_rounded, 'title': '主题设置', 'page': 'theme'},
    {'icon': Icons.notifications_rounded, 'title': '通知管理', 'page': 'notify'},
    {'icon': Icons.security_rounded, 'title': '隐私与安全', 'page': 'privacy'},
    {'icon': Icons.info_rounded, 'title': '关于 TideBot', 'page': 'about'},
    {'icon': Icons.storage_rounded, 'title': '数据管理', 'page': 'data'},
    {'icon': Icons.feedback_rounded, 'title': '反馈与建议', 'page': 'feedback'},
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final db = DBManager();
    final name = await db.getKV('user_name');
    if (mounted && name != null && name.isNotEmpty) setState(() => _userName = name);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F2F7),
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          child: Column(children: [
            _buildProfileCard(),
            const SizedBox(height: 24),
            ..._settings.map((s) => _buildSettingItem(s)),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return FrostCard(
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        GestureDetector(
          onTap: () async {
            final ctrl = TextEditingController(text: _userName);
            final result = await showTideDialog(context, builder: (ctx) => AlertDialog(
              title: const Text('修改昵称', style: TextStyle(fontFamily: 'TideFont')),
              content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '输入新昵称')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('确定')),
              ],
            ));
            if (result != null && result.toString().isNotEmpty) {
              setState(() => _userName = result.toString());
              await DBManager().insertKV('user_name', result.toString());
            }
          },
          child: CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFF6B5B95).withOpacity(0.15),
            child: const Icon(Icons.person_rounded, size: 36, color: Color(0xFF6B5B95)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_userName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
          const SizedBox(height: 4),
          const Text('点击头像修改信息', style: TextStyle(fontSize: 13, color: Color(0xFFC7C7CC), fontFamily: 'TideFont')),
        ])),
        const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFFC7C7CC)),
      ]),
    );
  }

  Widget _buildSettingItem(Map<String, dynamic> s) {
    return GestureDetector(
      onTap: () {
        if (s['page'] == 'api') {
          Navigator.push(context, _fadeRoute(const ApiSettingsPage()));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s['title']}功能开发中...'), behavior: SnackBarBehavior.floating));
        }
      },
      child: FrostCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(s['icon'] as IconData, size: 22, color: const Color(0xFF6B5B95)),
          const SizedBox(width: 14),
          Expanded(child: Text(s['title'] ?? '', style: const TextStyle(fontSize: 16, fontFamily: 'TideFont', color: Color(0xFF1C1C1E)))),
          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFC7C7CC)),
        ]),
      ),
    );
  }

  Route _fadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

// ==================== API 设置页 ====================
class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});
  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final List<Map<String, String>> _presets = [
    {'name': 'DeepSeek', 'url': 'https://api.deepseek.com/v1', 'key': ''},
    {'name': 'SiliconFlow', 'url': 'https://api.siliconflow.cn/v1', 'key': ''},
    {'name': 'GiteeAI', 'url': 'https://ai.gitee.com/v1', 'key': ''},
    {'name': '阿里云百炼', 'url': 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'key': ''},
    {'name': 'Kimi', 'url': 'https://api.moonshot.cn/v1', 'key': ''},
  ];

  int _selectedPreset = 0;
  bool _customMode = false;
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  String _testResult = '';
  bool _testing = false;
  String _ttsProvider = 'SiliconFlow';
  final List<String> _ttsPresets = ['SiliconFlow', '阿里云百炼', 'MiniMax', 'Edge-TTS'];
  bool _localQwen = false;
  bool _localGemma = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = _presets[0]['url'] ?? '';
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final db = DBManager();
    final provs = await db.queryProviders();
    if (provs.isNotEmpty) {
      final p = provs.first;
      if (mounted) {
        setState(() {
          _urlCtrl.text = p['url'] ?? '';
          _keyCtrl.text = p['api_key'] ?? '';
          _customMode = true;
        });
      }
    }
    final tts = await db.getKV('tts_provider');
    if (tts != null && mounted) setState(() => _ttsProvider = tts);
  }

  Future<void> _saveProvider() async {
    final db = DBManager();
    await db.deleteProviders();
    await db.insertProviderNew('custom', _urlCtrl.text.trim(), _keyCtrl.text.trim());
    await db.insertKV('tts_provider', _ttsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API 配置已保存'), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testResult = '测试中...'; });
    try {
      final ai = AIManager();
      final ms = await ai.testConnection(_urlCtrl.text.trim(), _keyCtrl.text.trim(), 'deepseek-chat');
      if (mounted) setState(() => _testResult = '连接成功！延迟 ${ms}ms');
    } catch (e) {
      if (mounted) setState(() => _testResult = '连接失败: $e');
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('API 设置', style: TextStyle(fontFamily: 'TideFont', fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size: 20), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(onPressed: _saveProvider, child: const Text('保存', style: TextStyle(fontFamily: 'TideFont', color: Color(0xFF6B5B95)))),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('选择提供商', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont')),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: List.generate(_presets.length, (i) {
            final active = !_customMode && _selectedPreset == i;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _customMode = false;
                  _selectedPreset = i;
                  _urlCtrl.text = _presets[i]['url'] ?? '';
                  _keyCtrl.text = _presets[i]['key'] ?? '';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: active ? const Color(0xFF6B5B95) : Colors.white.withOpacity(0.8)),
                child: Text(_presets[i]['name'] ?? '', style: TextStyle(fontSize: 13, fontFamily: 'TideFont', color: active ? Colors.white : const Color(0xFF3C3C43))),
              ),
            );
          })),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _customMode = !_customMode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: _customMode ? const Color(0xFF6B5B95) : Colors.white.withOpacity(0.8)),
              child: Text('自定义', style: TextStyle(fontSize: 13, fontFamily: 'TideFont', color: _customMode ? Colors.white : const Color(0xFF3C3C43))),
            ),
          ),
          const SizedBox(height: 20),
          _buildInput('API 地址', _urlCtrl),
          const SizedBox(height: 12),
          _buildInput('API Key', _keyCtrl, obscure: true),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FrostCard(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _testing ? null : _testConnection,
                  child: Center(
                    child: _testing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('测试连接', style: TextStyle(fontFamily: 'TideFont', color: Color(0xFF6B5B95), fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
            ),
          ]),
          if (_testResult.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_testResult, style: TextStyle(fontSize: 13, color: _testResult.contains('成功') ? const Color(0xFF34C759) : const Color(0xFFFF3B30), fontFamily: 'TideFont')),
            ),
          const SizedBox(height: 24),
          const Text('语音合成 (TTS)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont')),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: _ttsPresets.map((t) {
            final active = _ttsProvider == t;
            return GestureDetector(
              onTap: () => setState(() => _ttsProvider = t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: active ? const Color(0xFF6B5B95) : Colors.white.withOpacity(0.8)),
                child: Text(t, style: TextStyle(fontSize: 13, fontFamily: 'TideFont', color: active ? Colors.white : const Color(0xFF3C3C43))),
              ),
            );
          }).toList()),
          const SizedBox(height: 24),
          const Text('本地模型（下载后离线使用）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont')),
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text('Qwen2.5-0.5B', style: TextStyle(fontFamily: 'TideFont')),
            subtitle: const Text('约 400MB', style: TextStyle(fontSize: 12, color: Color(0xFFC7C7CC))),
            value: _localQwen, activeColor: const Color(0xFF6B5B95),
            onChanged: (v) => setState(() => _localQwen = v),
          ),
          SwitchListTile(
            title: const Text('Gemma-2B', style: TextStyle(fontFamily: 'TideFont')),
            subtitle: const Text('约 1.5GB', style: TextStyle(fontSize: 12, color: Color(0xFFC7C7CC))),
            value: _localGemma, activeColor: const Color(0xFF6B5B95),
            onChanged: (v) => setState(() => _localGemma = v),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, {bool obscure = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontFamily: 'TideFont')),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white.withOpacity(0.8)),
        child: TextField(
          controller: ctrl, obscureText: obscure,
          style: const TextStyle(fontSize: 14, fontFamily: 'TideFont'),
          decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: InputBorder.none),
        ),
      ),
    ]);
  }
}
