import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'db.dart';
import 'theme.dart';
import 'wechat_bridge_service.dart';

class WechatConnectionPage extends StatefulWidget {
  const WechatConnectionPage({super.key});

  @override
  State<WechatConnectionPage> createState() => _WechatConnectionPageState();
}

class _WechatConnectionPageState extends State<WechatConnectionPage> {
  WechatBridgeState? _state;
  List<Map<String, dynamic>> _bots = const [];
  StreamSubscription<WechatBridgeState>? _subscription;

  @override
  void initState() {
    super.initState();
    _load();
    _subscription = WechatBridgeService.instance.states.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  Future<void> _load() async {
    final bots = await DBManager().getAllBots();
    final state = await WechatBridgeService.instance.currentState();
    if (mounted)
      setState(() {
        _bots = bots;
        _state = state;
      });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String get _botName {
    final id = _state?.botId ?? '';
    return _bots
            .where((bot) => bot['id']?.toString() == id)
            .map((bot) => bot['name']?.toString() ?? id)
            .firstOrNull ??
        '未选择';
  }

  Future<void> _chooseBot() async {
    final current = _state?.botId ?? '';
    final botId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择微信回复机器人')),
            for (final bot in _bots)
              ListTile(
                selected: bot['id']?.toString() == current,
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(bot['name']?.toString() ?? '未命名机器人'),
                subtitle: Text(bot['id']?.toString() ?? ''),
                onTap: () => Navigator.pop(context, bot['id']?.toString()),
              ),
          ],
        ),
      ),
    );
    if (botId == null) return;
    final state = _state;
    await WechatBridgeService.instance.configure(
      botId: botId,
      replyEnabled: state?.replyEnabled ?? true,
      proactiveSyncEnabled: state?.proactiveSyncEnabled ?? true,
    );
    await _load();
  }

  Future<void> _setReply(bool value) async {
    final state = _state;
    if (state == null) return;
    await WechatBridgeService.instance.configure(
      botId: state.botId,
      replyEnabled: value,
      proactiveSyncEnabled: state.proactiveSyncEnabled,
    );
  }

  Future<void> _setProactiveSync(bool value) async {
    final state = _state;
    if (state == null) return;
    await WechatBridgeService.instance.configure(
      botId: state.botId,
      replyEnabled: state.replyEnabled,
      proactiveSyncEnabled: value,
    );
  }

  Future<void> _bind() async {
    if ((_state?.botId ?? '').isEmpty) {
      await _chooseBot();
      if ((_state?.botId ?? '').isEmpty) return;
    }
    await WechatBridgeService.instance.connect(requestBinding: true);
  }

  Future<void> _disconnect() async {
    await WechatBridgeService.instance.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final state = _state;
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar:
          AppBar(title: const Text('连接到微信'), backgroundColor: theme.bgColor),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('OpenClaw 微信桥接',
            style: TextStyle(
                color: theme.textStrong,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFamily: 'TideFont')),
        const SizedBox(height: 8),
        Text(state?.status ?? '正在读取连接状态',
            style: TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.smart_toy_rounded, color: theme.primary),
          title: const Text('已连接机器人', style: TextStyle(fontFamily: 'TideFont')),
          subtitle:
              Text(_botName, style: const TextStyle(fontFamily: 'TideFont')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _chooseBot,
        ),
        const Divider(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('消息自动回复', style: TextStyle(fontFamily: 'TideFont')),
          subtitle: const Text('收到微信文本后交给所选机器人回复',
              style: TextStyle(fontFamily: 'TideFont')),
          value: state?.replyEnabled ?? true,
          onChanged: _setReply,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('主动回复同步', style: TextStyle(fontFamily: 'TideFont')),
          subtitle: const Text('保留主动回复同步配置',
              style: TextStyle(fontFamily: 'TideFont')),
          value: state?.proactiveSyncEnabled ?? true,
          onChanged: _setProactiveSync,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: state?.binding == true ? null : _bind,
          icon: const Icon(Icons.qr_code_rounded),
          label: Text(state?.connected == true ? '重新获取绑定二维码' : '连接并获取二维码'),
        ),
        if (state?.connected == true) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.link_off_rounded),
            label: const Text('解除连接'),
          ),
        ],
        if (state?.qrUrl?.isNotEmpty == true) ...[
          const SizedBox(height: 24),
          Center(
            child: Column(children: [
              QrImageView(
                  data: state!.qrUrl!,
                  size: 224,
                  backgroundColor: Colors.white),
              const SizedBox(height: 12),
              Text('请使用微信扫描二维码完成绑定',
                  style:
                      TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
            ]),
          ),
        ],
      ]),
    );
  }
}
