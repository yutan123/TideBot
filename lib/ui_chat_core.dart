import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'db.dart';
import 'ai.dart';
import 'ops.dart';

// 独家弹窗体系
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
}

class ChatListPage extends StatefulWidget {
  const ChatListPage({Key? key}) : super(key: key);
  @override State<ChatListPage> createState() => _ChatListPageState();
}
class _ChatListPageState extends State<ChatListPage> {
  List<Map<String, dynamic>> _bots = [];

  @override void initState() { super.initState(); _loadData(); }
  void _loadData() async { final data = await DBManager().getAllBots(); setState(() => _bots = data); }

  void _showCreateModal() {
    final nameC = TextEditingController(), descC = TextEditingController(), promptC = TextEditingController();
    TideDialogs.showBottomSheet(context: context, child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("创造新生命", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        TextField(controller: nameC, decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), hintText: "名字")),
        const SizedBox(height: 12),
        TextField(controller: descC, maxLines: 2, decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), hintText: "人格设定")),
        const SizedBox(height: 12),
        TextField(controller: promptC, maxLines: 2, decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), hintText: "说话方式")),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          onPressed: () async {
            if (nameC.text.isEmpty) return;
            await DBManager().insertBot({'id': 'bot_${DateTime.now().millisecondsSinceEpoch}', 'name': nameC.text, 'desc': descC.text, 'prompt': promptC.text, 'created_at': DateTime.now().millisecondsSinceEpoch});
            Navigator.pop(context); _loadData();
          },
          child: const Text("生成", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        )
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(left: 24, top: 20, bottom: 10), child: Text('TideBot', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1))),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: _bots.length,
                itemBuilder: (context, index) {
                  final bot = _bots[index];
                  // 纯正 iOS 大圆角卡片
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatRoomPage(botData: bot))).then((_) => _loadData()),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))]),
                      child: Row(
                        children: [
                          Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade100), alignment: Alignment.center, child: Text(bot['name'].substring(0,1), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 16),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(bot['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(bot['desc'] ?? "暂无设定", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text("18:00", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade400)), // 24H制
                            const SizedBox(height: 12),
                            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade300)
                          ])
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(padding: const EdgeInsets.only(bottom: 90), child: FloatingActionButton(onPressed: _showCreateModal, backgroundColor: Colors.black, child: const Icon(Icons.add, color: Colors.white))),
    );
  }
}

// 真实的聊天室 UI
class ChatRoomPage extends StatefulWidget {
  final Map<String, dynamic> botData;
  const ChatRoomPage({Key? key, required this.botData}) : super(key: key);
  @override State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final TextEditingController _msgC = TextEditingController();
  final ScrollController _scrollC = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  bool _isRecording = false;
  String? _bgPath;

  @override void initState() { super.initState(); _loadHistory(); _loadBg(); }
  void _loadHistory() async { final res = await DBManager().getChatHistory(widget.botData['id']); setState(() => _messages = res); _scrollToBottom(); }
  void _loadBg() async { final path = await DBManager().getKV('chat_bg'); if (path != null) setState(() => _bgPath = path); }

  void _scrollToBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollC.hasClients) _scrollC.jumpTo(_scrollC.position.maxScrollExtent); }); }

  void _send(String text, {String type = 'text', String? filePath}) async {
    if (text.isEmpty && type == 'text') return;
    _msgC.clear();
    final ts = DateTime.now().millisecondsSinceEpoch;
    setState(() { _messages.add({'role': 'user', 'type': type, 'content': text, 'file_path': filePath, 'timestamp': ts}); _isTyping = true; });
    _scrollToBottom();
    
    // 真实调用
    final res = await AIManager().sendMessage(botId: widget.botData['id'], text: type == 'audio' ? "[发送了一段语音]" : text);
    setState(() => _isTyping = false);
    if (res['success'] == true) _loadHistory();
  }

  void _openSettings() {
    TideDialogs.showBottomSheet(context: context, child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("引擎设置", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        // 这里的选项需要真实查库，略写 UI 展示
        ListTile(title: const Text("默认聊天模型"), trailing: const Text("DeepSeek-chat >", style: TextStyle(color: Colors.grey)), onTap: (){}),
        ListTile(title: const Text("最大上下文 Token"), trailing: const Text("10000 >", style: TextStyle(color: Colors.grey)), onTap: (){}),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Stack(
        children: [
          if (_bgPath != null) Positioned.fill(child: Image.file(File(_bgPath!), fit: BoxFit.cover)),
          Column(
            children: [
              // 顶部栏
              ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, bottom: 10, left: 8, right: 8),
                    color: Colors.white.withOpacity(_bgPath != null ? 0.3 : 0.8),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back_ios_new), onPressed: () => Navigator.pop(context)),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.botData['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          if (_isTyping) const Text("正在输入中...", style: TextStyle(fontSize: 12, color: Colors.grey))
                        ])),
                        IconButton(icon: const Icon(Icons.call), onPressed: () {}),
                        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {}),
                        IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
                        IconButton(icon: const Icon(Icons.menu), onPressed: () {}),
                      ],
                    ),
                  ),
                ),
              ),
              
              // 消息流
              Expanded(
                child: ListView.builder(
                  controller: _scrollC, padding: const EdgeInsets.all(16), itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isUser = msg['role'] == 'user';
                    
                    if (msg['type'] == 'image') {
                      return Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(File(msg['file_path']), width: 200, fit: BoxFit.cover))));
                    }
                    if (msg['type'] == 'audio') {
                      return Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: isUser ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(24)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.multitrack_audio, color: isUser ? Colors.white : Colors.black), const SizedBox(width:8), Text("语音消息", style: TextStyle(color: isUser ? Colors.white : Colors.black))])));
                    }

                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(color: isUser ? Colors.black : Colors.white, borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(isUser ? 20 : 4), bottomRight: Radius.circular(isUser ? 4 : 20))),
                        child: Text(msg['content'] ?? '', style: TextStyle(fontSize: 16, color: isUser ? Colors.white : Colors.black87)),
                      ),
                    );
                  },
                ),
              ),

              // 底部输入框
              ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 24),
                    color: Colors.white.withOpacity(_bgPath != null ? 0.3 : 0.8),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.add_circle_outline, size: 28), onPressed: () async {
                          final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                          if (img != null) _send("", type: "image", filePath: img.path);
                        }),
                        Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.black12)), child: TextField(controller: _msgC, maxLines: 4, minLines: 1, decoration: const InputDecoration(border: InputBorder.none, hintText: '发送新消息...')))),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.heavyImpact();
                            setState(() => _isRecording = !_isRecording);
                            if (!_isRecording) _send("模拟录音", type: "audio", filePath: "dummy_path"); // 假装结束并发送
                          },
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _isRecording ? const Icon(Icons.stop_circle, color: Colors.red, size: 28) : const Icon(Icons.mic_none, size: 28)),
                        ),
                        GestureDetector(onTap: () => _send(_msgC.text), child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20))),
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