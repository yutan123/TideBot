import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'ai.dart';
import 'db.dart';
import 'theme.dart';

/// OpenClaw 微信私聊桥接配置页。APP 不登录用户微信，仅保存桥接服务提供的
/// 设备绑定会话；消息收发和二维码由已部署的 OpenClaw 插件服务完成。
class WeChatConnectionPage extends StatefulWidget {
  const WeChatConnectionPage({super.key});
  @override
  State<WeChatConnectionPage> createState() => _WeChatConnectionPageState();
}

class _WeChatConnectionPageState extends State<WeChatConnectionPage> {
  String _botId = '';
  String _botName = '';
  String _status = '未连接';
  String _qrUrl = '';
  bool _loading = true;
  bool _connecting = false;
  bool _syncing = false;
  Timer? _poller;
  String _syncedText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final db = DBManager();
    final id = await db.getKV('wechat_bot_id') ?? '';
    final status = await db.getKV('wechat_connection_status') ?? '未连接';
    final bot = id.isEmpty ? null : await db.getBotById(id);
    if (mounted)
      setState(() {
        _botId = id;
        _botName = bot?['name']?.toString() ?? '';
        _status = status;
        _loading = false;
      });
  }

  Future<void> _chooseBot() async {
    final bots = await DBManager().queryBots();
    if (!mounted || bots.isEmpty) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => ListView(children: [
        const ListTile(title: Text('选择接入微信的机器人')),
        ...bots.map((b) => ListTile(
              title: Text(b['name']?.toString() ?? '未命名机器人'),
              subtitle: const Text('微信仅转发私聊消息'),
              onTap: () => Navigator.pop(ctx, b),
            )),
      ]),
    );
    if (selected == null) return;
    await DBManager().setKV('wechat_bot_id', selected['id'].toString());
    if (mounted)
      setState(() {
        _botId = selected['id'].toString();
        _botName = selected['name']?.toString() ?? '';
      });
  }

  Future<void> _connect() async {
    if (_botId.isEmpty) {
      await _chooseBot();
      if (_botId.isEmpty) return;
    }
    final db = DBManager();
    final bridge = (await db.getKV('openclaw_bridge_url') ?? '').trim();
    if (!bridge.startsWith('http')) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先在高级设置配置 OpenClaw 桥接地址')));
      return;
    }
    setState(() {
      _connecting = true;
      _status = '正在获取二维码';
    });
    try {
      final response = await http
          .post(
              Uri.parse(
                  '${bridge.replaceFirst(RegExp(r'/+$'), '')}/wechat/connect'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'bot_id': _botId}))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw StateError('桥接服务返回 ${response.statusCode}');
      final body = jsonDecode(response.body) as Map;
      _qrUrl = body['qr_url']?.toString() ?? body['qrcode']?.toString() ?? '';
      _status = body['status']?.toString() ?? '等待扫码';
      await db.setKV('wechat_connection_status', _status);
      _startPolling(bridge);
    } catch (e) {
      _status = '连接失败：$e';
    }
    if (mounted) setState(() => _connecting = false);
  }

  void _startPolling(String bridge) {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final response = await http
            .get(Uri.parse(
                '${bridge.replaceFirst(RegExp(r'/+$'), '')}/wechat/status?bot_id=$_botId'))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) return;
        final body = jsonDecode(response.body) as Map;
        final next = body['status']?.toString() ?? _status;
        await DBManager().setKV('wechat_connection_status', next);
        if (mounted)
          setState(() {
            _status = next;
            _qrUrl = body['qr_url']?.toString() ?? _qrUrl;
          });
        // 连接成功后除了更新状态，还要拉取并处理微信私聊里的新消息。
        if (next == '已连接' || next == '连接成功') {
          _poller?.cancel();
          await _syncWechatMessages(bridge);
        }
      } catch (_) {}
    });
  }

  /// 拉取桥接服务的微信私聊新消息，逐条调用 TideBot 模型处理并回发，
  /// 同时同步到本应用的聊天记录。用 KV 标记每条消息 id 保证幂等。
  Future<void> _syncWechatMessages(String bridge) async {
    if (_syncing || _botId.isEmpty) return;
    _syncing = true;
    final db = DBManager();
    final base = bridge.replaceFirst(RegExp(r'/+$'), '');
    final cursor =
        int.tryParse(await db.getKV('wechat_last_cursor') ?? '') ?? 0;
    try {
      final response = await http
          .get(Uri.parse('$base/wechat/poll?bot_id=$_botId&after=$cursor'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      final List<dynamic> events = decoded is Map
          ? ((decoded['messages'] ?? decoded['events'] ?? []) as List)
          : (decoded as List);
      if (events.isEmpty) return;
      var maxTs = cursor;
      for (final raw in events) {
        if (raw is! Map) continue;
        final msgId = raw['id']?.toString() ?? raw['msg_id']?.toString() ?? '';
        final from = (raw['from'] ?? raw['from_user'] ?? '').toString();
        final content = (raw['content'] ?? raw['text'] ?? '').toString();
        final ts = (raw['timestamp'] as num?)?.toInt() ??
            (raw['ts'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        if (ts > maxTs) maxTs = ts;
        if (msgId.isEmpty || content.isEmpty) continue;
        // 只处理微信发来的消息（非系统事件），且每条只处理一次。
        if (from == 'system' || from == 'server') continue;
        final doneKey = 'wechat_processed_$msgId';
        if (await db.getKV(doneKey) == '1') continue;
        await _handleWechatMessage(db, base, msgId, content, ts);
        await db.setKV(doneKey, '1');
      }
      await db.setKV('wechat_last_cursor', '$maxTs');
      if (mounted) {
        setState(() => _syncedText = '已同步最近 ${events.length} 条微信消息');
      }
    } catch (e) {
      debugPrint('[wechat] sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  /// 处理单条微信私聊消息：落库 → 交给 TideBot 模型产出回复 → 回发微信。
  Future<void> _handleWechatMessage(
      DBManager db, String base, String msgId, String content, int ts) async {
    // 1) 把微信发来的用户消息写入本地聊天记录（role=user）。
    await db.insertChatMessage({
      'id': 'wx_${msgId}_u',
      'bot_id': _botId,
      'role': 'user',
      'type': 'text',
      'content': content,
      'file_path': '',
      'mood': '',
      'duration': 0,
      'error_log': '',
      'error_code': '',
      'error_message': '',
      'reply_to_id': '',
      'sources_json': '',
      'timestamp': ts,
    });

    // 2) 交给 TideBot 模型处理，产出一条自然语言回复。
    String reply = '';
    try {
      final res = await AIManager().sendMessage(
        botId: _botId,
        text: content,
        includeChatHistory: true,
        enableAutoSummary: false,
      );
      reply = (res['success'] == true
              ? res['reply']?.toString()
              : res['error']?.toString()) ??
          '';
    } catch (e) {
      reply = '抱歉，我暂时无法回复（$e）';
    }
    if (reply.trim().isEmpty) reply = '（收到你的消息，但暂时没有可用模型回复）';

    // 3) 把机器人回复写入聊天记录（role=assistant）。
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insertChatMessage({
      'id': 'wx_${msgId}_r',
      'bot_id': _botId,
      'role': 'assistant',
      'type': 'text',
      'content': reply,
      'file_path': '',
      'mood': '',
      'duration': 0,
      'error_log': '',
      'error_code': '',
      'error_message': '',
      'reply_to_id': 'wx_${msgId}_u',
      'sources_json': '',
      'timestamp': now,
    });

    // 4) 把 TideBot 的回复回发给微信用户。
    try {
      await http
          .post(Uri.parse('$base/wechat/reply'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'bot_id': _botId,
                'msg_id': msgId,
                'content': reply,
              }))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[wechat] reply failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('连接到微信', style: TextStyle(fontFamily: 'TideFont'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primary))
          : ListView(padding: const EdgeInsets.all(20), children: [
              Card(
                  child: ListTile(
                      leading: Icon(Icons.link_rounded, color: theme.primary),
                      title: Text(_status,
                          style: const TextStyle(fontFamily: 'TideFont')),
                      subtitle: Text(
                          _botId.isEmpty ? '当前未连接到微信' : '已选择机器人：$_botName'))),
              const SizedBox(height: 14),
              ListTile(
                  leading: const Icon(Icons.smart_toy_rounded),
                  title: const Text('接入机器人'),
                  subtitle: Text(_botId.isEmpty ? '请选择机器人' : _botName),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _chooseBot),
              const SizedBox(height: 14),
              // 桥接地址（与高级设置共享同一个 KV，可在此快速修改）。
              _BridgeUrlTile(onSaved: () {
                if (mounted) setState(() {});
              }),
              const SizedBox(height: 14),
              if (_qrUrl.isNotEmpty)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          const Text('请使用微信扫码完成私聊绑定',
                              style: TextStyle(fontFamily: 'TideFont')),
                          const SizedBox(height: 12),
                          Image.network(_qrUrl,
                              width: 220,
                              height: 220,
                              errorBuilder: (_, __, ___) =>
                                  const Text('二维码加载失败，请刷新连接')),
                        ]))),
              const SizedBox(height: 18),
              FilledButton.icon(
                  onPressed: _connecting ? null : _connect,
                  icon: const Icon(Icons.qr_code_rounded),
                  label: Text(_connecting ? '正在请求二维码…' : '连接 / 刷新二维码')),
              const SizedBox(height: 10),
              // 手动触发一次消息同步，并显示最近同步结果。
              OutlinedButton.icon(
                  onPressed: _syncing
                      ? null
                      : () async {
                          final bridge =
                              (await DBManager().getKV('openclaw_bridge_url') ??
                                      '')
                                  .trim();
                          if (!bridge.startsWith('http')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('请先配置 OpenClaw 桥接地址'),
                                    behavior: SnackBarBehavior.floating));
                            return;
                          }
                          await _syncWechatMessages(bridge);
                        },
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(_syncing ? '正在同步…' : '同步微信消息')),
              if (_syncedText.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_syncedText,
                        style: TextStyle(
                            color: theme.textWeak,
                            fontSize: 12,
                            fontFamily: 'TideFont'))),
              const SizedBox(height: 18),
              Text(
                  '说明：通过 OpenClaw 微信插件完成二维码绑定，仅支持私聊。微信消息会交由已选机器人使用 TideBot 的模型配置处理，回复和聊天记录会同步到本应用。',
                  style: TextStyle(
                      color: theme.textWeak,
                      height: 1.6,
                      fontFamily: 'TideFont')),
            ]),
    );
  }
}

/// 桥接地址编辑控件（与高级设置共享 openclaw_bridge_url 这一 KV）。
class _BridgeUrlTile extends StatefulWidget {
  const _BridgeUrlTile({this.onSaved});
  final VoidCallback? onSaved;
  @override
  State<_BridgeUrlTile> createState() => _BridgeUrlTileState();
}

class _BridgeUrlTileState extends State<_BridgeUrlTile> {
  String _saved = '';
  bool _loaded = false;

  Future<void> _load() async {
    final v = await DBManager().getKV('openclaw_bridge_url') ?? '';
    if (!mounted) return;
    setState(() {
      _saved = v;
      _loaded = true;
    });
  }

  Future<void> _edit() async {
    final ctrl = TextEditingController(text: _saved);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OpenClaw 桥接地址',
            style: TextStyle(fontFamily: 'TideFont')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              hintText: 'http://192.168.1.100:8200',
              hintStyle: TextStyle(fontFamily: 'TideFont')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('取消', style: TextStyle(fontFamily: 'TideFont'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child:
                  const Text('保存', style: TextStyle(fontFamily: 'TideFont'))),
        ],
      ),
    );
    if (result == null) return;
    await DBManager().setKV('openclaw_bridge_url', result);
    if (!mounted) return;
    setState(() => _saved = result);
    widget.onSaved?.call();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.dns_rounded, color: theme.primary),
        title: const Text('桥接地址', style: TextStyle(fontFamily: 'TideFont')),
        subtitle: Text(_loaded ? (_saved.isNotEmpty ? _saved : '未配置') : '加载中…',
            style: TextStyle(
                color: theme.textWeak, fontFamily: 'TideFont', fontSize: 12)),
        trailing: const Icon(Icons.edit_rounded),
        onTap: _edit,
      ),
    );
  }
}
