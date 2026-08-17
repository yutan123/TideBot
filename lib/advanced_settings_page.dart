import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_log_service.dart';
import 'db.dart';
import 'device_capability_service.dart';
import 'global_notice.dart';
import 'log_session_detail_page.dart';
import 'theme.dart';
import 'ui_components.dart';

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({super.key});

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage>
    with WidgetsBindingObserver {
  bool _logging = AppLogService.instance.enabled;
  bool _haptics = false;
  bool _botUiEditing = false;
  bool _extraContext = false;
  bool _operationProactive = false;
  bool _deviceControl = false;
  String _actionPolicy = DeviceCapabilityService.actionPolicyAsk;
  bool _overlayEnabled = false;
  bool _overlayPermissionPending = false;
  final Map<String, String> _boundBotNames = {};
  Timer? _ticker;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    final botNames = <String, String>{};
    for (final feature in const [
      DeviceCapabilityService.contextFeature,
      DeviceCapabilityService.proactiveFeature,
      DeviceCapabilityService.controlFeature,
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
    final policy = await capability.actionPolicy();
    final overlayIntent = prefs.getBool('assistant_overlay_enabled') ?? false;
    final botUiEditing = prefs.getBool('bot_ui_editing_enabled') ?? false;
    final hasOverlayPermission = await capability.overlayEnabled();
    final overlayRunning = await capability.overlayRunning();
    final overlay = overlayIntent && hasOverlayPermission && overlayRunning;
    if (overlayIntent && !hasOverlayPermission) {
      await prefs.setBool('assistant_overlay_enabled', false);
    }
    final pending =
        prefs.getBool('assistant_overlay_permission_pending') ?? false;
    if (mounted) {
      setState(() {
        _logging = enabled;
        _haptics = prefs.getBool('tide_haptics_enabled') ?? true;
        _botUiEditing = botUiEditing;
        _extraContext = prefs.getBool('extra_context_enabled') ?? false;
        _operationProactive =
            prefs.getBool('operation_proactive_enabled') ?? false;
        _deviceControl = prefs.getBool('device_control_enabled') ?? false;
        _actionPolicy = policy;
        _overlayEnabled = overlay;
        _overlayPermissionPending = pending;
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
    if (feature == DeviceCapabilityService.contextFeature) {
      if (selected.contains('location')) await Permission.location.request();
      if (selected.contains('app_usage')) {
        await capability.openUsageAccessSettings();
      }
      if (selected.contains('notifications')) {
        await capability.openNotificationListenerSettings();
      }
      if ((selected.contains('screen_text') ||
              selected.contains('foreground_app')) &&
          !await capability.accessibilityEnabled()) {
        await capability.openAccessibilitySettings();
      }
    }
    if (feature == DeviceCapabilityService.proactiveFeature &&
        (selected.contains('app_opened') ||
            selected.contains('screen_event')) &&
        !await capability.accessibilityEnabled()) {
      await capability.openAccessibilitySettings();
    }
    if (feature == DeviceCapabilityService.proactiveFeature &&
        selected.contains('new_notification')) {
      await capability.openNotificationListenerSettings();
    }
    if (feature == DeviceCapabilityService.controlFeature &&
        !await capability.accessibilityEnabled()) {
      if (!mounted) return;
      final openSettings = await TideDialogs.show<bool>(
            context: context,
            builder: (ctx) => TideDialogSurface(
              title: const Text('需要无障碍授权',
                  style: TextStyle(fontFamily: 'TideFont')),
              content: const Text(
                  '仅在 Android 系统设置中单独启用 TideBot 受控自动化后，已确认的操作才能执行。',
                  style: TextStyle(fontFamily: 'TideFont')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('稍后')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('打开系统设置')),
              ],
            ),
          ) ??
          false;
      if (openSettings) await capability.openAccessibilitySettings();
    }
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
                    selected.contains('screen_event'))) ||
            feature == DeviceCapabilityService.controlFeature;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _overlayPermissionPending) {
      unawaited(_resumeOverlayAfterPermission());
    }
  }

  Future<void> _resumeOverlayAfterPermission() async {
    final capability = DeviceCapabilityService.instance;
    if (!await capability.overlayEnabled()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('assistant_overlay_permission_pending', false);
    _overlayPermissionPending = false;
    await _startOverlay();
  }

  Future<void> _startOverlay() async {
    final capability = DeviceCapabilityService.instance;
    var botId =
        await capability.boundBot(DeviceCapabilityService.controlFeature);
    final bots = await DBManager().getAllBots();
    if ((botId == null || botId.isEmpty) && bots.isNotEmpty) {
      botId = bots.first['id']?.toString();
    }
    final bot = bots.cast<Map<String, dynamic>>().firstWhere(
          (item) => item['id']?.toString() == botId,
          orElse: () => const {},
        );
    final ok = await capability.setAssistantOverlay(
      enabled: true,
      botId: botId,
      botName: bot['name']?.toString(),
      avatarPath: bot['avatar']?.toString(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('assistant_overlay_enabled', ok);
    if (ok && botId != null && botId.isNotEmpty) {
      await prefs.setString('assistant_overlay_bot_id', botId);
    }
    if (mounted) setState(() => _overlayEnabled = ok);
  }

  Future<void> _toggleOverlay(bool value) async {
    final capability = DeviceCapabilityService.instance;
    final prefs = await SharedPreferences.getInstance();
    if (!value) {
      await prefs.setBool('assistant_overlay_enabled', false);
      await prefs.setBool('assistant_overlay_permission_pending', false);
      _overlayPermissionPending = false;
      await capability.setAssistantOverlay(enabled: false);
      if (mounted) setState(() => _overlayEnabled = false);
      return;
    }
    if (!await capability.overlayEnabled()) {
      if (!mounted) return;
      final open = await TideDialogs.show<bool>(
            context: context,
            builder: (ctx) => TideDialogSurface(
              title: const Text('允许机器人悬浮窗',
                  style: TextStyle(fontFamily: 'TideFont')),
              content: const Text(
                  '接下来会打开 Android 的“显示在其他应用上层”页面。请选择 TideBot 并开启允许；返回 TideBot 后，悬浮窗会自动启动，无需再次拨动开关。',
                  style: TextStyle(fontFamily: 'TideFont')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('前往授权')),
              ],
            ),
          ) ??
          false;
      if (!open) return;
      await prefs.setBool('assistant_overlay_permission_pending', true);
      _overlayPermissionPending = true;
      await capability.openOverlaySettings();
      return;
    }
    await _startOverlay();
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
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final logs = AppLogService.instance.entries;
    return Scaffold(
      backgroundColor: theme.bgColor,
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('机器人修改主题',
                  style: TextStyle(fontFamily: 'TideFont')),
              subtitle: const Text(
                  '默认关闭。开启后，机器人仅在你明确要求时可调用 UI 外观工具；不会改动功能、权限、数据或安全设置。',
                  style: TextStyle(fontFamily: 'TideFont', fontSize: 12)),
              value: _botUiEditing,
              activeThumbColor: theme.primary,
              onChanged: (value) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('bot_ui_editing_enabled', value);
                if (mounted) setState(() => _botUiEditing = value);
              },
            ),
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
              const Divider(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('机器人操控手机',
                    style: TextStyle(fontFamily: 'TideFont')),
                subtitle: const Text('需要无障碍授权；每次实际执行前必须展示确认。',
                    style: TextStyle(fontFamily: 'TideFont')),
                value: _deviceControl,
                onChanged: (value) => _setProtectedToggle(
                    key: 'device_control_enabled',
                    feature: DeviceCapabilityService.controlFeature,
                    value: value,
                    title: '授权机器人操控手机',
                    description: '启用不会自动授予控制。功能须绑定机器人、限制动作白名单，并对每次实际操作要求明确确认。',
                    defaultWhitelist: const {
                      'back',
                      'home',
                      'open_app',
                      'click_selector'
                    },
                    update: (v) => _deviceControl = v),
              ),
              _featureFooter(DeviceCapabilityService.controlFeature,
                  const {'back', 'home', 'open_app', 'click_selector'}),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  const options = {
                    DeviceCapabilityService.actionPolicyOff: '关闭',
                    DeviceCapabilityService.actionPolicyAsk: '每次询问',
                    DeviceCapabilityService.actionPolicyAllow: '允许',
                  };
                  final value = await showTideSheet<String>(
                    context: context,
                    height: 300,
                    child: SafeArea(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        children: [
                          const ListTile(
                            title: Text('机器人执行操作',
                                style: TextStyle(
                                    fontFamily: 'TideFont',
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text('选择机器人对已授权白名单操作的执行策略。',
                                style: TextStyle(fontFamily: 'TideFont')),
                          ),
                          for (final entry in options.entries)
                            ListTile(
                              leading: Icon(entry.key == _actionPolicy
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded),
                              title: Text(entry.value,
                                  style:
                                      const TextStyle(fontFamily: 'TideFont')),
                              onTap: () => Navigator.pop(context, entry.key),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (value == null) return;
                  await DeviceCapabilityService.instance.setActionPolicy(value);
                  if (mounted) setState(() => _actionPolicy = value);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '机器人执行操作',
                    helperText: '关闭：拒绝执行；每次询问：逐步确认；允许：白名单内直接执行。',
                    suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  child: Text(
                    const {
                          DeviceCapabilityService.actionPolicyOff: '关闭',
                          DeviceCapabilityService.actionPolicyAsk: '每次询问',
                          DeviceCapabilityService.actionPolicyAllow: '允许',
                        }[_actionPolicy] ??
                        '每次询问',
                    style: const TextStyle(fontFamily: 'TideFont'),
                  ),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('机器人悬浮窗',
                    style: TextStyle(fontFamily: 'TideFont')),
                subtitle: const Text('在其他应用上显示机器人头像和快捷输入栏。',
                    style: TextStyle(fontFamily: 'TideFont')),
                value: _overlayEnabled,
                onChanged: _toggleOverlay,
              ),
            ]),
          ),
          FrostCard(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    );
  }
}

class LogHistoryPage extends StatelessWidget {
  const LogHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
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
