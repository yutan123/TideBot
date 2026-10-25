import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'device_capability_service.dart';
import 'global_notice.dart';
import 'native_background_coordinator.dart';
import 'theme.dart';
import 'ui_components.dart';

class PermissionManagementPage extends StatefulWidget {
  const PermissionManagementPage({super.key});
  @override
  State<PermissionManagementPage> createState() =>
      _PermissionManagementPageState();
}

class _PermissionManagementPageState extends State<PermissionManagementPage>
    with WidgetsBindingObserver {
  final Map<Permission, PermissionStatus> _statuses = {};
  Map<String, dynamic> _native = {};
  bool _loading = true;
  bool _requesting = false;
  int _refreshGeneration = 0;

  Permission get _photos => (_native['sdkInt'] as int? ?? 33) >= 33
      ? Permission.photos
      : Permission.storage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_refreshGeneration;
    try {
      final native = await DeviceCapabilityService.instance.capabilityState();
      final values = <Permission, PermissionStatus>{};
      for (final permission in [
        Permission.notification,
        Permission.locationWhenInUse,
        Permission.ignoreBatteryOptimizations,
        Permission.microphone,
        Permission.camera,
        Permission.photos,
        Permission.storage,
        Permission.scheduleExactAlarm
      ]) {
        values[permission] = await permission.status;
      }
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _native = native;
        _statuses.addAll(values);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      GlobalNotice.show('无法读取权限状态，请稍后重试');
    }
  }

  Future<void> _request(Permission permission) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final status = await permission.status;
      if (permission == Permission.ignoreBatteryOptimizations ||
          permission == Permission.scheduleExactAlarm) {
        await DeviceCapabilityService.instance.openPermissionSettings(
            permission == Permission.ignoreBatteryOptimizations
                ? 'battery'
                : 'alarm');
      } else if (status.isPermanentlyDenied ||
          status.isRestricted ||
          status.isLimited) {
        if (!await openAppSettings()) GlobalNotice.show('无法打开应用设置，请手动进入系统设置');
      } else {
        final result = await permission.request();
        if (!result.isGranted && !result.isLimited) {
          if (result.isPermanentlyDenied ||
              permission == Permission.notification ||
              permission == Permission.ignoreBatteryOptimizations ||
              permission == Permission.scheduleExactAlarm) {
            await DeviceCapabilityService.instance.openPermissionSettings(
                permission == Permission.ignoreBatteryOptimizations
                    ? 'battery'
                    : permission == Permission.scheduleExactAlarm
                        ? 'alarm'
                        : 'app');
          } else {
            GlobalNotice.show('尚未授权，可再次点击申请');
          }
        }
      }
      await _refresh();
      if (permission == Permission.scheduleExactAlarm) {
        await NativeBackgroundCoordinator.synchronize();
      }
    } catch (_) {
      GlobalNotice.show('无法打开授权页面，请在系统应用设置中授权');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Widget _row(IconData icon, String title, String description,
      {Permission? permission,
      String? nativeKey,
      Future<void> Function()? open}) {
    final theme = TideTheme.of(context);
    final status = _statuses[permission];
    final granted = nativeKey == null
        ? status?.isGranted == true
        : _native[nativeKey] == true;
    final limited = status?.isLimited == true;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: theme.primary, size: 23),
        ),
        title: Text(title,
            style: TextStyle(fontFamily: 'TideFont', color: theme.textStrong)),
        subtitle: Text(description,
            style: TextStyle(
                fontFamily: 'TideFont',
                fontSize: 12,
                color: theme.textWeak,
                height: 1.5)),
        trailing: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              granted
                  ? Icons.check_circle_rounded
                  : limited
                      ? Icons.check_circle_outline_rounded
                      : Icons.chevron_right_rounded,
              color: granted || limited ? theme.primary : theme.textWeak),
          const SizedBox(height: 4),
          Text(
              _loading
                  ? '读取中'
                  : granted
                      ? '已授权'
                      : limited
                          ? '部分授权'
                          : '去授权',
              style: TextStyle(
                  fontFamily: 'TideFont',
                  fontSize: 11,
                  color: granted || limited ? theme.primary : theme.textWeak)),
        ]),
        onTap: _loading || _requesting || granted
            ? null
            : () async {
                if (permission != null) {
                  await _request(permission);
                } else {
                  try {
                    await open?.call();
                    await _refresh();
                  } catch (_) {
                    GlobalNotice.show('无法打开系统授权页面');
                  }
                }
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TideBackground(
        child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          title: const Text('权限管理', style: TextStyle(fontFamily: 'TideFont')),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded),
              onPressed: () => Navigator.pop(context)),
          actions: [
            IconButton(
                tooltip: '刷新权限状态',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded))
          ]),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                child: Text('权限由你掌控\n按需开启，返回此页后自动更新授权状态。',
                    style: TextStyle(
                        fontFamily: 'TideFont',
                        color: theme.textWeak,
                        height: 1.7))),
            FrostCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  _row(Icons.notifications_outlined, '通知权限', '接收机器人未读消息和运行状态通知',
                      permission: Permission.notification),
                  _row(Icons.location_on_outlined, '定位权限',
                      '为已开启的位置上下文提供当地信息，仅在使用时访问',
                      permission: Permission.locationWhenInUse),
                  _row(Icons.battery_saver_outlined, '忽略电池优化',
                      '减少系统对后台陪伴与定时任务的限制',
                      permission: Permission.ignoreBatteryOptimizations),
                  _row(Icons.mic_none_rounded, '麦克风权限', '录制语音消息和进行语音通话',
                      permission: Permission.microphone),
                  _row(Icons.camera_alt_outlined, '摄像头权限', '进行视频通话和拍摄画面',
                      permission: Permission.camera),
                  _row(Icons.photo_library_outlined, '相册权限',
                      '选择头像、聊天图片和背景；部分授权仅可访问选中的照片',
                      permission: _photos),
                ])),
            Padding(
                padding: const EdgeInsets.fromLTRB(8, 24, 8, 10),
                child: Text('按需开启的特殊权限',
                    style: TextStyle(
                        fontFamily: 'TideFont',
                        fontWeight: FontWeight.w600,
                        color: theme.textStrong))),
            FrostCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  _row(Icons.install_mobile_rounded, '安装应用更新',
                      '仅用于你手动确认后的 TideBot APK 更新安装',
                      nativeKey: 'installPackages',
                      open: () => DeviceCapabilityService.instance
                          .openPermissionSettings('install')),
                  _row(Icons.alarm_rounded, '精确闹钟', '让已设置的后台任务在指定时间唤醒',
                      permission: Permission.scheduleExactAlarm),
                  _row(Icons.query_stats_rounded, '使用情况访问',
                      '仅用于高级设置中主动开启的应用使用时长上下文',
                      nativeKey: 'usageAccess',
                      open: DeviceCapabilityService
                          .instance.openUsageAccessSettings),
                  _row(Icons.mark_chat_unread_outlined, '通知使用权',
                      '读取其他应用通知，用于主动开启的通知上下文与通知触发；与发送通知权限不同',
                      nativeKey: 'notificationAccess',
                      open: DeviceCapabilityService
                          .instance.openNotificationListenerSettings),
                ])),
          ]),
    ));
  }
}
