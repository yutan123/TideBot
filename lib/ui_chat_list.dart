import 'dart:async';
import 'package:flutter/material.dart';
import 'chat_event_bus.dart';
import 'chat_protocol.dart';
import 'message_delivery_service.dart';
import 'db.dart';
import 'ui_components.dart';
import 'chat_sidebar.dart';
import 'ui_chat_room.dart';
import 'theme.dart';
import 'bot_state.dart';

class ChatListPage extends StatefulWidget {
  final GlobalKey<ChatListPageState>? pageKey;
  final ChatSidebarController? sidebar;
  const ChatListPage({super.key, this.pageKey, this.sidebar});
  @override
  State<ChatListPage> createState() => ChatListPageState();
}

class ChatListPageState extends State<ChatListPage> {
  List<Map<String, dynamic>> _bots = [];
  bool _showParticles = false;
  int _particleRun = 0;
  final List<Offset> _origins = [];
  // Keys must outlive ListView rebuilds. Creating a GlobalKey inside itemBuilder
  // makes the key detached after a previous deletion, so later particles lose
  // their source RenderBox.
  final Map<String, GlobalKey> _botCardKeys = <String, GlobalKey>{};
  final Set<String> _openingBots = <String>{};

  StreamSubscription<ChatEvent>? _chatEvents;

  @override
  void initState() {
    super.initState();
    _chatEvents = ChatEventBus.instance.events.listen((event) {
      if (!mounted || event.botId == null) return;
      load();
    });
    load();
  }

  @override
  void dispose() {
    _chatEvents?.cancel();
    super.dispose();
  }

  void _openSidebar() {
    widget.sidebar?.open();
  }

  void _updateSidebarDrag(DragUpdateDetails details) {
    final width = MediaQuery.sizeOf(context).width * .86;
    widget.sidebar?.updateDrag(details.delta.dx, width);
  }

  void _endSidebarDrag(DragEndDetails details) {
    widget.sidebar?.endDrag(details.velocity.pixelsPerSecond.dx);
  }

  void load() async {
    final db = DBManager();
    List<Map<String, dynamic>> bots;
    try {
      bots = await db.queryBots();
    } catch (error) {
      print('[chat_list] queryBots failed: $error');
      if (mounted) {
        setState(() => _bots = []);
        widget.sidebar?.updateBot(null);
      }
      return;
    }
    final enriched = <Map<String, dynamic>>[];
    for (var b in bots) {
      // 取该机器人「最新」一条消息作聊天列表预览（按时间倒序取首条）。
      List<Map<String, dynamic>> msgs = const [];
      try {
        msgs = await DBManager()
            .queryMessages(b['id'] as String, limit: 30, descending: true);
      } catch (error) {
        print('[chat_list] queryMessages failed: $error');
      }
      String preview = '';
      int lastTime =
          (b['last_msg_time'] as int?) ?? (b['created_at'] as int?) ?? 0;
      if (msgs.isNotEmpty) {
        final chosen = msgs.firstWhere(
            (m) => m['type']?.toString() != 'sticker',
            orElse: () => msgs.first);
        final type = chosen['type']?.toString() ?? 'text';
        preview = chatListPreview(
          type: type,
          rawContent: chosen['content']?.toString() ?? '',
        );
        if (preview.length > 25) preview = '${preview.substring(0, 25)}...';
        lastTime = msgs.first['timestamp'] as int? ?? lastTime;
      }
      final latestAssistant = msgs
          .where((message) => message['role']?.toString() == 'assistant')
          .fold<int>(0, (latest, message) {
        final timestamp = (message['timestamp'] as num?)?.toInt() ?? 0;
        return timestamp > latest ? timestamp : latest;
      });
      final lastRead = (b['last_read_at'] as num?)?.toInt() ?? 0;
      enriched.add({
        ...b,
        'preview': preview,
        'lastTime': lastTime,
        'unread': latestAssistant > lastRead,
      });
    }
    enriched.sort((a, b) {
      final aPin = (a['is_pinned'] as int?) ?? 0;
      final bPin = (b['is_pinned'] as int?) ?? 0;
      if (aPin != bPin) return bPin.compareTo(aPin);
      return (b['lastTime'] as int).compareTo(a['lastTime'] as int);
    });
    if (mounted) {
      setState(() => _bots = enriched);
      widget.sidebar?.updateBot(enriched.isEmpty ? null : enriched.first);
    }
  }

  void _deleteBot(Map<String, dynamic> bot, GlobalKey key) async {
    final confirm = await TideDialogs.show<bool>(
      context: context,
      builder: (ctx) => TideDialogSurface(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: TideDialogs.glassContent(context: ctx, children: [
          const Center(
              child: Text('确认删除',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'TideFont'))),
          const SizedBox(height: 10),
          Align(
              alignment: Alignment.centerLeft,
              child: Text('确定删除「${bot['name']}」吗？\n此操作不可恢复。',
                  textAlign: TextAlign.start,
                  style: const TextStyle(
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
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final pos = box.localToGlobal(Offset.zero);
        final w = box.size.width;
        final h = box.size.height;
        // 全卡片范围撒点：四角 + 中心 + 随机分布
        _origins.clear();
        for (int i = 0; i < 12; i++) {
          _origins.add(Offset(pos.dx + w * (0.1 + 0.8 * (i / 11)),
              pos.dy + h * (0.2 + 0.6 * ((i * 7) % 11) / 10)));
        }
        setState(() {
          // 每次删除都递增 Key，强制 ParticleOverlay 创建新的动画状态。
          _particleRun++;
          _showParticles = true;
        });
      }
      await DBManager().deleteBot(bot['id'] as String);
      load();
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showParticles = false);
      });
    }
  }

  Future<void> _openChat(Map<String, dynamic> bot) async {
    final id = bot['id']?.toString() ?? '';
    if (id.isEmpty || !_openingBots.add(id)) return;
    if (mounted) setState(() {});
    try {
      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (c, a, s) => ChatRoomPage(botData: bot),
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          transitionsBuilder: (c, a, s, child) {
            final anim = CurvedAnimation(
              parent: a,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(anim),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
            );
          },
        ),
      );
      await MessageDeliveryService.instance.markRead(id);
      if (mounted) load();
    } finally {
      _openingBots.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: '打开 TideBot 侧栏',
                  child: GestureDetector(
                    onTap: _openSidebar,
                    child: Text('TideBot',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'TideFont',
                            color: TideTheme.of(context).textStrong)),
                  ),
                ))),
        Expanded(
            child: _bots.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inbox_rounded,
                        size: 50, color: Colors.grey.shade400),
                    const SizedBox(height: 10),
                    const Text('还没有机器人',
                        style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 15,
                            fontFamily: 'TideFont')),
                    const Text('点击右下角 + 创建',
                        style: TextStyle(
                            color: Color(0xFFC7C7CC),
                            fontSize: 13,
                            fontFamily: 'TideFont'))
                  ]))
                : _list()),
      ])),
    );
    final shell = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        final sidebar = widget.sidebar;
        if (sidebar == null ||
            sidebar.isOpen ||
            details.globalPosition.dx > 28 ||
            _bots.isEmpty) {
          return;
        }
        sidebar.beginDrag();
      },
      onHorizontalDragUpdate: (details) {
        if (widget.sidebar?.dragActive == true) _updateSidebarDrag(details);
      },
      onHorizontalDragEnd: (details) {
        if (widget.sidebar?.dragActive == true) _endSidebarDrag(details);
      },
      child: content,
    );
    return _showParticles
        ? ParticleOverlay(
            key: ValueKey(_particleRun),
            origins: _origins,
            onDone: () {
              if (mounted) setState(() => _showParticles = false);
            },
            child: shell,
          )
        : shell;
  }

  Widget _list() => ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: _bots.length,
      itemBuilder: (ctx, i) {
        final bot = _bots[i];
        final id = bot['id']?.toString() ?? 'bot_$i';
        final key = _botCardKeys.putIfAbsent(id, GlobalKey.new);
        return GestureDetector(
          key: key,
          onTap: () => _openChat(bot),
          onLongPress: () => showTideSheet(
              context: context,
              height: 232,
              child: Column(children: [
                const SizedBox(height: 10),
                ListTile(
                    leading: Icon(Icons.push_pin_rounded,
                        color: TideTheme.of(context).primary),
                    title: Text(
                        ((bot['is_pinned'] as int?) ?? 0) == 1 ? '取消置顶' : '置顶',
                        style: const TextStyle(fontFamily: 'TideFont')),
                    onTap: () {
                      Navigator.pop(context);
                      final pin =
                          ((bot['is_pinned'] as int?) ?? 0) == 1 ? 0 : 1;
                      DBManager().toggleBotPin(bot['id'] as String, pin);
                      load();
                    }),
                ListTile(
                    leading: Icon(
                        (bot['is_disabled'] == 1 || bot['is_disabled'] == true)
                            ? Icons.play_circle_outline_rounded
                            : Icons.pause_circle_outline_rounded,
                        color: const Color(0xFFF39C12)),
                    title: Text(
                        (bot['is_disabled'] == 1 || bot['is_disabled'] == true)
                            ? '启用机器人'
                            : '禁用机器人',
                        style: const TextStyle(fontFamily: 'TideFont')),
                    subtitle: const Text('禁用后机器人不会回复、执行日程或主动消息。',
                        style: TextStyle(fontFamily: 'TideFont', fontSize: 11)),
                    onTap: () async {
                      Navigator.pop(context);
                      final disabled = isBotDisabled(bot['is_disabled']);
                      await DBManager().updateBot(bot['id'] as String,
                          {'is_disabled': disabled ? 0 : 1});
                      load();
                    }),
                ListTile(
                    leading: const Icon(Icons.delete_rounded,
                        color: Color(0xFFE74C3C)),
                    title: const Text('删除机器人',
                        style: TextStyle(
                            fontFamily: 'TideFont', color: Color(0xFFE74C3C))),
                    onTap: () {
                      Navigator.pop(context);
                      _deleteBot(bot, key);
                    }),
              ])),
          child: Padding(
              padding: const EdgeInsets.only(bottom: 10), child: _card(bot)),
        );
      });

  Widget _card(Map<String, dynamic> bot) {
    final av = (bot['avatar'] as String?) ?? '';
    return GlassCard(
      liquid: true,
      padding: const EdgeInsets.all(14),
      onTap: () => _openChat(bot),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          TideBotAvatar(name: bot['name'] as String? ?? '', path: av, size: 56),
          if (bot['unread'] == true)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFE74C3C),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: TideTheme.of(context).bgColor, width: 2),
                ),
              ),
            ),
        ]),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (((bot['is_pinned'] as int?) ?? 0) == 1) ...[
              Icon(Icons.push_pin_rounded,
                  size: 14, color: TideTheme.of(context).primary),
              const SizedBox(width: 2),
            ],
            if (bot['is_disabled'] == 1 || bot['is_disabled'] == true) ...[
              const Icon(Icons.pause_circle_filled_rounded,
                  size: 17, color: Color(0xFFE67E22)),
              const SizedBox(width: 4),
            ],
            Flexible(
                child: Text(bot['name'] as String? ?? '',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'TideFont',
                        color: TideTheme.of(context).textStrong),
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 3),
          Text(bot['preview'] as String? ?? '点击开始对话',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  color: TideTheme.of(context).textWeak,
                  fontFamily: 'TideFont')),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtTime(bot['lastTime'] as int? ?? 0),
              style: TextStyle(
                  fontSize: 11,
                  color: TideTheme.of(context).textFaint,
                  fontFamily: 'TideFont')),
          const SizedBox(height: 4),
          Icon(Icons.chevron_right_rounded,
              size: 16, color: TideTheme.of(context).textFaint),
        ]),
      ]),
    );
  }
}
