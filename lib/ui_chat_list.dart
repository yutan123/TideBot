import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'db.dart';
import 'ui_components.dart';
import 'ui_chat_room.dart';
import 'theme.dart';

class ChatListPage extends StatefulWidget {
  final GlobalKey<ChatListPageState>? pageKey;
  const ChatListPage({Key? key, this.pageKey}) : super(key: key);
  @override State<ChatListPage> createState() => ChatListPageState();
}

class ChatListPageState extends State<ChatListPage> {
  List<Map<String, dynamic>> _bots = [];
  bool _showParticles = false;
  final List<Offset> _origins = [];

  @override void initState() { super.initState(); load(); }
  void load() async {
    final bots = await DBManager().queryBots();
    final enriched = <Map<String, dynamic>>[];
    for (var b in bots) {
      final msgs = await DBManager().queryMessages(b['id'] as String, limit: 1);
      String preview = '';
      int lastTime = (b['last_msg_time'] as int?) ?? (b['created_at'] as int?) ?? 0;
      if (msgs.isNotEmpty) {
        preview = (msgs.first['content'] as String?)?.replaceAll('\n', ' ') ?? '';
        if (preview.length > 25) preview = '${preview.substring(0, 25)}...';
        lastTime = msgs.first['timestamp'] as int? ?? lastTime;
      }
      enriched.add({...b, 'preview': preview, 'lastTime': lastTime});
    }
    enriched.sort((a, b) {
      final aPin = (a['is_pinned'] as int?) ?? 0;
      final bPin = (b['is_pinned'] as int?) ?? 0;
      if (aPin != bPin) return bPin.compareTo(aPin);
      return (b['lastTime'] as int).compareTo(a['lastTime'] as int);
    });
    if (mounted) setState(() => _bots = enriched);
  }

  void _deleteBot(Map<String, dynamic> bot, GlobalKey key) async {
    final confirm = await TideDialogs.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero,
        content: TideDialogs.glassContent(context: ctx, children: [
          const Center(child: Text('确认删除', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'TideFont'))),
          const SizedBox(height: 10),
          Center(child: Text('确定删除「${bot['name']}」吗？\n此操作不可恢复。', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Color(0xFF636366), fontFamily: 'TideFont'))),
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
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final pos = box.localToGlobal(Offset.zero);
        final w = box.size.width;
        final h = box.size.height;
        // 全卡片范围撒点：四角 + 中心 + 随机分布
        _origins.clear();
        for (int i = 0; i < 12; i++) {
          _origins.add(Offset(pos.dx + w * (0.1 + 0.8 * (i / 11)), pos.dy + h * (0.2 + 0.6 * ((i * 7) % 11) / 10)));
        }
        setState(() { _showParticles = true; });
      }
      await DBManager().deleteBot(bot['id'] as String);
      load();
      Future.delayed(const Duration(milliseconds: 1400), () { if (mounted) setState(() => _showParticles = false); });
    }
  }

  @override Widget build(BuildContext context) {
    Widget content = Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('TideBot', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, fontFamily: 'TideFont', color: TideTheme.of(context).textStrong)))),
        Expanded(child: _bots.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inbox_rounded, size: 50, color: Colors.grey.shade400), const SizedBox(height: 10), const Text('还没有机器人', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15, fontFamily: 'TideFont')), const Text('点击右下角 + 创建', style: TextStyle(color: Color(0xFFC7C7CC), fontSize: 13, fontFamily: 'TideFont'))])) : _list()),
      ])),
    );
    return _showParticles ? ParticleOverlay(child: content, origins: _origins, onDone: () { if (mounted) setState(() => _showParticles = false); }) : content;
  }

  Widget _list() => ListView.builder(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), itemCount: _bots.length, itemBuilder: (ctx, i) {
    final bot = _bots[i];
    final key = GlobalKey();
    return GestureDetector(
      key: key, onTap: () async { await Navigator.push(context, PageRouteBuilder(pageBuilder: (c, a, s) => ChatRoomPage(botData: bot), transitionDuration: const Duration(milliseconds: 380), reverseTransitionDuration: const Duration(milliseconds: 240), transitionsBuilder: (c, a, s, child) { final anim = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic); return SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim), child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1).animate(anim), child: FadeTransition(opacity: anim, child: child))); })); load(); },
      onLongPress: () => showTideSheet(context: context, height: 160, child: Column(children: [
        const SizedBox(height: 10),
        ListTile(leading: Icon(Icons.push_pin_rounded, color: TideTheme.of(context).primary), title: Text(((bot['is_pinned'] as int?) ?? 0) == 1 ? '取消置顶' : '置顶', style: const TextStyle(fontFamily: 'TideFont')), onTap: () { Navigator.pop(context); final pin = ((bot['is_pinned'] as int?) ?? 0) == 1 ? 0 : 1; DBManager().toggleBotPin(bot['id'] as String, pin); load(); }),
        ListTile(leading: const Icon(Icons.delete_rounded, color: Color(0xFFE74C3C)), title: const Text('删除机器人', style: TextStyle(fontFamily: 'TideFont', color: Color(0xFFE74C3C))), onTap: () { Navigator.pop(context); _deleteBot(bot, key); }),
      ])),
      child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(bot)),
    );
  });

  Widget _card(Map<String, dynamic> bot) {
    final av = (bot['avatar'] as String?) ?? '';
    final hasAv = av.isNotEmpty;
    return GlassCard(
      padding: const EdgeInsets.all(14), radius: 20,
      onTap: () async { await Navigator.push(context, PageRouteBuilder(pageBuilder: (c, a, s) => ChatRoomPage(botData: bot), transitionDuration: const Duration(milliseconds: 380), reverseTransitionDuration: const Duration(milliseconds: 240), transitionsBuilder: (c, a, s, child) { final anim = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic); return SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim), child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1).animate(anim), child: FadeTransition(opacity: anim, child: child))); })); load(); },
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(width: 50, height: 50, color: const Color(0xFFE8E8F0), child: hasAv ? Image.file(File(av), fit: BoxFit.cover) : Center(child: Text((bot['name'] as String? ?? '?')[0], style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TideTheme.of(context).primary, fontFamily: 'TideFont'))))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (((bot['is_pinned'] as int?) ?? 0) == 1) ...[
              Icon(Icons.push_pin_rounded, size: 14, color: TideTheme.of(context).primary),
              const SizedBox(width: 2),
            ],
            Flexible(child: Text(bot['name'] as String? ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'TideFont', color: TideTheme.of(context).textStrong), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 3),
          Text(bot['preview'] as String? ?? '点击开始对话', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: TideTheme.of(context).textWeak, fontFamily: 'TideFont')),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtTime(bot['lastTime'] as int? ?? 0), style: TextStyle(fontSize: 11, color: TideTheme.of(context).textFaint, fontFamily: 'TideFont')),
          const SizedBox(height: 4),
          Icon(Icons.chevron_right_rounded, size: 16, color: TideTheme.of(context).textFaint),
        ]),
      ]),
    );
  }
}
