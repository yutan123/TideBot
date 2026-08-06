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
import 'package:permission_handler/permission_handler.dart';
import 'db.dart';
import 'ai.dart';
import 'ui_components.dart';
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
  
  late AnimationController _bottomBarCtrl;
  bool _hasText = false;
  void _msgChanged() { if (mounted) setState(() => _hasText = _msgC.text.isNotEmpty); }

  @override void initState() {
    super.initState();
    _bot = Map.from(widget.botData);
    _msgC.addListener(_msgChanged);
    _loadMsgs(); _loadBg();
    
    // 底部栏动画控制器
    _bottomBarCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200)); // 减慢动画速度
    // 首帧后启动进场动画，否则 SlideTransition 会一直停在向下偏移 25% 的位置，
    // 这就是输入框一直偏下、"怎么调 padding 都不动"的根因。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bottomBarCtrl.forward();
    });
  }
  
  @override void dispose() { 
    _msgC.removeListener(_msgChanged); _msgC.dispose(); _scrollC.dispose(); _rec.dispose(); _player.dispose(); _recTimer?.cancel();
    _bottomBarCtrl.dispose(); // 添加动画控制器释放
    super.dispose(); 
  }

  void _loadBg() async {
    final prefs = await SharedPreferences.getInstance();
    final bg = prefs.getString('chat_bg_${_bot['id']}');
    if (mounted) setState(() => _customBg = bg);
  }

  void _loadMsgs() async {
    print('_loadMsgs called with bot ID: ${_bot['id']}');
    try {
      final msgs = await DBManager().queryMessages(_bot['id'] as String, limit: 100);
      print('_loadMsgs success: got ${msgs.length} messages');
      // queryMessages 按 timestamp ASC（旧→新），ListView 从上往下渲染，
      // 直接使用即可保证"旧消息在上、新消息在下"，与 _send 追加到末尾一致。
      if (mounted) setState(() { _msgs = msgs; _msgsLoading = false; });
    } catch (e) {
      print('_loadMsgs error: $e');
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
    try {
      final text = _msgC.text.trim();
      if (text.isEmpty && img == null) {
        if (mounted) setState(() => _hasText = false);
        return; // 无内容时空点发送不触发
      }
      if (_loading) return; // 避免连点重复发送
      setState(() => _loading = true);
      final now = DateTime.now().millisecondsSinceEpoch;

      // 先保证已选择一个可用模型：若 bot 还没配 chat_model，但存在默认 provider，则自动用第一个
      String? cm;
      try {
        cm = _bot['chat_model'] as String?;
        if (cm == null || cm.toString().isEmpty) {
          final providers = await DBManager().queryChatProviders();
          if (providers.isNotEmpty) {
            cm = providers.first['id'] as String;
            _bot['chat_model'] = cm;
            await DBManager().updateBot(_bot['id'] as String, {'chat_model': cm});
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('请先在「我的 → API 设置」添加模型，再回来聊天～', style: TextStyle(fontFamily: 'TideFont')),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Color(0xFFE74C3C),
              ));
            }
            setState(() => _loading = false);
            return;
          }
        }
      } catch (e) {
        debugPrint('[send] provider resolve error: $e');
        setState(() => _loading = false);
        return;
      }

      // 插入并显示用户消息（保证用户自己的发言一定上屏）
      final msg = <String, dynamic>{'id': 'm_$now', 'bot_id': _bot['id'], 'role': 'user', 'content': text, 'image': img, 'timestamp': now};
      try {
        await DBManager().insertMessage(msg);
      } catch (e) { debugPrint('[send] insert user msg error: $e'); }
      if (mounted) setState(() { _msgs.add(msg); _msgC.clear(); _msgsLoading = false; _typing = true; });
      _scrollDown();

      try {
        final history = _msgs.where((m) => (m['content'] as String?)?.isNotEmpty == true).map((m) => {'role': m['role'], 'content': m['content']}).toList();
        var imgB64 = '';
        if (img != null) imgB64 = base64Encode(await File(img).readAsBytes());
        final resp = await AIManager().chat(botId: _bot['id'] as String, messages: history, imageBase64: imgB64);
        debugPrint('[send] chat resp: ${resp.substring(0, resp.length > 80 ? 80 : resp.length)}');
        final isErr = resp.startsWith('[X]') || resp.startsWith('未配置') || resp.startsWith('映射的模型');
        final bm = <String, dynamic>{'id': 'm_${DateTime.now().millisecondsSinceEpoch}', 'bot_id': _bot['id'], 'role': 'assistant',
          'content': isErr ? resp : (resp.isEmpty ? '[X] 模型返回了空内容，请检查配置' : resp), 'timestamp': DateTime.now().millisecondsSinceEpoch};
        try { await DBManager().insertMessage(bm); } catch (e) { debugPrint('[send] insert ai msg error: $e'); }
        if (mounted) setState(() => _msgs.add(bm));
      } catch (e) {
        debugPrint('[send] chat exception: $e');
        final err = <String, dynamic>{'id': 'm_err_${DateTime.now().millisecondsSinceEpoch}', 'bot_id': _bot['id'], 'role': 'assistant', 'content': '[X] 连接失败: $e', 'timestamp': DateTime.now().millisecondsSinceEpoch};
        try { await DBManager().insertMessage(err); } catch (_) {}
        if (mounted) setState(() => _msgs.add(err));
      }
    } finally {
      if (mounted) setState(() { _loading = false; _typing = false; });
    }
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
      // 主动请求录音权限（弹系统授权框），被拒绝则引导去设置
      final micStatus = await Permission.microphone.request();
      if (micStatus.isGranted) {
        final dir = await getApplicationDocumentsDirectory();
        final p = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _rec.start(path: p, encoder: AudioEncoder.aacLc, bitRate: 128000);
        setState(() => _isRecording = true);
        _recTimer = Timer.periodic(const Duration(seconds: 1), (t) { if (mounted) setState(() => _recSecs++); });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('需要麦克风权限才能录音，请在设置中开启～', style: TextStyle(fontFamily: 'TideFont')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFE74C3C),
        ));
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
      // 选择相册前主动请求图片读取权限（Android 13+ photos / 旧版 storage）
      bool granted = true;
      try { granted = await Permission.photos.isGranted || (await Permission.photos.request()).isGranted; } catch (_) {
        try { granted = (await Permission.storage.request()).isGranted; } catch (_) {}
      }
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('需要相册权限才能选择图片，请在设置中开启～', style: TextStyle(fontFamily: 'TideFont')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFFE74C3C),
          ));
        }
        return;
      }
      final p = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (p != null) _send(img: await _fixHeic(p.path));
    } else if (r == 'file') {
      try { await Permission.storage.request(); } catch (_) {}
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
    String avatar = _bot['avatar']?.toString() ?? '';
    TideDialogs.show(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      // 更换头像：从相册选择并复制到应用目录
      Future<void> pickNewAvatar() async {
        try {
          final picker = ImagePicker();
          final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512);
          if (img != null) {
            String path = img.path;
            if (path.toLowerCase().endsWith('.heic') || path.toLowerCase().endsWith('.heif')) {
              try {
                final converted = await HeifConverter.convert(path);
                if (converted != null) path = converted;
              } catch (_) {}
            }
            final dir = await getApplicationDocumentsDirectory();
            final dest = '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
            await File(path).copy(dest);
            if (mounted) setSt(() => avatar = dest);
          }
        } catch (_) {}
      }
      return AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero,
        content: TideDialogs.glassContent(context: ctx, children: [
          const Center(child: Text('机器人信息', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'TideFont'))),
          const SizedBox(height: 14),
          // 头像更换
          Center(child: GestureDetector(onTap: pickNewAvatar, child: Stack(children: [
            Container(width: 72, height: 72, decoration: BoxDecoration(borderRadius: BorderRadius.circular(36), color: const Color(0xFFE8E8F0)), child: avatar.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(36), child: Image.file(File(avatar), fit: BoxFit.cover)) : const Center(child: Icon(Icons.person_rounded, color: Color(0xFF8E8E93), size: 30))),
            Positioned(right: 0, bottom: 0, child: Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, color: TideTheme.of(ctx).primary), child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white))),
          ]))),
          const SizedBox(height: 8),
          const Center(child: Text('点按头像可更换', style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93), fontFamily: 'TideFont'))),
          const SizedBox(height: 8),
          _mLabel('名字'), _mField(n),
          const SizedBox(height: 10), _mLabel('人格设定'), _mField(d, h: 80),
          const SizedBox(height: 10), _mLabel('说话方式'), _mField(p, h: 100),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: TideDialogs.glassButton('保存', onTap: () async {
            final botId = _bot['id'] as String;
            _bot['name'] = n.text; _bot['desc'] = d.text; _bot['prompt'] = p.text; _bot['avatar'] = avatar;
            await DBManager().updateBot(botId, {
              'name': n.text, 'desc': d.text, 'prompt': p.text, 'avatar': avatar,
            });
            Navigator.pop(ctx); setState(() {});
          })),
        ]));
    }));
  }

  // ========== 模型设置弹窗 ==========
  // 需求#5显示模型名 / #6 TTS分开+音色 / #7 token实时反馈：统一改为 StatefulBuilder + 本地状态，点击即刷新
  void _showModelSettings() async {
    final providers = await DBManager().queryChatProviders();
    final ttsProviders = await DBManager().queryTtsProviders();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final botId = _bot['id'] as String;
    // 当前选择（只读读取 DB，作为初始值；弹窗内实时状态交给 setSt 维护）
    String curChat = prefs.getString('chat_model_$botId') ?? ((_bot['chat_model'] as String?)?.isNotEmpty == true ? _bot['chat_model'] as String : (providers.isNotEmpty ? providers.first['id'] as String : ''));
    String curTts = prefs.getString('tts_model_$botId') ?? ((_bot['tts_model'] as String?)?.isNotEmpty == true ? _bot['tts_model'] as String : '');
    int curTok = prefs.getInt('max_token_$botId') ?? (_bot['max_tokens'] as int? ?? 10000);

    TideDialogs.show(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      // 选中项实时更新到内存 & 持久化，让界面即时刷新
      Future<void> pickModel(String key, String val, {bool isTts = false}) async {
        setSt(() {});
        await prefs.setString(key, val);
        if (!isTts && key == 'chat_model_$botId') {
          _bot['chat_model'] = val;
          await DBManager().updateBot(botId, {'chat_model': val});
        }
        if (isTts && key == 'tts_model_$botId') {
          _bot['tts_model'] = val;
          await DBManager().updateBot(botId, {'tts_model': val});
        }
        setSt(() {});
      }
      return AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero,
        content: TideDialogs.glassContent(context: ctx, maxWidth: 0.9, children: [
          const Center(child: Text('模型设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'TideFont'))),
          const SizedBox(height: 12),
          Flexible(child: SingleChildScrollView(child: Column(children: [
            _mLabel('聊天模型'), _modelPicker(ctx, providers, curChat, (v) async { curChat = v; await pickModel('chat_model_$botId', v); }),
            // TTS 模型独立：从 tts_provider_list 读取，额外展示音色字段（可选，不配置则纯文字回复）
            _mLabel('TTS模型（语音，可选）'), _modelPicker(ctx, ttsProviders, curTts, (v) async { curTts = v; await pickModel('tts_model_$botId', v, isTts: true); }),
            _mLabel('最大上下文Token'),
            _tokenField(ctx, curTok, (v) async { curTok = v; await prefs.setInt('max_token_$botId', v); await DBManager().updateBot(botId, {'max_tokens': v}); setSt(() {}); }),
          ]))),
          const SizedBox(height: 12),
          TideDialogs.glassButton('确定', onTap: () => Navigator.pop(ctx)),
        ]));
    }));
  }

  // token 选择字段，点击弹底部选择，选中后立即回调更新
  Widget _tokenField(BuildContext parentCtx, int cur, Future<void> Function(int) onPick) {
    Future<void> choose(int v) async { await onPick(v); if (mounted) setState(() {}); }
    return GestureDetector(
      onTap: () {
        final c = TextEditingController(text: cur.toString());
        showTideSheet(context: parentCtx, height: 260, child: Column(children: [
          const SizedBox(height: 10),
          const Text('最大上下文', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
          const SizedBox(height: 8),
          ListTile(title: const Text('10,000 token', style: TextStyle(fontFamily: 'TideFont')), trailing: cur == 10000 ? Icon(Icons.check, color: TideTheme.of(parentCtx).primary) : null, onTap: () { Navigator.pop(parentCtx); choose(10000); }),
          ListTile(title: const Text('20,000 token', style: TextStyle(fontFamily: 'TideFont')), trailing: cur == 20000 ? Icon(Icons.check, color: TideTheme.of(parentCtx).primary) : null, onTap: () { Navigator.pop(parentCtx); choose(20000); }),
          ListTile(title: const Text('自定义...', style: TextStyle(fontFamily: 'TideFont')), onTap: () {
            Navigator.pop(parentCtx);
            TideDialogs.show(context: parentCtx, builder: (c2) => AlertDialog(backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero, content: TideDialogs.glassContent(context: c2, children: [
              const Text('自定义Token', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'TideFont')),
              const SizedBox(height: 10),
              TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: '输入token数量', hintStyle: const TextStyle(fontFamily: 'TideFont'), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))))),
              const SizedBox(height: 12),
              TideDialogs.glassButton('确定', onTap: () { final v = int.tryParse(c.text); if (v != null && v > 0) choose(v); Navigator.pop(c2); }),
            ])));
          }),
        ]));
      },
      child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: const Color(0xFFE8E8F0), borderRadius: BorderRadius.circular(10)), child: Align(alignment: Alignment.centerLeft, child: Text(cur >= 1000 ? '${cur.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (m) => ',')} token' : '$cur token', style: const TextStyle(fontSize: 14, fontFamily: 'TideFont')))));
  }

  // 模型选择器：普通模型显示「名字 · 模型名」，TTS 额外显示「音色」
  Widget _modelPicker(BuildContext ctx, List<Map<String, dynamic>> providers, String cur, Function(String) onPick) {
    final sel = providers.firstWhereOrNull((p) => p['id'] == cur);
    final String disp;
    if (sel != null) {
      final name = sel['name']?.toString() ?? '未选择';
      final model = sel['model']?.toString().trim() ?? '';
      final voice = sel['voice']?.toString().trim() ?? '';
      if (voice.isNotEmpty) {
        disp = '$name · $model · 音色:$voice';
      } else {
        disp = model.isNotEmpty ? '$name · $model' : name;
      }
    } else {
      disp = providers.isEmpty ? '无可用模型' : '未选择';
    }
    return GestureDetector(
      onTap: () {
        showTideSheet(context: ctx, height: 380, child: ListView(children: [
          for (var pv in providers)
            ListTile(
              title: Text(_providerTitle(pv), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'TideFont', fontSize: 14)),
              subtitle: Text(_providerSub(pv), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontFamily: 'TideFont')),
              trailing: cur == pv['id'] ? Icon(Icons.check, color: TideTheme.of(ctx).primary) : null,
              onTap: () { onPick(pv['id'] as String); Navigator.pop(ctx); },
            ),
        ]));
      },
      child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: const Color(0xFFE8E8F0), borderRadius: BorderRadius.circular(10)), child: Align(alignment: Alignment.centerLeft, child: Text(disp, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontFamily: 'TideFont')))));
  }

  String _providerTitle(Map<String, dynamic> p) {
    final name = p['name']?.toString() ?? '';
    return name;
  }
  String _providerSub(Map<String, dynamic> p) {
    final model = p['model']?.toString().trim() ?? '';
    final voice = p['voice']?.toString().trim() ?? '';
    if (voice.isNotEmpty) return '$model · 音色:$voice';
    return model;
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
    final theme = TideTheme.of(context);
    // 背景优先级：单机器人自定义 > 全局主题背景 > 主题底色
    final String? effBg = _hasBg ? _customBg : (theme.chatBg.isNotEmpty ? theme.chatBg : null);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        // 背景：与主界面一致的主题底色 + 柔光光斑(不再用强烈渐变)，避免黑屏/割裂
        Positioned.fill(
          child: effBg != null
            ? Image.file(File(effBg), fit: BoxFit.cover)
            : DecoratedBox(
                decoration: BoxDecoration(color: theme.bgColor),
                child: Stack(children: [
                  Positioned(left: -80, top: -60, child: IgnorePointer(child: Container(width: 240, height: 240, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [theme.primaryLight.withOpacity(0.25), Colors.transparent]))))),
                  Positioned(right: -60, bottom: 120, child: IgnorePointer(child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [theme.primary.withOpacity(0.15), Colors.transparent]))))),
                ]),
              ),
        ),
        Column(children: [_chatHeader(), Expanded(child: _chatBody()), _inputBar()]),
      ]),
    );
  }
Widget _chatHeader() {
    return ClipRRect(
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: _hasBg ? TideTheme.of(context).glass.withOpacity(0.15) : TideTheme.of(context).glass.withOpacity(0.55),
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
        spans.add(TextSpan(text: text.substring(last, m.start), style: TextStyle(color: isUser ? Colors.white : TideTheme.of(context).textStrong, fontSize: 14, fontFamily: 'TideFont')));
      }
      spans.add(TextSpan(text: text.substring(m.start, m.end), style: TextStyle(color: isUser ? Colors.white.withOpacity(0.6) : TideTheme.of(context).textWeak, fontSize: 12, fontFamily: 'TideFont', fontStyle: FontStyle.italic)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: TextStyle(color: isUser ? Colors.white : TideTheme.of(context).textStrong, fontSize: 14, fontFamily: 'TideFont')));
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isUser ? TideTheme.of(context).primary : TideTheme.of(context).bubbleAi, borderRadius: BorderRadius.circular(16)), child: RichText(text: TextSpan(children: spans)));
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: SlideTransition(
        // 直接用 controller 驱动位移，消除此前"从未 forward + 嵌套 CurvedAnimation"导致停在下偏30%的问题
        position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(CurvedAnimation(parent: _bottomBarCtrl, curve: Curves.easeOutCubic)),
        child: Padding(
          // 轻微上浮：此前"被截断一半"是动画停在下偏的 bug（已修），现在动画归零；这里仅留适度间距避免紧贴屏幕底
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          child: Container(
            decoration: _hasBg ? BoxDecoration(color: TideTheme.of(context).glass.withOpacity(0.1)) : null,
            child: ClipRRect(
              child: BackdropFilter(filter: _hasBg ? ImageFilter.blur(sigmaX: 20, sigmaY: 20) : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: _hasBg ? TideTheme.of(context).glass.withOpacity(0.6) : TideTheme.of(context).surface.withOpacity(0.85), borderRadius: BorderRadius.circular(22)), child: Row(children: [
                  GestureDetector(onTap: _pickMedia, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.add_rounded, size: 24, color: Color(0xFF8E8E93)))),
                  Expanded(child: TextField(controller: _msgC, minLines: 1, maxLines: 4, style: const TextStyle(fontSize: 15, fontFamily: 'TideFont'), decoration: InputDecoration(hintText: '发送新消息...', hintStyle: const TextStyle(color: Color(0xFFC7C7CC), fontSize: 14, fontFamily: 'TideFont'), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 8)))),
                  GestureDetector(onTap: _toggleRec, child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.mic_rounded, size: 24, color: _isRecording ? Colors.red : const Color(0xFF8E8E93)))),
                  // 发送按钮：始终显示（不再依赖 _hasText 条件渲染，避免"输入了却看不到/点不动"的情况）
                  GestureDetector(
                    onTap: () { _send(); },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(padding: const EdgeInsets.all(6), child: Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: TideTheme.of(context).primary.withOpacity(_hasText ? 0.5 : 0.2), blurRadius: 8),], color: TideTheme.of(context).primary.withOpacity(_hasText ? 1 : 0.45)), child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white))),
                  ),
                ])),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mLabel(String t) => Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(t, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93), fontFamily: 'TideFont')));
  Widget _mField(TextEditingController c, {double h = 40}) => Container(height: h, decoration: BoxDecoration(color: const Color(0xFFE8E8F0), borderRadius: BorderRadius.circular(10)), child: TextField(controller: c, maxLines: null, expands: h > 50, style: const TextStyle(fontSize: 14, fontFamily: 'TideFont'), decoration: InputDecoration(contentPadding: const EdgeInsets.all(10), border: InputBorder.none)));
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    try { return firstWhere(test); } catch (_) { return null; }
  }
}
