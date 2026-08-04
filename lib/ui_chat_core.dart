import 'dart:ui';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'db.dart';
import 'ai.dart';
import 'ops.dart';

// 绝对防线：严禁使用系统原生弹窗
class TideDialogs {
  static Future<T?> showBottomSheet<T>({required BuildContext context, required Widget child}) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<T>(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), 
          child: Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), 
            color: Colors.white.withOpacity(0.85), 
            child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(28), child: child))
          )
        ),
      ),
    );
  }
  static Future<T?> showCustomDialog<T>({required BuildContext context, required Widget child}) {
    HapticFeedback.lightImpact();
    return showGeneralDialog<T>(
      context: context, barrierDismissible: true, barrierLabel: '', barrierColor: Colors.black.withOpacity(0.4), transitionDuration: const Duration(milliseconds: 300), pageBuilder: (c,a,s) => const SizedBox(), 
      transitionBuilder: (c,a,s,_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15*a.value, sigmaY: 15*a.value), 
        child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: FadeTransition(opacity: a, child: Dialog(backgroundColor: Colors.transparent, elevation: 0, child: child)))
      )
    );
  }
}

// 粒子爆炸引擎
class Particle {
  double x, y, vx, vy, size; Color color; double life = 1.0;
  Particle(this.x, this.y, this.vx, this.vy, this.size, this.color);
  void update() { x += vx; y += vy; vy += 0.5; life -= 0.03; size *= 0.92; }
}
class ExplosionPainter extends CustomPainter {
  final List<Particle> p; ExplosionPainter(this.p);
  @override void paint(Canvas c, Size s) { final pt = Paint()..style = PaintingStyle.fill; for (var v in p) { if (v.life > 0) { pt.color = v.color.withOpacity(v.life.clamp(0.0, 1.0)); c.drawCircle(Offset(v.x, v.y), v.size, pt); } } }
  @override bool shouldRepaint(covariant ExplosionPainter o) => true;
}

// ================== 聊天列表主界面 ==================
class ChatListPage extends StatefulWidget {
  const ChatListPage({Key? key}) : super(key: key);
  @override State<ChatListPage> createState() => _ChatListPageState();
}
class _ChatListPageState extends State<ChatListPage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _bots = [];
  Map<String, AnimationController> _expCtrls = {};
  Map<String, List<Particle>> _expParts = {};
  final math.Random _rnd = math.Random();

  @override void initState() { super.initState(); _loadData(); }
  void _loadData() async { final data = await DBManager().getAllBots(); setState(() => _bots = data); }

  void _triggerExplosion(String botId, Rect rect) {
    _expParts[botId] = List.generate(30, (_) => Particle(rect.width/2 + _rnd.nextDouble()*60-30, rect.height/2 + _rnd.nextDouble()*40-20, _rnd.nextDouble()*16-8, _rnd.nextDouble()*16-12, _rnd.nextDouble()*5+3, Colors.black87));
    _expCtrls[botId] = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..addListener(() { setState((){ for(var p in _expParts[botId]!) p.update(); }); })..addStatusListener((s) async { if (s == AnimationStatus.completed) { await DBManager().deleteBot(botId); _loadData(); } });
    _expCtrls[botId]!.forward();
  }

  void _showCreateModal() {
    final nameC = TextEditingController(), descC = TextEditingController(), promptC = TextEditingController();
    TideDialogs.showBottomSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("创造新生命", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)), const SizedBox(height: 24),
      TextField(controller: nameC, decoration: InputDecoration(filled: true, fillColor: Colors.black.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), hintText: "名字 (如: 屿潭)")), const SizedBox(height: 16),
      TextField(controller: descC, maxLines: 2, decoration: InputDecoration(filled: true, fillColor: Colors.black.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), hintText: "身世与人格设定 (如: 傲娇的魔法师)")), const SizedBox(height: 16),
      TextField(controller: promptC, maxLines: 2, decoration: InputDecoration(filled: true, fillColor: Colors.black.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), hintText: "说话方式指令 (如: 每句话带个喵)")), const SizedBox(height: 32),
      GestureDetector(onTap: () async {
        if (nameC.text.isEmpty) return; 
        await DBManager().insertBot({'id': 'bot_${DateTime.now().millisecondsSinceEpoch}', 'name': nameC.text, 'desc': descC.text, 'prompt': promptC.text, 'created_at': DateTime.now().millisecondsSinceEpoch}); 
        Navigator.pop(context); _loadData();
      }, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(28)), alignment: Alignment.center, child: const Text("生成生命体", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))))
    ]));
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(left: 28, top: 20, bottom: 10), child: Text('TideBot', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1))),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10).copyWith(bottom: 120), itemCount: _bots.length,
            itemBuilder: (context, index) {
              final bot = _bots[index];
              final dt = DateTime.fromMillisecondsSinceEpoch(bot['created_at']);
              final timeStr = "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}"; // 24小时制，无 AM/PM
              final isExp = _expCtrls.containsKey(bot['id']) && _expCtrls[bot['id']]!.isAnimating;
              
              if (isExp) return CustomPaint(painter: ExplosionPainter(_expParts[bot['id']]!), child: const SizedBox(height: 120, width: double.infinity));

              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(context, PageRouteBuilder(pageBuilder: (c,a,s) => ChatRoomPage(botData: bot), transitionsBuilder: (c,a,s,child) => SlideTransition(position: Tween<Offset>(begin: const Offset(1,0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child))).then((_) => _loadData());
                },
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  TideDialogs.showBottomSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(leading: const Icon(Icons.push_pin_rounded), title: const Text("置顶", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), onTap: () => Navigator.pop(context)),
                    ListTile(leading: const Icon(Icons.delete_rounded, color: Colors.red), title: const Text("删除", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)), onTap: () {
                      Navigator.pop(context);
                      TideDialogs.showCustomDialog(context: context, child: Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(36)), child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.warning_rounded, color: Colors.red, size: 48), const SizedBox(height: 16),
                        const Text("确认销毁？", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 12), const Text("此操作将抹除该生命体的所有记忆与设定，且不可逆转。", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.5)), const SizedBox(height: 28),
                        Row(children: [Expanded(child: GestureDetector(onTap: () => Navigator.pop(context), child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(20)), alignment: Alignment.center, child: const Text("取消", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))))), const SizedBox(width: 12), Expanded(child: GestureDetector(onTap: () { Navigator.pop(context); _triggerExplosion(bot['id'], const Rect.fromLTWH(0,0,300,120)); }, child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)), alignment: Alignment.center, child: const Text("彻底销毁", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))))])
                      ])));
                    })
                  ]));
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 12))]),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 64, height: 64, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black), alignment: Alignment.center, child: Text(bot['name'].substring(0,1), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900))),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(bot['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)), 
                      const SizedBox(height: 6), 
                      Text(bot['desc'] ?? "暂无设定", maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: Colors.grey.shade500, height: 1.4))
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(timeStr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade400)), const SizedBox(height: 16), Icon(Icons.chevron_right_rounded, size: 24, color: Colors.grey.shade300)])
                  ]),
                ),
              );
            },
          )),
        ]),
      ),
      floatingActionButton: Padding(padding: const EdgeInsets.only(bottom: 100), child: FloatingActionButton(onPressed: _showCreateModal, backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), elevation: 12, child: const Icon(Icons.add_rounded, color: Colors.white, size: 32))),
    );
  }
}

// ================= 沉浸式聊天室 =================
class ChatRoomPage extends StatefulWidget {
  final Map<String, dynamic> botData;
  const ChatRoomPage({Key? key, required this.botData}) : super(key: key);
  @override State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> with SingleTickerProviderStateMixin {
  final TextEditingController _msgC = TextEditingController();
  final ScrollController _scrollC = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  bool _isRecording = false;
  String? _bgPath;
  late AnimationController _micAnim;

  @override void initState() { 
    super.initState(); 
    _micAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
    _loadHistory(); _loadBg(); 
  }
  @override void dispose() { _micAnim.dispose(); _msgC.dispose(); _scrollC.dispose(); super.dispose(); }

  void _loadHistory() async { final res = await DBManager().getChatHistory(widget.botData['id']); setState(() => _messages = res); _scrollToBottom(); }
  void _loadBg() async { final path = await DBManager().getKV('chat_bg_${widget.botData['id']}'); if (path != null) setState(() => _bgPath = path); }

  void _scrollToBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollC.hasClients) _scrollC.animateTo(_scrollC.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic); }); }

  void _send({String? text, String? imagePath, String? audioPath}) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    
    // 如果有图，分离展示
    if (imagePath != null) {
      final imgMsg = {'id': 'msg_u_img_$ts', 'bot_id': widget.botData['id'], 'role': 'user', 'type': 'image', 'file_path': imagePath, 'timestamp': ts};
      await DBManager().insertChatMessage(imgMsg);
      setState(() => _messages.add(imgMsg));
    }
    // 文字或音频
    if (text != null && text.isNotEmpty) {
      final txtMsg = {'id': 'msg_u_txt_${ts+1}', 'bot_id': widget.botData['id'], 'role': 'user', 'type': 'text', 'content': text, 'timestamp': ts + 1};
      await DBManager().insertChatMessage(txtMsg);
      setState(() => _messages.add(txtMsg));
    } else if (audioPath != null) {
      final audMsg = {'id': 'msg_u_aud_${ts+1}', 'bot_id': widget.botData['id'], 'role': 'user', 'type': 'audio', 'file_path': audioPath, 'timestamp': ts + 1};
      await DBManager().insertChatMessage(audMsg);
      setState(() => _messages.add(audMsg));
    }

    _msgC.clear(); _scrollToBottom();
    setState(() => _isTyping = true);
    
    // 发送给模型是合并发送的
    final res = await AIManager().sendMessage(botId: widget.botData['id'], text: text ?? "[语音/图片]", imagePath: imagePath);
    setState(() => _isTyping = false);
    if (res['success'] == true) _loadHistory();
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? '网络异常')));
  }

  // 长按菜单
  void _showMsgMenu(Map<String, dynamic> msg) {
    TideDialogs.showBottomSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, children: [
      if(msg['type']=='text') ListTile(leading: const Icon(Icons.copy_rounded), title: const Text("复制", style: TextStyle(fontWeight: FontWeight.bold)), onTap: () { Clipboard.setData(ClipboardData(text: msg['content'])); Navigator.pop(context); }),
      if(msg['type']=='text') ListTile(leading: const Icon(Icons.edit_rounded), title: const Text("编辑", style: TextStyle(fontWeight: FontWeight.bold)), onTap: () { /* 预留编辑口 */ Navigator.pop(context); }),
      if(msg['type']=='text') ListTile(leading: const Icon(Icons.format_quote_rounded), title: const Text("引用", style: TextStyle(fontWeight: FontWeight.bold)), onTap: () { /* 预留引用口 */ Navigator.pop(context); }),
      ListTile(leading: const Icon(Icons.delete_rounded, color: Colors.red), title: const Text("删除", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), onTap: () async { await DBManager().deleteMessage(msg['id']); Navigator.pop(context); _loadHistory(); }),
    ]));
  }

  // 构建富文本，正则分离括号内的动作描写
  RichText _buildRichText(String text, bool isUser) {
    List<TextSpan> spans = [];
    final regex = RegExp(r'(\(.*?\)|（.*?）)');
    final matches = regex.allMatches(text);
    int lastMatchEnd = 0;

    for (var match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start), style: TextStyle(fontSize: 16, color: isUser ? Colors.white : Colors.black87, height: 1.5)));
      }
      spans.add(TextSpan(text: match.group(0), style: TextStyle(fontSize: 14, color: isUser ? Colors.white70 : Colors.grey.shade500, fontStyle: FontStyle.italic, height: 1.5)));
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: TextStyle(fontSize: 16, color: isUser ? Colors.white : Colors.black87, height: 1.5)));
    }
    return RichText(text: TextSpan(children: spans, style: const TextStyle(fontFamily: 'TideFont')));
  }

  @override Widget build(BuildContext context) {
    // 强制适配：如果用户自定义了背景，必须全局使用毛玻璃，否则使用白色
    final isCustomBg = _bgPath != null;
    final barBgColor = isCustomBg ? Colors.white.withOpacity(0.4) : Colors.white.withOpacity(0.9);
    final blurSigma = isCustomBg ? 30.0 : 10.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: Stack(
        children: [
          if (isCustomBg) Positioned.fill(child: Image.file(File(_bgPath!), fit: BoxFit.cover)),
          Column(
            children: [
              // 自定义顶部栏 (从右到左: 菜单、设置、删除、电话)
              ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: Container(
                    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, bottom: 10, left: 10, right: 10),
                    color: barBgColor,
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22), onPressed: () => Navigator.pop(context)),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.botData['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                          if (_isTyping) const Text("正在输入中...", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))
                        ])),
                        IconButton(icon: const Icon(Icons.call_rounded, size: 24), onPressed: () {
                           if (widget.botData['stt_model'] == null || widget.botData['tts_model'] == null) {
                             TideDialogs.showCustomDialog(context: context, child: Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(36)), child: const Text("未能接通：需先在设置中配置 STT(语音转文字) 和 TTS(文字转语音) 模型方可拨打电话。", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, height: 1.5))));
                           }
                        }),
                        IconButton(icon: const Icon(Icons.cleaning_services_rounded, size: 24), onPressed: () {
                          TideDialogs.showCustomDialog(context: context, child: Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(36)), child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text("记忆与对话管理", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 24),
                            GestureDetector(onTap: () async { await DBManager().clearChatHistory(widget.botData['id']); Navigator.pop(context); _loadHistory(); }, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18), decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(20)), alignment: Alignment.center, child: const Text("删除表面聊天记录", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)))),
                            const SizedBox(height: 12),
                            GestureDetector(onTap: () async { await DBManager().clearMemories(widget.botData['id']); Navigator.pop(context); }, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), alignment: Alignment.center, child: const Text("删除底层潜意识记忆", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)))),
                          ])));
                        }),
                        IconButton(icon: const Icon(Icons.settings_rounded, size: 24), onPressed: () async {
                          final providers = await DBManager().getProvidersByType('chat');
                          if (!mounted) return;
                          Navigator.push(context, PageRouteBuilder(pageBuilder: (c,a,s) => ChatSettingsPage(botData: widget.botData, providers: providers), transitionsBuilder: (c,a,s,child) => SlideTransition(position: Tween<Offset>(begin: const Offset(0,1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child))).then((_) => _loadHistory());
                        }),
                        IconButton(icon: const Icon(Icons.menu_rounded, size: 24), onPressed: () {
                          TideDialogs.showBottomSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 88, height: 88, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black), alignment: Alignment.center, child: Text(widget.botData['name'].substring(0,1), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900))),
                            const SizedBox(height: 16), Text(widget.botData['name'], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)), const SizedBox(height: 32),
                            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black.withOpacity(0.04), borderRadius: BorderRadius.circular(24)), width: double.infinity, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("身世设定", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(widget.botData['desc'] ?? "无", style: const TextStyle(fontSize: 16, height: 1.4))])),
                            const SizedBox(height: 16),
                            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black.withOpacity(0.04), borderRadius: BorderRadius.circular(24)), width: double.infinity, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("说话方式", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(widget.botData['prompt'] ?? "无", style: const TextStyle(fontSize: 16, height: 1.4))])),
                          ]));
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              
              // 消息流
              Expanded(
                child: ListView.builder(
                  controller: _scrollC, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isUser = msg['role'] == 'user';
                    final dt = DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] ?? DateTime.now().millisecondsSinceEpoch);
                    final timeStr = "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
                    
                    // 单张图片独立显示，不带气泡
                    if (msg['type'] == 'image') {
                      return GestureDetector(
                        onLongPress: () => _showMsgMenu(msg),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(iconTheme: const IconThemeData(color: Colors.white), backgroundColor: Colors.black, actions: [IconButton(icon: const Icon(Icons.download_rounded), onPressed: (){ /* 保存图片预留 */ })]), body: Center(child: InteractiveViewer(child: Image.file(File(msg['file_path']))))))),
                        child: Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.file(File(msg['file_path']), width: 240, fit: BoxFit.cover)))),
                      );
                    }
                    // 专属语音卡片
                    if (msg['type'] == 'audio') {
                      return GestureDetector(
                        onLongPress: () => _showMsgMenu(msg),
                        onTap: () => OpsManager().playAudio(msg['file_path']),
                        child: Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), decoration: BoxDecoration(color: isUser ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [if(!isUser) BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0,8))]), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.graphic_eq_rounded, color: isUser ? Colors.white : Colors.black), const SizedBox(width:12), Text("语音记录", style: TextStyle(color: isUser ? Colors.white : Colors.black, fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(width: 16), Text(timeStr, style: TextStyle(color: isUser ? Colors.white54 : Colors.grey.shade400, fontSize: 12))]))),
                      );
                    }

                    // 文字消息
                    return GestureDetector(
                      onLongPress: () => _showMsgMenu(msg),
                      child: Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 12),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(color: isUser ? Colors.black : Colors.white, borderRadius: BorderRadius.only(topLeft: const Radius.circular(28), topRight: const Radius.circular(28), bottomLeft: Radius.circular(isUser ? 28 : 8), bottomRight: Radius.circular(isUser ? 8 : 28)), boxShadow: [if(!isUser) BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0,8))]),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _buildRichText(msg['content'] ?? '', isUser),
                              const SizedBox(height: 6),
                              Text(timeStr, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isUser ? Colors.white54 : Colors.grey.shade400)), // 时间尾巴紧贴右下角
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 底部输入框
              ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: Container(
                    padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 20),
                    color: barBgColor,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Padding(padding: const EdgeInsets.only(bottom: 4), child: IconButton(icon: const Icon(Icons.add_circle_rounded, size: 30), onPressed: () async {
                          final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                          if (img != null) {
                             if (_msgC.text.isNotEmpty) _send(text: _msgC.text, imagePath: img.path);
                             else _send(imagePath: img.path);
                          }
                        })),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 18), 
                            decoration: BoxDecoration(color: isCustomBg ? Colors.white.withOpacity(0.8) : Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.black.withOpacity(0.06))), 
                            child: TextField(controller: _msgC, maxLines: 5, minLines: 1, decoration: const InputDecoration(border: InputBorder.none, hintText: '发送新消息...', hintStyle: TextStyle(color: Colors.grey)))
                          )
                        ),
                        Padding(padding: const EdgeInsets.only(bottom: 4), child: GestureDetector(
                          onTap: () async {
                            HapticFeedback.heavyImpact();
                            if (!_isRecording) {
                              setState(() => _isRecording = true);
                              await OpsManager().startRecording();
                            } else {
                              setState(() => _isRecording = false);
                              final p = await OpsManager().stopRecording();
                              if (p != null) _send(audioPath: p);
                            }
                          },
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: _isRecording ? FadeTransition(opacity: _micAnim, child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))) : const Icon(Icons.mic_rounded, size: 30)),
                        )),
                        Padding(padding: const EdgeInsets.only(bottom: 10, right: 4), child: GestureDetector(onTap: () => _send(text: _msgC.text), child: Container(width: 38, height: 38, decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22)))),
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }
}

// 机器人独立设置页 (在弹窗中进行以符合 iOS 风，用 custom dialog)
class ChatSettingsPage extends StatefulWidget {
  final Map<String, dynamic> botData;
  final List<Map<String, dynamic>> providers;
  const ChatSettingsPage({Key? key, required this.botData, required this.providers}) : super(key: key);
  @override State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}
class _ChatSettingsPageState extends State<ChatSettingsPage> {
  late String _chatModel;
  late int _maxToken;
  
  @override void initState() { 
    super.initState(); 
    _chatModel = widget.botData['chat_model'] ?? (widget.providers.isNotEmpty ? widget.providers.first['id'] : '');
    _maxToken = widget.botData['max_tokens'] ?? 10000;
  }

  void _save() async {
    await DBManager().updateBot(widget.botData['id'], {'chat_model': _chatModel, 'max_tokens': _maxToken});
    Navigator.pop(context);
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(title: const Text("模型映射", style: TextStyle(fontWeight: FontWeight.w900)), actions: [TextButton(onPressed: _save, child: const Text("保存", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)))]),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text("引擎核心", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("默认聊天模型", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _chatModel.isEmpty ? null : _chatModel, underline: const SizedBox(),
                  items: widget.providers.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text("${p['name'].toString().split('/').first} - ${p['name'].toString().split('/').last}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)))).toList(),
                  onChanged: (v) => setState(() => _chatModel = v!),
                )
              ]),
              const Divider(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("最大上下文", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                DropdownButton<int>(
                  value: _maxToken, underline: const SizedBox(),
                  items: const [DropdownMenuItem(value: 10000, child: Text("10000", style: TextStyle(fontWeight: FontWeight.bold))), DropdownMenuItem(value: 20000, child: Text("20000", style: TextStyle(fontWeight: FontWeight.bold)))],
                  onChanged: (v) => setState(() => _maxToken = v!),
                )
              ])
            ]),
          )
        ],
      ),
    );
  }
}