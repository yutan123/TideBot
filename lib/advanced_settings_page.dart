import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_log_service.dart';
import 'bot_state.dart';
import 'db.dart';
import 'device_capability_service.dart';
import 'external_api_service.dart';
import 'global_notice.dart';
import 'log_session_detail_page.dart';
import 'theme.dart';
import 'ui_components.dart';

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({super.key});

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  bool _logging = AppLogService.instance.enabled;
  bool _haptics = false;
  bool _extraContext = false;
  bool _operationProactive = false;
  bool _externalApiEnabled = false;
  String _externalApiPort = '6666';
  String _externalApiKey = '';
  String _externalApiBotId = '';
  bool _externalApiSyncMessages = true;
  List<String> _externalApiUrls = const [];
  String _externalApiUrl = '';
  List<Map<String, dynamic>> _bots = const [];
  final Map<String, String> _boundBotNames = {};
  Timer? _ticker;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _logging) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    });
  }

  Future<void> _load() async {
    await TideHaptics.load();
    final prefs = await SharedPreferences.getInstance();
    final enabled = AppLogService.instance.enabled;
    final capability = DeviceCapabilityService.instance;
    final bots = await DBManager().getAllBots();
    final db = DBManager();
    final botNames = <String, String>{};
    for (final feature in const [
      DeviceCapabilityService.contextFeature,
      DeviceCapabilityService.proactiveFeature,
    ]) {
      final id = await capability.boundBot(feature);
      if (id != null && id.isNotEmpty) {
        final bot = bots.cast<Map<String, dynamic>>().firstWhere(
              (item) => item['id']?.toString() == id,
              orElse: () => const {},
            );
        botNames[feature] = bot['name']?.toString() ?? id;
      }
    }
    final externalEnabled = await db.getKV('external_api_enabled') == 'true';
    final externalPort = await db.getKV('external_api_port') ?? '6666';
    final externalKey = await db.getKV('external_api_key') ?? '';
    final externalBotId = await db.getKV('external_api_bot_id') ?? '';
    final externalSync =
        await db.getKV('external_api_sync_messages') != 'false';
    final urls = await ExternalApiService.instance
        .baseUrls(port: int.tryParse(externalPort));
    final externalUrl = await ExternalApiService.instance
        .preferredBaseUrl(port: int.tryParse(externalPort));
    if (mounted) {
      setState(() {
        _logging = enabled;
        _haptics = prefs.getBool('tide_haptics_enabled') ?? true;
        _extraContext = prefs.getBool('extra_context_enabled') ?? false;
        _operationProactive =
            prefs.getBool('operation_proactive_enabled') ?? false;
        _externalApiEnabled = externalEnabled;
        _externalApiPort = externalPort;
        _externalApiKey = externalKey;
        _externalApiBotId = externalBotId;
        _externalApiSyncMessages = externalSync;
        _externalApiUrls = urls;
        _externalApiUrl = externalUrl;
        _bots = bots.cast<Map<String, dynamic>>();
        _boundBotNames
          ..clear()
          ..addAll(botNames);
      });
    }
  }

  Future<void> _setProtectedToggle({
    required String key,
    required String feature,
    required bool value,
    required String title,
    required String description,
    required Set<String> defaultWhitelist,
    required ValueChanged<bool> update,
  }) async {
    final capability = DeviceCapabilityService.instance;
    if (!value) {
      await (await SharedPreferences.getInstance()).setBool(key, false);
      if (mounted) setState(() => update(false));
      return;
    }
    if (!mounted) return;
    final approved = await TideDialogs.show<bool>(
          context: context,
          builder: (ctx) => TideDialogSurface(
            title: Text(title, style: const TextStyle(fontFamily: 'TideFont')),
            content: Text(description,
                style: const TextStyle(fontFamily: 'TideFont')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('配置授权')),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    final bots = await DBManager().getAllBots();
    if (!mounted || bots.isEmpty) return;
    final botId = await showTideSheet<String>(
      context: context,
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择可使用此能力的机器人')),
            for (final bot in bots)
              ListTile(
                title: Text(bot['name']?.toString() ?? '未命名机器人'),
                subtitle: Text(bot['id']?.toString() ?? ''),
                onTap: () => Navigator.pop(context, bot['id']?.toString()),
              ),
          ],
        ),
      ),
    );
    if (botId == null || botId.isEmpty) return;
    await capability.bindBot(feature, botId);
    final selected = await _chooseWhitelist(feature, defaultWhitelist);
    if (selected == null || selected.isEmpty) return;
    await capability.setWhitelist(feature, selected);
    await _requestMissingSystemPermissions(feature, selected);
    await (await SharedPreferences.getInstance()).setBool(key, true);
    if (mounted) setState(() => update(true));
  }

  Future<Set<String>?> _chooseWhitelist(
      String feature, Set<String> defaults) async {
    final existing = await DeviceCapabilityService.instance.whitelist(feature);
    final values = <String>{...defaults, ...existing};
    final labels = feature == DeviceCapabilityService.contextFeature
        ? const {
            'battery': '电量',
            'location': '位置（用于当地天气等按需信息）',
            'notifications': '最近通知内容',
            'foreground_app': '当前前台应用',
            'app_usage': '应用使用时长',
            'screen_text': '当前屏幕文字（无障碍）',
          }
        : feature == DeviceCapabilityService.proactiveFeature
            ? const {
                'app_opened': '打开或切换应用',
                'new_notification': '收到新通知',
                'screen_event': '屏幕操作事件',
              }
            : const {
                'back': '返回',
                'home': '回到桌面',
                'recents': '打开最近任务',
                'notifications': '展开通知栏',
                'click': '按坐标点击',
                'click_selector': '按文字、描述或资源 ID 点击',
                'input': '向当前输入框填入文字',
                'scroll_up': '向上滚动',
                'scroll_down': '向下滚动',
                'open_app': '打开应用',
                'close_app': '关闭应用后台进程',
                'jump_tidebot': '跳转 TideBot',
              };
    values.removeWhere((value) => !labels.containsKey(value));
    values.addAll(defaults);
    if (!mounted) return null;
    return TideDialogs.show<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setLocal) => TideDialogSurface(
          title: const Text('选择允许项目', style: TextStyle(fontFamily: 'TideFont')),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.58,
            ),
            child: Scrollbar(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in labels.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: values.contains(entry.key),
                      title: Text(entry.value,
                          style: const TextStyle(fontFamily: 'TideFont')),
                      onChanged: (checked) => setLocal(() {
                        if (checked == true) {
                          values.add(entry.key);
                        } else {
                          values.remove(entry.key);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, values),
                child: const Text('保存')),
          ],
        ),
      ),
    );
  }

  Future<void> _manageFeature(String feature, Set<String> defaults) async {
    final bots = await DBManager().getAllBots();
    if (!mounted || bots.isEmpty) {
      if (mounted) GlobalNotice.show('请先创建机器人');
      return;
    }
    final currentId = await DeviceCapabilityService.instance.boundBot(feature);
    final selectedId = await showTideSheet<String>(
      context: context,
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择授权机器人')),
            for (final bot in bots)
              ListTile(
                selected: bot['id']?.toString() == currentId,
                title: Text(bot['name']?.toString() ?? '未命名机器人'),
                subtitle: Text(bot['id']?.toString() ?? ''),
                onTap: () => Navigator.pop(context, bot['id']?.toString()),
              ),
          ],
        ),
      ),
    );
    if (selectedId == null || selectedId.isEmpty) return;
    await DeviceCapabilityService.instance.bindBot(feature, selectedId);
    final selected = await _chooseWhitelist(feature, defaults);
    if (selected == null) return;
    await DeviceCapabilityService.instance.setWhitelist(feature, selected);
    await _requestMissingSystemPermissions(feature, selected);
    await _load();
  }

  Future<void> _requestMissingSystemPermissions(
      String feature, Set<String> selected) async {
    final capability = DeviceCapabilityService.instance;
    final state = await capability.capabilityState();
    Future<void> explain(String message, Future<void> Function() open) async {
      if (!mounted) return;
      GlobalNotice.show(message, color: TideTheme.of(context).primary);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await open();
    }

    if (feature == DeviceCapabilityService.contextFeature) {
      if (selected.contains('location') &&
          state['locationPermission'] != true) {
        await Permission.location.request();
      }
      if (selected.contains('app_usage') && state['usageAccess'] != true) {
        await explain(
            '请在系统页面允许 TideBot 查看使用情况访问权限', capability.openUsageAccessSettings);
      }
      if (selected.contains('notifications') &&
          state['notificationAccess'] != true) {
        await explain('请在系统页面开启 TideBot 通知使用权',
            capability.openNotificationListenerSettings);
      }
    }
    final needsAccessibility =
        (feature == DeviceCapabilityService.contextFeature &&
                (selected.contains('screen_text') ||
                    selected.contains('foreground_app'))) ||
            (feature == DeviceCapabilityService.proactiveFeature &&
                (selected.contains('app_opened') ||
                    selected.contains('screen_event')));
    if (needsAccessibility && state['accessibility'] != true) {
      await explain(
          '请在系统无障碍页面开启“TideBot 受控自动化”', capability.openAccessibilitySettings);
    }
    if (feature == DeviceCapabilityService.proactiveFeature &&
        selected.contains('new_notification') &&
        state['notificationAccess'] != true) {
      await explain('请在系统页面开启 TideBot 通知使用权',
          capability.openNotificationListenerSettings);
    }
  }

  Widget _featureFooter(String feature, Set<String> defaults) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('启用的机器人：${_boundBotNames[feature] ?? '未绑定'}',
              style: const TextStyle(fontFamily: 'TideFont', fontSize: 13)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => _manageFeature(feature, defaults),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('管理权限'),
          ),
        ],
      );
  Future<void> _toggleExternalApi(bool value) async {
    final db = DBManager();
    final usableBots =
        _bots.where((bot) => !isBotDisabled(bot['is_disabled'])).toList();
    if (value && usableBots.isEmpty) {
      GlobalNotice.show('请先创建并启用一个机器人');
      return;
    }
    String? botId = _externalApiBotId;
    final boundBot = botId.isEmpty
        ? null
        : _bots.cast<Map<String, dynamic>>().firstWhere(
              (bot) => bot['id']?.toString() == botId,
              orElse: () => const {},
            );
    if (value &&
        (boundBot == null ||
            boundBot.isEmpty ||
            isBotDisabled(boundBot['is_disabled']))) {
      botId = await _chooseBot('选择对外提供服务的机器人');
      if (botId == null || botId.isEmpty) return;
      await db.setKV('external_api_bot_id', botId);
    }
    await db.setKV('external_api_enabled', '$value');
    bool ok = true;
    if (value) {
      ok = await ExternalApiService.instance.start();
    } else {
      await ExternalApiService.instance.stop();
    }
    await _load();
    if (mounted) {
      GlobalNotice.show(
          ok ? (value ? '外部访问服务已启动' : '外部访问服务已停止') : '外部访问服务启动失败，请查看开发日志');
    }
  }

  Future<String?> _chooseBot(String title, {String? selectedId}) =>
      showTideSheet<String>(
        context: context,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                  title: Text(title,
                      style: const TextStyle(fontFamily: 'TideFont'))),
              for (final bot in _bots.where(
                (item) => !isBotDisabled(item['is_disabled']),
              ))
                ListTile(
                  selected: bot['id']?.toString() == selectedId,
                  title: Text(bot['name']?.toString() ?? '未命名机器人',
                      style: const TextStyle(fontFamily: 'TideFont')),
                  subtitle: Text(bot['id']?.toString() ?? ''),
                  onTap: () => Navigator.pop(context, bot['id']?.toString()),
                ),
            ],
          ),
        ),
      );

  Future<void> _editExternalApi() async {
    final portController = TextEditingController(text: _externalApiPort);
    final keyController = TextEditingController(text: _externalApiKey);
    var botId = _externalApiBotId;
    var syncMessages = _externalApiSyncMessages;
    final saved = await TideDialogs.show<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setLocal) => TideDialogSurface(
          title: const Text('外部访问服务', style: TextStyle(fontFamily: 'TideFont')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '端口',
                  helperText: '默认 6666；端口占用时会自动换用可用端口。',
                ),
              ),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('服务机器人',
                    style: TextStyle(fontFamily: 'TideFont')),
                subtitle: Text(_bots
                        .where((bot) => bot['id']?.toString() == botId)
                        .map((bot) => bot['name']?.toString())
                        .firstOrNull ??
                    '请选择'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final chosen =
                      await _chooseBot('选择对外服务机器人', selectedId: botId);
                  if (chosen != null) setLocal(() => botId = chosen);
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('同步到 TideBot 聊天记录',
                    style: TextStyle(fontFamily: 'TideFont')),
                subtitle: const Text('默认开启；关闭后外部请求不写入本地聊天记录。',
                    style: TextStyle(fontFamily: 'TideFont', fontSize: 12)),
                value: syncMessages,
                onChanged: (value) => setLocal(() => syncMessages = value),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存并重启')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final port = int.tryParse(portController.text.trim());
    if (port == null ||
        port < 1024 ||
        port > 65535 ||
        keyController.text.trim().isEmpty ||
        botId.isEmpty) {
      if (mounted) GlobalNotice.show('请填写有效端口、API Key 并选择机器人');
      return;
    }
    final db = DBManager();
    await db.setKV('external_api_port', '$port');
    await db.setKV('external_api_key', keyController.text.trim());
    await db.setKV('external_api_bot_id', botId);
    await db.setKV('external_api_sync_messages', '$syncMessages');
    if (_externalApiEnabled) await ExternalApiService.instance.restart();
    await _load();
  }

  Future<void> _chooseExternalApiUrl() async {
    if (_externalApiUrls.isEmpty || !mounted) return;
    final selected = await showTideSheet<String>(
      context: context,
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择 API 地址')),
            for (final url in _externalApiUrls)
              ListTile(
                selected: url == _externalApiUrl,
                title:
                    Text(url, style: const TextStyle(fontFamily: 'TideFont')),
                trailing: url == _externalApiUrl
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, url),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await ExternalApiService.instance.setPreferredBaseUrl(selected);
    if (mounted) setState(() => _externalApiUrl = selected);
  }

  Future<void> _toggleLog(bool value) async {
    if (value) {
      await AppLogService.instance.setEnabled(true);
      if (mounted) setState(() => _logging = true);
      return;
    }
    if (AppLogService.instance.entries.isNotEmpty && mounted) {
      final save = await TideDialogs.show<bool>(
        context: context,
        builder: (ctx) => TideDialogSurface(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: TideDialogs.glassContent(context: ctx, children: [
            Text('关闭实时日志',
                textAlign: TextAlign.start,
                style: TextStyle(
                    fontFamily: 'TideFont',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: TideTheme.of(ctx).textStrong)),
            const SizedBox(height: 8),
            Text('是否保存本次日志到历史记录？',
                textAlign: TextAlign.start,
                style: TextStyle(
                    fontFamily: 'TideFont', color: TideTheme.of(ctx).textWeak)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                  child: TideDialogs.glassButton('不保存',
                      onTap: () => Navigator.pop(ctx, false),
                      color: TideTheme.of(ctx).surfaceVariant,
                      textColor: TideTheme.of(ctx).textStrong)),
              const SizedBox(width: 10),
              Expanded(
                  child: TideDialogs.glassButton('保存',
                      onTap: () => Navigator.pop(ctx, true),
                      color: TideTheme.of(ctx).primary)),
            ]),
          ]),
        ),
      );
      if (save == true) await AppLogService.instance.saveCurrent();
    }
    await AppLogService.instance.setEnabled(false);
    if (mounted) setState(() => _logging = false);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final logs = AppLogService.instance.entries;
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('高级设置',
              style: TextStyle(
                  fontFamily: 'TideFont',
                  color: theme.textStrong,
                  fontWeight: FontWeight.w700)),
          iconTheme: IconThemeData(color: theme.iconMuted),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            FrostCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('触感反馈',
                        style: TextStyle(
                            fontFamily: 'TideFont',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.textStrong)),
                    const SizedBox(height: 4),
                    Text('开启后，使用 TideBot 的按钮和卡片时会有轻微震动。',
                        style: TextStyle(
                            fontFamily: 'TideFont',
                            color: theme.textWeak,
                            fontSize: 13)),
                    Switch.adaptive(
                      value: _haptics,
                      activeThumbColor: theme.primary,
                      onChanged: (value) async {
                        await TideHaptics.setEnabled(value);
                        if (mounted) setState(() => _haptics = value);
                        if (value) TideHaptics.tap();
                      },
                    ),
                  ]),
            ),
            const SizedBox(height: 12),
            FrostCard(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('额外信息感知',
                      style: TextStyle(fontFamily: 'TideFont')),
                  subtitle: const Text('仅在你绑定机器人并授予所需权限后，按需提供设备状态。',
                      style: TextStyle(fontFamily: 'TideFont')),
                  value: _extraContext,
                  onChanged: (value) => _setProtectedToggle(
                      key: 'extra_context_enabled',
                      feature: DeviceCapabilityService.contextFeature,
                      value: value,
                      title: '授权额外信息感知',
                      description: '启用后仍需逐项选择允许的信息；信息只在与当前问题有关时注入上下文。',
                      defaultWhitelist: const {'battery', 'foreground_app'},
                      update: (v) => _extraContext = v),
                ),
                _featureFooter(DeviceCapabilityService.contextFeature,
                    const {'battery', 'foreground_app'}),
                const Divider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('操作触发主动回复',
                      style: TextStyle(fontFamily: 'TideFont')),
                  subtitle: const Text('打开应用等操作可低概率触发已绑定机器人的主动消息。',
                      style: TextStyle(fontFamily: 'TideFont')),
                  value: _operationProactive,
                  onChanged: (value) => _setProtectedToggle(
                      key: 'operation_proactive_enabled',
                      feature: DeviceCapabilityService.proactiveFeature,
                      value: value,
                      title: '授权操作触发主动回复',
                      description: '机器人只会收到你允许的触发类型。消息发送仍受主动回复设置、频率限制和绑定机器人约束。',
                      defaultWhitelist: const {'app_opened'},
                      update: (v) => _operationProactive = v),
                ),
                _featureFooter(DeviceCapabilityService.proactiveFeature,
                    const {'app_opened'}),
                // 机器人操控手机与悬浮窗功能已移除。
              ]),
            ),
            const SizedBox(height: 12),
            FrostCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('外部访问服务',
                          style: TextStyle(fontFamily: 'TideFont')),
                      subtitle: const Text(
                          '将选定机器人作为本机 OpenAI 兼容 API 服务提供给同一局域网设备。',
                          style:
                              TextStyle(fontFamily: 'TideFont', fontSize: 12)),
                      value: _externalApiEnabled,
                      activeThumbColor: theme.primary,
                      onChanged: _toggleExternalApi,
                    ),
                    if (_externalApiEnabled) ...[
                      const Divider(),
                      const Text('API Base URL',
                          style:
                              TextStyle(fontFamily: 'TideFont', fontSize: 12)),
                      const SizedBox(height: 4),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          _externalApiUrl.isEmpty
                              ? 'http://127.0.0.1:$_externalApiPort/v1'
                              : _externalApiUrl,
                          style: TextStyle(
                              fontFamily: 'TideFont',
                              fontSize: 13,
                              color: theme.primary),
                        ),
                        trailing: const Icon(Icons.copy_rounded, size: 18),
                        onTap: () {
                          final url = _externalApiUrl.isEmpty
                              ? 'http://127.0.0.1:$_externalApiPort/v1'
                              : _externalApiUrl;
                          Clipboard.setData(ClipboardData(text: url));
                          GlobalNotice.show('API Base URL 已复制');
                        },
                      ),
                      if (_externalApiUrls.length > 1)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _chooseExternalApiUrl,
                            icon:
                                const Icon(Icons.swap_horiz_rounded, size: 17),
                            label: const Text('切换地址'),
                          ),
                        ),
                      Text(
                          '模型可留空；填写时使用机器人名称。API Key：$_externalApiKey；机器人：${_bots.where((bot) => bot['id']?.toString() == _externalApiBotId).map((bot) => bot['name']?.toString()).firstOrNull ?? '未选择'}',
                          style: TextStyle(
                              fontFamily: 'TideFont',
                              color: theme.textWeak,
                              fontSize: 12)),
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                              onPressed: _editExternalApi,
                              icon:
                                  const Icon(Icons.settings_outlined, size: 17),
                              label: const Text('配置'))),
                    ] else
                      TextButton.icon(
                          onPressed: _editExternalApi,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('配置端口、API Key 和机器人')),
                  ]),
            ),
            const SizedBox(height: 12),
            FrostCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('开发日志',
                                style: TextStyle(
                                    fontFamily: 'TideFont',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: theme.textStrong)),
                            const SizedBox(height: 4),
                            Text('仅本次运行有效；退出或重启 App 后自动关闭。',
                                style: TextStyle(
                                    fontFamily: 'TideFont',
                                    color: theme.textWeak,
                                    fontSize: 13)),
                          ])),
                      Switch.adaptive(
                          value: _logging,
                          activeThumbColor: theme.primary,
                          onChanged: _toggleLog),
                    ]),
                    if (_logging) ...[
                      const SizedBox(height: 12),
                      Container(
                        height: 220,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: theme.surfaceVariant,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: theme.border)),
                        child: logs.isEmpty
                            ? Center(
                                child: Text('等待日志输出…',
                                    style: TextStyle(
                                        fontFamily: 'TideFont',
                                        color: theme.textFaint)))
                            : ListView.builder(
                                controller: _scroll,
                                itemCount: logs.length,
                                itemBuilder: (_, i) {
                                  final log = logs[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: SelectableText(
                                        '[${log.time.toIso8601String()}] ${log.level}  ${log.message}',
                                        style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            color: theme.textStrong)),
                                  );
                                },
                              ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TideDialogs.glassButton('查看历史日志',
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LogHistoryPage())),
                        color: theme.primary),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}

class LogHistoryPage extends StatelessWidget {
  const LogHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('历史日志',
              style: TextStyle(
                  fontFamily: 'TideFont',
                  color: theme.textStrong,
                  fontWeight: FontWeight.w700))),
      body: FutureBuilder<List<AppLogSession>>(
        future: AppLogService.instance.history(),
        builder: (_, snapshot) {
          final logs = snapshot.data ?? const <AppLogSession>[];
          if (snapshot.connectionState != ConnectionState.done)
            return Center(
                child: CircularProgressIndicator(color: theme.primary));
          if (logs.isEmpty)
            return Center(
                child: Text('暂无已保存日志',
                    style: TextStyle(
                        fontFamily: 'TideFont', color: theme.textFaint)));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final session = logs[i];
              return FrostCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                      child: InkWell(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                LogSessionDetailPage(session: session))),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${session.startedAt.toLocal()} · ${session.entries.length} 条${session.hasError ? ' · 含错误' : ''}',
                              style: TextStyle(
                                  fontFamily: 'TideFont',
                                  color: session.hasError
                                      ? Colors.redAccent
                                      : theme.primary,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(
                              session.entries.isEmpty
                                  ? '空日志'
                                  : session.entries.first.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'TideFont',
                                  color: theme.textStrong)),
                        ]),
                  )),
                  IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        await AppLogService.instance.deleteSession(session.id);
                        if (context.mounted)
                          Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LogHistoryPage()));
                      }),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
