import 'dart:ui';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'db.dart';
import 'ai.dart';
import 'ops.dart';

class TideDialogs {
  static Future<T?> showBottomSheet<T>({required BuildContext context, required Widget child}) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<T>(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), child: Container(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), color: Colors.white.withOpacity(0.95), child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(24), child: child)))),
      ),
    );
  }
  static Future<T?> showCustomDialog<T>({required BuildContext context, required Widget child}) {
    HapticFeedback.lightImpact();
    return showGeneralDialog<T>(context: context, barrierDismissible: true, barrierLabel: '', transitionDuration: const Duration(milliseconds: 250), pageBuilder: (c,a,s) => const SizedBox(), transitionBuilder: (c,a,s,_) => BackdropFilter(filter: ImageFilter.blur(sigmaX: 10*a.value, sigmaY: 10*a.value), child: ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: FadeTransition(opacity: a, child: Dialog(backgroundColor: Colors.transparent, elevation: 0, child: child)))));
  }
}

class Particle {
  double x, y, vx, vy, size; Color color; double life = 1.0;
  Particle(this.x, this.y, this.vx, this.vy, this.size, this.color);
  void update() { x += vx; y += vy; vy += 0.4; life -= 0.04; size *= 0.9; }
}
class ExplosionPainter extends CustomPainter {
  final List<Particle> p; ExplosionPainter(this.p);
  @override void paint(Canvas c, Size s) { final pt = Paint()..style = PaintingStyle.fill; for (var v in p) { if (v.life > 0) { pt.color = v.color.withOpacity(v.life.clamp(0.0, 1.0)); c.drawCircle(Offset(v.x, v.y), v.size, pt); } } }
  @override bool shouldRepaint(covariant ExplosionPainter o) => true;
}

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

  void _triggerExplosion(String botId) {
    _expParts[botId] = List.generate(20, (_) => Particle(150 + _rnd.nextDouble()*40-20, 40 + _rnd.nextDouble()*20-10, _rnd.nextDouble()*10-5, _rnd.nextDouble()*10-8, _rnd.nextDouble()*4+2, Colors.grey));
    _expCtrls[botId] = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..addListener(() { setState((){ for(var p in _expParts[botId]!) p.update(); }); })..addStatusListener((s) async { if (s == AnimationStatus.completed) { await DBManager().deleteBot(botId); _loadData(); } });
    _expCtrls[botId]!.forward();
  }

  void _showCreateModal() {
    final nameC = TextEditingController(), descC = TextEditingController(), promptC = TextEditingController();
    TideDialogs.showBottomSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("创造新生命", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)), const SizedBox(height: 20),
      TextField(controller: nameC, decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), hintText: "名字")), const SizedBox(height: 12),
      TextField(controller: descC, maxLines: 2, decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), hintText: "人格设定")), const SizedBox(height: 12),
      TextField(controller: promptC, maxLines: 2, decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), hintText: "说话方式")), const SizedBox(height: 24),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), onPressed: () async { if (nameC.text.isEmpty) return; await DBManager().insertBot({'id': 'bot_${DateTime.now().millisecondsSinceEpoch}', 'name': nameC.text, 'desc': descC.text, 'prompt': promptC.text, 'created_at': DateTime.now().millisecondsSinceEpoch}); Navigator.pop(context); _loadData(); }, child: const Text("生成", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))
    ]));
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(left: 24, top: 20, bottom: 10), child: Text('TideBot', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1))),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), itemCount: _bots.length,
            itemBuilder: (context, index) {
              final bot = _bots[index];
              final dt = DateTime.fromMillisecondsSinceEpoch(bot['created_at']);
              final timeStr = "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
              final isExp = _expCtrls.containsKey(bot['id']) && _expCtrls[bot['id']]!.isAnimating;
              
              if (isExp) return CustomPaint(painter: ExplosionPainter(_expParts[bot['id']]!), child: const SizedBox(height: 96, width: double.infinity));

              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatRoomPage(botData: bot))).then((_) => _loadData()),
                onLongPress: () => TideDialogs.showBottomSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(leading: const Icon(Icons.push_pin_outlined), title: const Text("置顶该生命体", style: TextStyle(fontWeight: FontWeight.bold)), onTap: () => Navigator.pop(context)),
                  ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text("彻底删除", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), onTap: () {
                    Navigator.pop(context);
                    TideDialogs.showCustomDialog(context: context, child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)), child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text("确认删除？", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const Text("此操作不可逆。", style: TextStyle(color: Colors.grey)), const SizedBox(height: 24),
                      Row(children: [Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消", style: TextStyle(color: Colors.black)))), Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(context); _triggerExplosion(bot['id']); }, child: const Text("删除", style: TextStyle(color: Colors.white))))])
                    ])));
                  })
                ])),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))]),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade100), alignment: Alignment.center, child: Text(bot['name'].substring(0,1), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(bot['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(bot['desc'] ?? "暂无设定", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: Colors.grey.shade500))])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(timeStr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade400)), const SizedBox(height: 12), Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade300)])
                  ]),
                ),
              );
            },
          )),
        ]),
      ),
      floatingActionButton: Padding(padding: const EdgeInsets.only(bottom: 90), child: FloatingActionButton(onPressed: _showCreateModal, backgroundColor: Colors.black, elevation: 10, child: const Icon(Icons.add, color: Colors.white, size: 28))),
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
    _micAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
    _loadHistory(); _loadBg(); 
  }
  @override void dispose() { _micAnim.dispose(); super.dispose(); }

  void _loadHistory() async { final res = await DBManager().getChatHistory(widget.botData['id']); setState(() => _messages = res); _scrollToBottom(); }
  void _loadBg() async { final path = await DBManager().getKV('chat_bg_${widget.botData['id']}'); if (path != null) setState(() => _bgPath = path); }

  void _scrollToBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollC.hasClients) _scrollC.jumpTo(_scrollC.position.maxScrollExtent); }); }

  // 完美实现图片和文字的分离发送
  void _send({String? text, String? imagePath, String? audioPath}) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    
    // 如果有图先插图
    if (imagePath != null) {
      final imgMsg = {'id': 'msg_u_img_$ts', 'bot_id': widget.botData['id'], 'role': 'user', 'type': 'image', 'file_path': imagePath, 'timestamp': ts};
      await DBManager().insertChatMessage(imgMsg);
      setState(() => _messages.add(imgMsg));
    }
    // 再插文字/音频
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
    
    final res = await AIManager().sendMessage(botId: widget.botData['id'], text: text ?? "[语音/图片]", imagePath: imagePath);
    setState(() => _isTyping = false);
    if (res['success'] == true) _loadHistory();
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? '请求失败')));
  }

  void _showMsgMenu(Map<String, dynamic> msg) {
    TideDialogs.showBottomSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.copy), title: const Text("复制"), onTap: () { Clipboard.setData(ClipboardData(text: msg['content'])); Navigator.pop(context); }),
      ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("删除", style: TextStyle(color: Colors.red)), onTap: () async { await DBManager().deleteMessage(msg['id']); Navigator.pop(context); _loadHistory(); }),
    ]));
  }

  void _openSettings() async {
    final providers = await DBManager().getProvidersByType('chat');
    // 强制使用真实页面更新
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatSettingsPage(botData: widget.botData, providers: providers))).then((_) => _loadHistory());
  }

  @override Widget build(BuildContext context) {
    final topBarColor = _bgPath != null ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.85);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Stack(
        children: [
          if (_bgPath != null) Positioned.fill(child: Image.file(File(_bgPath!), fit: BoxFit.cover)),
          Column(
            children: [
              // 顶部栏: 无阴影, iOS 风毛玻璃
              ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, bottom: 8, left: 4, right: 4),
                    color: topBarColor,
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 22), onPressed: () => Navigator.pop(context)),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.botData['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                          if (_isTyping) const Text("正在输入中...", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))
                        ])),
                        IconButton(icon: const Icon(Icons.call_outlined, size: 24), onPressed: () {
                           if (widget.botData['stt_model'] == null || widget.botData['tts_model'] == null) {
                             TideDialogs.showCustomDialog(context: context, child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: const Text("请先配置 STT 和 TTS 模型", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))));
                           }
                        }),
                        IconButton(icon: const Icon(Icons.delete_sweep_outlined, size: 24), onPressed: () {
                          TideDialogs.showCustomDialog(context: context, child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)), child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text("抹除记忆", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 16),
                            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () async { await DBManager().clearChatHistory(widget.botData['id']); Navigator.pop(context); _loadHistory(); }, child: const Text("清空表面聊天记录", style: TextStyle(color: Colors.white))),
                            const SizedBox(height: 12),
                            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900), onPressed: () async { await DBManager().clearMemories(widget.botData['id']); Navigator.pop(context); }, child: const Text("抹除潜意识长期记忆", style: TextStyle(color: Colors.white))),
                          ])));
                        }),
                        IconButton(icon: const Icon(Icons.settings_outlined, size: 24), onPressed: _openSettings),
                        IconButton(icon: const Icon(Icons.menu_open, size: 24), onPressed: () {
                          TideDialogs.showBottomSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade200), alignment: Alignment.center, child: Text(widget.botData['name'].substring(0,1), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold))),
                            const SizedBox(height: 16), Text(widget.botData['name'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)), const SizedBox(height: 24),
                            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)), width: double.infinity, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("身世设定", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(widget.botData['desc'] ?? "无", style: const TextStyle(fontSize: 15))])),
                            const SizedBox(height: 12),
                            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)), width: double.infinity, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("说话方式", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(widget.botData['prompt'] ?? "无", style: const TextStyle(fontSize: 15))])),
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
                  controller: _scrollC, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isUser = msg['role'] == 'user';
                    
                    if (msg['type'] == 'image') {
                      return GestureDetector(
                        onLongPress: () => _showMsgMenu(msg),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(iconTheme: const IconThemeData(color: Colors.white), backgroundColor: Colors.black, actions: [IconButton(icon: const Icon(Icons.download), onPressed: (){})]), body: Center(child: Image.file(File(msg['file_path'])))))),
                        child: Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(File(msg['file_path']), width: 220, fit: BoxFit.cover)))),
                      );
                    }
                    if (msg['type'] == 'audio') {
                      return GestureDetector(
                        onLongPress: () => _showMsgMenu(msg),
                        onTap: () => OpsManager().playAudio(msg['file_path']),
                        child: Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), decoration: BoxDecoration(color: isUser ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(24)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.multitrack_audio, color: isUser ? Colors.white : Colors.black), const SizedBox(width:8), Text("语音消息", style: TextStyle(color: isUser ? Colors.white : Colors.black, fontWeight: FontWeight.bold))]))),
                      );
                    }

                    return GestureDetector(
                      onLongPress: () => _showMsgMenu(msg),
                      child: Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(color: isUser ? Colors.black : Colors.white, borderRadius: BorderRadius.only(topLeft: const Radius.circular(24), topRight: const Radius.circular(24), bottomLeft: Radius.circular(isUser ? 24 : 4), bottomRight: Radius.circular(isUser ? 4 : 24)), boxShadow: [if(!isUser) BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0,4))]),
                          child: Text(msg['content'] ?? '', style: TextStyle(fontSize: 16, color: isUser ? Colors.white : Colors.black87, height: 1.5)),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 底部输入框 (带麦克风闪烁)
              ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 20),
                    color: topBarColor,
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.add_circle_outline, size: 28), onPressed: () async {
                          final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                          if (img != null) {
                             if (_msgC.text.isNotEmpty) _send(text: _msgC.text, imagePath: img.path);
                             else _send(imagePath: img.path);
                          }
                        }),
                        Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.black.withOpacity(0.08))), child: TextField(controller: _msgC, maxLines: 5, minLines: 1, decoration: const InputDecoration(border: InputBorder.none, hintText: '发送新消息...', hintStyle: TextStyle(color: Colors.grey))))),
                        GestureDetector(
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
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _isRecording ? FadeTransition(opacity: _micAnim, child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))) : const Icon(Icons.mic_none, size: 28)),
                        ),
                        GestureDetector(onTap: () => _send(text: _msgC.text), child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20))),
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

// 机器人独立设置页 (真实可改)
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
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(title: const Text("配置属性", style: TextStyle(fontWeight: FontWeight.w800)), actions: [TextButton(onPressed: _save, child: const Text("保存", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("引擎模型", style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("默认聊天模型", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _chatModel.isEmpty ? null : _chatModel, underline: const SizedBox(),
                  items: widget.providers.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text("${p['name'].toString().split('/').first} - ${p['name'].toString().split('/').last}", style: const TextStyle(fontSize: 14)))).toList(),
                  onChanged: (v) => setState(() => _chatModel = v!),
                )
              ]),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("最大上下文", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                DropdownButton<int>(
                  value: _maxToken, underline: const SizedBox(),
                  items: const [DropdownMenuItem(value: 10000, child: Text("10000")), DropdownMenuItem(value: 20000, child: Text("20000"))],
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