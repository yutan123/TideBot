import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

class ChatSidebar extends StatefulWidget {
  final Map<String, dynamic> bot;
  final Animation<double> progress;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final VoidCallback onClose;
  final ValueChanged<String> onOpenManager;

  const ChatSidebar({
    super.key,
    required this.bot,
    required this.progress,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onClose,
    required this.onOpenManager,
  });

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> with WidgetsBindingObserver {
  static const _indexKey = 'chat_sidebar_bot_index';
  static const _remainingKey = 'chat_sidebar_remaining_ms';

  final DBManager _db = DBManager();
  List<Map<String, dynamic>> _bots = const [];
  Map<String, dynamic>? _latestPost;
  String _userName = '用户';
  String _userAvatar = '';
  String _quote = '';
  int _index = 0;
  DateTime _nextRotation = DateTime.now().add(const Duration(seconds: 5));
  Timer? _ticker;
  Timer? _clock;
  DateTime _now = DateTime.now();
  bool _online = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _bots.length < 2) return;
      if (DateTime.now().isBefore(_nextRotation)) return;
      _nextRotation = DateTime.now().add(const Duration(seconds: 5));
      _index = (_index + 1) % _bots.length;
      _persistRotation();
      setState(() {});
    });
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _db.queryBots(),
      _db.queryPosts(limit: 1),
      _db.getKV('user_name'),
      _db.getKV('user_avatar'),
      _db.getKV(_indexKey),
      _db.getKV(_remainingKey),
    ]);
    final bots = results[0] as List<Map<String, dynamic>>;
    final savedIndex = int.tryParse(results[4]?.toString() ?? '') ?? 0;
    final savedRemaining = int.tryParse(results[5]?.toString() ?? '');
    final now = DateTime.now();
    final remaining = (savedRemaining ?? 5000).clamp(250, 5000);
    final next = now.add(Duration(milliseconds: remaining));
    final validIndex = bots.isEmpty ? 0 : savedIndex.clamp(0, bots.length - 1);
    if (!mounted) return;
    setState(() {
      _bots = bots;
      _latestPost = (results[1] as List<Map<String, dynamic>>).firstOrNull;
      _userName = (results[2] as String?)?.trim().isNotEmpty == true
          ? results[2] as String
          : '用户';
      _userAvatar = results[3] as String? ?? '';
      _index = validIndex;
      _nextRotation = next;
      _quote = _dailyQuote();
    });
    _checkOnline();
  }

  String _dailyQuote() {
    final available = _bots
        .map((bot) => bot['daily_quote']?.toString().trim() ?? '')
        .where((quote) => quote.isNotEmpty)
        .toList();
    if (available.isEmpty) {
      return '今天也和你一起，慢慢把事情做好。';
    }
    final day = DateTime.now();
    final seed = day.year * 10000 + day.month * 100 + day.day;
    return available[seed % available.length];
  }

  Future<void> _checkOnline() async {
    var online = false;
    try {
      final addresses = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 2));
      online = addresses.isNotEmpty;
    } catch (_) {}
    if (mounted) setState(() => _online = online);
  }

  Future<void> _persistRotation() async {
    final remaining = _nextRotation
        .difference(DateTime.now())
        .inMilliseconds
        .clamp(250, 5000);
    await _db.setKV(_indexKey, '$_index');
    await _db.setKV(_remainingKey, '$remaining');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _ticker?.cancel();
      _ticker = null;
      _persistRotation();
    } else if (state == AppLifecycleState.resumed && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || _bots.length < 2) return;
        if (DateTime.now().isBefore(_nextRotation)) return;
        _nextRotation = DateTime.now().add(const Duration(seconds: 5));
        _index = (_index + 1) % _bots.length;
        _persistRotation();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _persistRotation();
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final bot = _bots.isEmpty ? widget.bot : _bots[_index];
    final width = MediaQuery.sizeOf(context).width * .86;
    return AnimatedBuilder(
      animation: widget.progress,
      builder: (context, child) {
        final progress = widget.progress.value;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                onHorizontalDragUpdate: widget.onDragUpdate,
                onHorizontalDragEnd: widget.onDragEnd,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: .30 * progress),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(-width * (1 - progress), 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: theme.surface.withValues(alpha: .97),
                  child: SafeArea(
                    right: false,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _header(theme),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                              children: [
                                _timeCard(theme),
                                const SizedBox(height: 12),
                                _statusCard(theme, bot),
                                const SizedBox(height: 12),
                                _postCard(theme),
                                const SizedBox(height: 16),
                                _managerButton(theme, Icons.extension_rounded,
                                    'Skill', 'skill'),
                                const SizedBox(height: 8),
                                _managerButton(
                                    theme, Icons.hub_rounded, 'MCP', 'mcp'),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: IconButton(
                              tooltip: theme.isDark ? '切换到日间模式' : '切换到夜间模式',
                              onPressed: () => theme.cycleMode(),
                              icon: Icon(
                                theme.isDark
                                    ? Icons.light_mode_rounded
                                    : Icons.dark_mode_rounded,
                                color: theme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(TideTheme theme) {
    final avatar = _userAvatar.isNotEmpty && File(_userAvatar).existsSync()
        ? FileImage(File(_userAvatar))
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: theme.primary.withValues(alpha: .15),
            backgroundImage: avatar,
            child: avatar == null
                ? Icon(Icons.person_rounded, color: theme.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: theme.textStrong)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.circle,
                      size: 8,
                      color:
                          _online ? const Color(0xFF34C759) : theme.iconMuted),
                  const SizedBox(width: 5),
                  Text(_online ? '在线' : '离线',
                      style: TextStyle(fontSize: 12, color: theme.textWeak)),
                ]),
              ],
            ),
          ),
          IconButton(
              onPressed: widget.onClose,
              tooltip: '关闭',
              icon: Icon(Icons.close_rounded, color: theme.iconMuted)),
        ],
      ),
    );
  }

  Widget _timeCard(TideTheme theme) => _panel(
        theme,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: theme.textStrong)),
          Text(
              '${_now.year}年${_now.month}月${_now.day}日  ${_weekday(_now.weekday)}',
              style: TextStyle(color: theme.textWeak)),
          const SizedBox(height: 10),
          Text('“$_quote”',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: theme.textStrong)),
        ]),
      );

  Widget _statusCard(TideTheme theme, Map<String, dynamic> bot) => _panel(
        theme,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            TideBotAvatar(
                name: bot['name']?.toString() ?? 'TideBot',
                path: bot['avatar']?.toString(),
                size: 38),
            const SizedBox(width: 10),
            Expanded(
                child: Text(bot['name']?.toString() ?? 'TideBot',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: theme.textStrong))),
            if (_bots.length > 1)
              Text('${_index + 1}/${_bots.length}',
                  style: TextStyle(fontSize: 12, color: theme.textFaint)),
          ]),
          const SizedBox(height: 12),
          Text('当前心情：${_mood(bot)}', style: TextStyle(color: theme.textWeak)),
          const SizedBox(height: 5),
          FutureBuilder<Map<String, int>>(
            future: _db.todayBotStats(bot['id']?.toString() ?? ''),
            builder: (context, snapshot) {
              final stats = snapshot.data ?? const {'messages': 0, 'tokens': 0};
              return Text(
                  '今日发送 ${stats['messages']} 条  ·  ${stats['tokens']} token',
                  style: TextStyle(color: theme.textWeak));
            },
          ),
        ]),
      );

  Widget _postCard(TideTheme theme) => _panel(
        theme,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('最新动态',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: theme.textStrong)),
          const SizedBox(height: 8),
          Text(
              _latestPost?['content']?.toString().trim().isNotEmpty == true
                  ? _latestPost!['content'].toString()
                  : '还没有新的动态',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(height: 1.4, color: theme.textWeak)),
        ]),
      );

  Widget _managerButton(
          TideTheme theme, IconData icon, String label, String id) =>
      BouncyTap(
        onTap: () => widget.onOpenManager(id),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(icon, color: theme.primary),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: theme.textStrong, fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: theme.iconMuted)
          ]),
        ),
      );

  Widget _panel(TideTheme theme, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: theme.primary.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.primary.withValues(alpha: .16))),
        child: child,
      );

  String _mood(Map<String, dynamic> bot) =>
      bot['mood']?.toString().trim().isNotEmpty == true
          ? bot['mood'].toString()
          : '平静';
  String _weekday(int day) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day - 1];
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
