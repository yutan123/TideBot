import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:path_provider/path_provider.dart';
import 'db.dart';
import 'ai.dart';
import 'ui_components.dart';
import 'ui_create_bot.dart';
import 'theme.dart';

class ChatRoomPage extends StatefulWidget {
  final Map<String, dynamic> botData;
  const ChatRoomPage({Key? key, required this.botData}) : super(key: key);
  @override State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> with SingleTickerProviderStateMixin {
  final TextEditingController _msgC = TextEditingController();
  final ScrollController _scrollC = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  bool _isRecording = false;
  bool _loading = false;
  bool _typing = false;
  bool _msgsLoading = true;
  final Record _rec = Record();
  final AudioPlayer _player = AudioPlayer();
  Timer? _recTimer;
  int _recSecs = 0;
  String? _customBg;
  late Map<String, dynamic> _bot;

  bool _hasText = false;
  void _msgChanged() { if (mounted) setState(() => _hasText = _msgC.text.isNotEmpty); }

  @override void initState() {
    super.initState();
    _bot = Map.from(widget.botData);
    _msgC.addListener(_msgChanged);
    _loadMsgs(); _loadBg();
  }
  @override void dispose() { _msgC.removeListener(_msgChanged); _msgC.dispose(); _scrollC.dispose(); _rec.dispose(); _player.dispose(); _recTimer?.cancel(); super.dispose(); }

  void _loadBg() async {
    final prefs = await SharedPreferences.getInstance();
    final bg = prefs.getString('chat_bg_${_bot['id']}');
    if (mounted) setState(() => _customBg = bg);
  }

  void _loadMsgs() async {
    try {
      final msgs = await DBManager().queryMessages(_bot['id'] as String, limit: 100);
      if (mounted) setState(() { _msgs = msgs.reversed.toList(); _msgsLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _msgsLoading = false);
    }
    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 80), () { if (_scrollC.hasClients) _scrollC.animateTo(_scrollC.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic); });
  }

  bool get _hasBg => _customBg != null && _customBg!.isNotEmpty;

  // ========== 发送消息 ==========
  void _send({String? img}) async {
    final text = _msgC.text.trim();
    if (text.isEmpty && img == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final msg = <String, dynamic>{'id': 'm_$now', 'bot_id': _bot['id'], 'role': 'user', 'content': text, 'image': img, 'timestamp': now};
    await DBManager().insertMessage(msg);
    setState(() { _msgs.add(msg); _msgC.clear(); });
    _scrollDown();

    setState(() { _loading = true; _typing = true; });
    try {
      final providers = await DBManager().queryProviders();
      final prefs = await SharedPreferences.getInstance();
      final cm = prefs.getString('chat_model_${_bot['id']}') ?? (providers.isNotEmpty ? providers.first['id'] : '');
      final history = _msgs.where((m) => (m['content'] as String?)?.isNotEmpty == true).map((m) => {'role': m['role'], 'content': m['content']}).toList();
      var imgB64 = '';
      if (img != null) imgB64 = base64Encode(await File(img).readAsBytes());
      final resp = await AIManager().chat(messages: history, providerId: cm, botPrompt: _bot['prompt'] as String? ?? '', imageBase64: imgB64);
      final bm = <String, dynamic>{'id': 'm_${DateTime.now().millisecondsSinceEpoch}', 'bot_id': _bot['id'], 'role': 'assistant', 'content': resp, 'timestamp': DateTime.now().millisecondsSinceEpoch};
      await DBManager().insertMessage(bm);
      setState(() => _msgs.add(bm));
    } catch (e) {
      final err = <String, dynamic>{'id': 'm_err_${DateTime.now().millisecondsSinceEpoch}', 'bot_id': _bot['id'], 'role': 'assistant', 'content': '[X] 连接失败: $e', 'timestamp': DateTime.now().millisecondsSinceEpoch};
      setState(() => _msgs.add(err));
    }
    setState(() { _loading = false; _typing = false; });
    _scrollDown();
  }

  // ========== 录音 ==========
  Future<void> _toggleRec() async {
    if (_isRecording) {
      _recTimer?.cancel();
      final path = await _rec.stop();
      setState(() { _isRecording = false; _recSecs = 0; });
      if (path != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final m = <String, dynamic>{'id': 'm_$now', 'bot_id': _bot['id'], 'role': 'user', 'content': '', 'audio': path, 'timestamp': now};
        await DBManager().insertMessage(m);
        setState(() => _msgs.add(m));
        _scrollDown();
      }
    } else {
      if (await _rec.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final p = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _rec.start(path: p, encoder: AudioEncoder.aacLc, bitRate: 128000);
        setState(() => _isRecording = true);
        _recTimer = Timer.periodic(const Duration(seconds: 1), (t) { if (mounted) setState(() => _recSecs++); });
      }
    }
  }

  // ========== 选择图片/文件 ==========
  void _pickMedia() async {
    final r = await showTideSheet<String>(context: context, height: 180, child: Column(children: [
      const SizedBox(height: 10),
      ListTile(leading: Icon(Icons.photo_library_rounded, color: TideTheme.of(context).primary), title: const Text('相册', style: TextStyle(fontFamily: 'TideFont')), onTap: () => Navigator.pop(context, 'img')),
      ListTile(leading: Icon(Icons.insert_drive_file_rounded, color: TideTheme.of(context).primary), title: const Text('文件', style: TextStyle(fontFamily: 'TideFont')), onTap: () => Navigator.pop(context, 'file')),
    ]));
    if (r == 'img') {
      final p = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (p != null) _send(img: await _fixHeic(p.path));
    } else if (r == 'file') {
      final fp = await FilePicker.platform.pickFiles();
      if (fp != null && fp.files.single.path != null) _send(img: fp.files.single.path);
    }
  }

  Future<String> _fixHeic(String path) async {
    final l = path.toLowerCase();
    if (l.endsWith('.heic') || l.endsWith('.heif')) {
      try {
        final converted = await HeifConverter.convert(path);
        if (converted != null) return converted;
      } catch (_) {}
    }
    return path;
  }

  // ========== 图片预览 ==========
  void _previewImg(String path) {
    Navigator.push(context, PageRouteBuilder(pageBuilder: (c, a, s) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white))), body: Center(child: InteractiveViewer(child: Image.file(File(path), fit: BoxFit.contain)))), transitionsBuilder: (c, a, s, child) => FadeTransition(opacity: a, child: child)));
  }

  // ========== 机器人信息弹窗 ==========
  void _showBotInfo() {
    final n = TextEditingController(text: _bot['name']);
    final d = TextEditingController(text: _bot['desc']);
    final p = TextEditingController(text: _bot['prompt']);
    TideDialogs.show(context: context, builder: (ctx) => AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero, content: TideDialogs.glassContent(context: ctx, children: [
      const Center(child: Text('机器人信息', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'TideFont'))),
      const SizedBox(height: 14),
      _mLabel('名字'), _mField(n),
      const SizedBox(height: 10), _mLabel('人格设定'), _mField(d, h: 80),
      const SizedBox(height: 10), _mLabel('说话方式'), _mField(p, h: 100),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: TideDialogs.glassButton('保存', onTap: () async {
        _bot['name'] = n.text; _bot['desc'] = d.text; _bot['prompt'] = p.text;
        await DBManager().updateBot(_bot['id'] as String, {
          'name': n.text, 'desc': d.text, 'prompt': p.text,
        });
        Navigator.pop(ctx); setState(() {});
      })),
    ])));
  }

  // ========== 模型设置弹窗 ==========
  void _showModelSettings() async {
    final providers = await DBManager().queryProviders();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final curChat = prefs.getString('chat_model_${_bot['id']}') ?? (providers.isNotEmpty ? providers.first['id'] : '');
    final curBak = prefs.getString('backup_model_${_bot['id']}') ?? '';
    final curVision = prefs.getString('vision_model_${_bot['id']}') ?? '';
    final curStt = prefs.getString('stt_model_${_bot['id']}') ?? '';
    final curTts = prefs.getString('tts_model_${_bot['id']}') ?? '';
    final curTok = prefs.getInt('max_token_${_bot['id']}') ?? 10000;

    TideDialogs.show(context: context, builder: (ctx) => AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero, content: TideDialogs.glassContent(context: ctx, maxWidth: 0.9, children: [
      const Center(child: Text('模型设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'TideFont'))),
      const SizedBox(height: 14),
      _mLabel('聊天模型'), _modelPicker(ctx, providers, curChat, (v) async { await prefs.setString('chat_model_${_bot['id']}', v); }),
      _mLabel('备用模型'), _modelPicker(ctx, providers, curBak, (v) async { await prefs.setString('backup_model_${_bot['id']}', v); }),
      _mLabel('识图模型'), _modelPicker(ctx, providers, curVision, (v) async { await prefs.setString('vision_model_${_bot['id']}', v); }),
      _mLabel('STT模型'), _modelPicker(ctx, providers, curStt, (v) async { await prefs.setString('stt_model_${_bot['id']}', v); }),
      _mLabel('TTS模型'), _modelPicker(ctx, providers, curTts, (v) async { await prefs.setString('tts_model_${_bot['id']}', v); }),
      _mLabel('最大上下文Token'),
      GestureDetector(onTap: () => _pickToken(ctx, curTok), child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: const Color(0xFFE8E8F0), borderRadius: BorderRadius.circular(10)), child: Align(alignment: Alignment.centerLeft, child: Text('$curTok token', style: const TextStyle(fontSize: 14, fontFamily: 'TideFont'))))),
      const SizedBox(height: 14),
      TideDialogs.glassButton('确定', onTap: () => Navigator.pop(ctx)),
    ])));
  }

  void _pickToken(BuildContext parentCtx, int cur) {
    final c = TextEditingController();
    TideDialogs.show(context: parentCtx, builder: (ctx) => AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero, content: TideDialogs.glassContent(context: ctx, children: [
      const Text('最大上下文', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
      const SizedBox(height: 12),
      ListTile(title: const Text('10,000 token', style: TextStyle(fontFamily: 'TideFont')), onTap: () async { await SharedPreferences.getInstance().then((p) => p.setInt('max_token_${_bot['id']}', 10000)); Navigator.pop(ctx); }),
      ListTile(title: const Text('20,000 token', style: TextStyle(fontFamily: 'TideFont')), onTap: () async { await SharedPreferences.getInstance().then((p) => p.setInt('max_token_${_bot['id']}', 20000)); Navigator.pop(ctx); }),
      ListTile(title: const Text('自定义', style: TextStyle(fontFamily: 'TideFont')), onTap: () {
        Navigator.pop(ctx);
        TideDialogs.show(context: parentCtx, builder: (c2) => AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero, content: TideDialogs.glassContent(context: c2, children: [
          const Text('自定义Token', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
          const SizedBox(height: 10),
          TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: '输入token数量', hintStyle: const TextStyle(fontFamily: 'TideFont'), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))))),
          const SizedBox(height: 12),
          TideDialogs.glassButton('确定', onTap: () async { final v = int.tryParse(c.text); if (v != null && v > 0) { await SharedPreferences.getInstance().then((p) => p.setInt('max_token_${_bot['id']}', v)); } Navigator.pop(c2); }),
        ])));
      }),
    ])));
  }

  Widget _modelPicker(BuildContext ctx, List<Map<String, dynamic>> providers, String cur, Function(String) onPick) {
    final disp = providers.isNotEmpty
        ? (providers.firstWhereOrNull((p) => p['id'] == cur)?['name'] ?? '未选择')
        : '无可用模型';
    return GestureDetector(
      onTap: () {
        showTideSheet(context: ctx, height: 350, child: ListView(children: [
          for (var pv in providers)
            ListTile(title: Text(pv['name'] as String? ?? '', style: const TextStyle(fontFamily: 'TideFont')), subtitle: Text(pv['model'] as String? ?? '', style: const TextStyle(fontSize: 12, fontFamily: 'TideFont')), trailing: cur == pv['id'] ? Icon(Icons.check, color: TideTheme.of(ctx).primary) : null, onTap: () { onPick(pv['id'] as String); Navigator.pop(ctx); }),
        ]));
      },
      child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: const Color(0xFFE8E8F0), borderRadius: BorderRadius.circular(10)), child: Align(alignment: Alignment.centerLeft, child: Text(disp, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontFamily: 'TideFont')))));
  }

  // ========== 删除选项 ==========
  void _showDeleteOptions() {
    bool delMsgs = false;
    bool delMem = false;
    TideDialogs.show(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero, content: TideDialogs.glassContent(context: ctx, children: [
      const Text('清理数据', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
      const SizedBox(height: 14),
      CheckboxListTile(value: delMsgs, onChanged: (v) => setSt(() => delMsgs = v ?? false), title: const Text('删除聊天记录', style: TextStyle(fontFamily: 'TideFont')), controlAffinity: ListTileControlAffinity.leading),
      CheckboxListTile(value: delMem, onChanged: (v) => setSt(() => delMem = v ?? false), title: const Text('删除底层记忆', style: TextStyle(fontFamily: 'TideFont')), controlAffinity: ListTileControlAffinity.leading),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TideDialogs.glassButton('取消', onTap: () => Navigator.pop(ctx), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E))),
        const SizedBox(width: 10),
        Expanded(child: TideDialogs.glassButton('确认清除', onTap: () async {
          if (delMsgs) await DBManager().deleteMessages(_bot['id'] as String);
          if (delMem) await DBManager().deleteMemories(_bot['id'] as String);
          Navigator.pop(ctx); _loadMsgs();
        }, color: const Color(0xFFE74C3C))),
      ]),
    ]))));
  }

  // ========== 长按消息 ==========
  void _msgLongPress(Map<String, dynamic> msg) {
    showTideSheet(context: context, height: 220, child: Column(children: [
      const SizedBox(height: 8),
      ListTile(leading: Icon(Icons.copy_rounded, color: TideTheme.of(context).primary), title: const Text('复制', style: TextStyle(fontFamily: 'TideFont')), onTap: () { /* copy */ Navigator.pop(context); }),
      ListTile(leading: Icon(Icons.edit_rounded, color: TideTheme.of(context).primary), title: const Text('编辑', style: TextStyle(fontFamily: 'TideFont')), onTap: () => Navigator.pop(context)),
      ListTile(leading: Icon(Icons.format_quote_rounded, color: TideTheme.of(context).primary), title: const Text('引用', style: TextStyle(fontFamily: 'TideFont')), onTap: () => Navigator.pop(context)),
      ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE74C3C)), title: const Text('删除', style: TextStyle(fontFamily: 'TideFont', color: Color(0xFFE74C3C))), onTap: () async { await DBManager().deleteMessage(msg['id'] as String); Navigator.pop(context); _loadMsgs(); }),
    ]));
  }

  // ========== 构建UI ==========
  @override Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        // 自定义背景
        if (_hasBg) Positioned.fill(child: Image.file(File(_customBg!), fit: BoxFit.cover)),
        Column(children: [_chatHeader(), Expanded(child: _chatBody()), _inputBar()]),
      ]),
    );
  }
Widget _chatHeader() {
    return ClipRRect(
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: _hasBg ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.5),
          child: SafeArea(bottom: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context), child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.arrow_back_ios_rounded, size: 20, color: Color(0xFF1C1C1E)))),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_bot['name'] as String? ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
                if (_typing) Text('正在输入中...', style: TextStyle(fontSize: 11, color: TideTheme.of(context).primary, fontFamily: 'TideFont')),
              ])),
              // 电话按钮
              IconButton(icon: Icon(Icons.call_rounded, size: 20, color: TideTheme.of(context).primary), onPressed: () {
                // TODO: 先检查 TTS/STT 配置
              }),
              // 删除按钮
              IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFF8E8E93)), onPressed: _showDeleteOptions),
              // 设置按钮
              IconButton(icon: const Icon(Icons.settings_rounded, size: 20, color: Color(0xFF8E8E93)), onPressed: _showModelSettings),
              // 信息按钮
              IconButton(icon: const Icon(Icons.menu_rounded, size: 20, color: Color(0xFF8E8E93)), onPressed: _showBotInfo),
            ]),
          ),
        ),
      )),
    );
  }

  Widget _chatBody() {
    if (_msgsLoading) return Center(child: CircularProgressIndicator(color: TideTheme.of(context).primary));
    return ListView.builder(
      controller: _scrollC, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _msgs.length,
      itemBuilder: (ctx, i) {
        final m = _msgs[i];
        final isUser = m['role'] == 'user';
        final hasImg = (m['image'] as String?)?.isNotEmpty == true;
        final hasAudio = (m['audio'] as String?)?.isNotEmpty == true;
        final txt = (m['content'] as String?) ?? '';
        final ts = m['timestamp'] as int? ?? 0;

        return GestureDetector(
          onLongPress: () => _msgLongPress(m),
          child: Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(
            margin: const EdgeInsets.only(bottom: 8), constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            child: Column(crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
              // 图片
              if (hasImg) GestureDetector(onTap: () => _previewImg(m['image']), child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(margin: const EdgeInsets.only(bottom: 4), child: Image.file(File(m['image']), fit: BoxFit.cover, width: 180)))),
              // 音频卡片
              if (hasAudio) GestureDetector(onTap: () => _player.play(DeviceFileSource(m['audio'])), child: Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: isUser ? TideTheme.of(context).primary : const Color(0xFFE8E8F0), borderRadius: BorderRadius.circular(16)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(isUser ? Icons.mic : Icons.volume_up, size: 18, color: isUser ? Colors.white : TideTheme.of(context).primary), const SizedBox(width: 8), Text(isUser ? '语音消息' : '点击播放', style: TextStyle(color: isUser ? Colors.white : const Color(0xFF1C1C1E), fontSize: 13, fontFamily: 'TideFont'))]))),
              // 文字气泡
              if (txt.isNotEmpty) _parseText(txt, isUser),
              // 时间尾巴
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(fmtTime(ts), style: const TextStyle(fontSize: 10, color: Color(0xFFC7C7CC), fontFamily: 'TideFont'))),
            ]),
          )),
        );
      },
    );
  }

  // 富文本解析：旁白括号灰化
  Widget _parseText(String text, bool isUser) {
    final spans = <TextSpan>[];
    final reg = RegExp(r'\(.*?\)');
    int last = 0;
    for (var m in reg.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: TextStyle(color: isUser ? Colors.white : const Color(0xFF1C1C1E), fontSize: 14, fontFamily: 'TideFont')));
      }
      spans.add(TextSpan(text: text.substring(m.start, m.end), style: TextStyle(color: isUser ? Colors.white.withOpacity(0.6) : const Color(0xFF8E8E93), fontSize: 12, fontFamily: 'TideFont', fontStyle: FontStyle.italic)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: TextStyle(color: isUser ? Colors.white : const Color(0xFF1C1C1E), fontSize: 14, fontFamily: 'TideFont')));
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isUser ? TideTheme.of(context).primary : Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(16)), child: RichText(text: TextSpan(children: spans)));
  }

  Widget _inputBar() {
    return SafeArea(top: false, child: Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: _hasBg ? BoxDecoration(color: Colors.white.withOpacity(0.1)) : null,
      child: ClipRRect(
        child: BackdropFilter(filter: _hasBg ? ImageFilter.blur(sigmaX: 20, sigmaY: 20) : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: _hasBg ? Colors.white.withOpacity(0.6) : Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(22)), child: Row(children: [
            GestureDetector(onTap: _pickMedia, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.add_rounded, size: 24, color: Color(0xFF8E8E93)))),
            Expanded(child: TextField(controller: _msgC, minLines: 1, maxLines: 4, style: const TextStyle(fontSize: 15, fontFamily: 'TideFont'), decoration: InputDecoration(hintText: '发送新消息...', hintStyle: const TextStyle(color: Color(0xFFC7C7CC), fontSize: 14, fontFamily: 'TideFont'), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 8)))),
            GestureDetector(onTap: _toggleRec, child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.mic_rounded, size: 24, color: _isRecording ? Colors.red : const Color(0xFF8E8E93)))),
            if (_hasText || _loading) GestureDetector(onTap: () => _send(), child: Padding(padding: const EdgeInsets.all(6), child: Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: TideTheme.of(context).primary), child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white)))),
          ])),
        ),
      ),
    ));
  }

  Widget _mLabel(String t) => Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(t, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93), fontFamily: 'TideFont')));
  Widget _mField(TextEditingController c, {double h = 40}) => Container(height: h, decoration: BoxDecoration(color: const Color(0xFFE8E8F0), borderRadius: BorderRadius.circular(10)), child: TextField(controller: c, maxLines: null, expands: h > 50, style: const TextStyle(fontSize: 14, fontFamily: 'TideFont'), decoration: InputDecoration(contentPadding: const EdgeInsets.all(10), border: InputBorder.none)));
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    try { return firstWhere(test); } catch (_) { return null; }
  }
}
