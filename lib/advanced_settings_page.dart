import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_log_service.dart';
import 'db.dart';
import 'device_capability_service.dart';
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
  bool _deviceControl = false;
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
    if (mounted) {
      setState(() {
        _logging = enabled;
        _haptics = prefs.getBool('tide_haptics_enabled') ?? true;
        _extraContext = prefs.getBool('extra_context_enabled') ?? false;
        _operationProactive =
            prefs.getBool('operation_proactive_enabled') ?? false;
        _deviceControl = prefs.getBool('device_control_enabled') ?? false;
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
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
