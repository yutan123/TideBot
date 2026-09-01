import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:flutter/services.dart';
import 'app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'legal_pages.dart';
import 'theme.dart';
import 'chat_sidebar.dart';
import 'tool_manager_page.dart';
import 'ui_chat_list.dart';
// Chat room is opened through app navigation elsewhere.
import 'ui_create_bot.dart';
import 'ui_space_square.dart';
import 'ui_profile.dart';
import 'ui_components.dart';
import 'tide_liquid_glass.dart';
import 'app_state.dart';
import 'app_navigation.dart';
import 'db.dart';
import 'future_task_scheduler.dart';

import 'diary_service.dart';
import 'chat_event_bus.dart';
import 'global_notice.dart';
import 'ops.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ota_update.dart';
import 'ai.dart';
import 'life_schedule_service.dart';
import 'device_capability_service.dart';
import 'external_api_service.dart';
import 'persistent_service_coordinator.dart';
import 'mcp_connection_service.dart';

import 'daily_launch_animation.dart';
import 'bot_state.dart';

final TideTheme tideTheme = TideTheme();
// 悬浮窗功能已移除。

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  await tideTheme.loadFromDB();
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  await TideHaptics.load();
  await AppLogService.instance.restoreForLaunch();
  final bool hasSeenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  final bool hasAcceptedLegal =
      (prefs.getBool('legal_agreement_accepted') ?? false) &&
          (prefs.getBool('legal_age_confirmed') ?? false);
  runApp(
    TideBotApp(
      hasSeenOnboarding: hasSeenOnboarding,
      hasAcceptedLegal: hasAcceptedLegal,
    ),
  );
  unawaited(McpConnectionService.instance.connectAuto());
  if (await DBManager().getKV('external_api_enabled') == 'true') {
    unawaited(ExternalApiService.instance.start());
  }
  Timer.periodic(const Duration(minutes: 2), (_) {
    unawaited(_runDeviceEventTriggeredReply());
  });
  Future<void>.delayed(const Duration(seconds: 2), OtaUpdate.checkOncePerDay);

  // 通知回调需要在根导航器建立后才能打开对应聊天室。
  unawaited(
    OpsManager().initializeNotifications().catchError((e, st) {
      debugPrint('[notification] init skipped: $e');
    }),
  );

  // 与通知设置页共用 DB KV，避免 SharedPreferences 与数据库的状态分叉。
  // 只恢复用户此前主动开启过的运行中服务；首次启动和关闭开关后绝不自启。
  final restorePersistentService =
      (await DBManager().getKV('persistent_notification')) == 'true';
  unawaited(
    _initPersistentService(
      restoreAfterUserOptIn: restorePersistentService,
    ).catchError((e, st) {
      debugPrint('[service] init skipped: $e');
    }),
  );
}

Future<void> _initPersistentService({
  required bool restoreAfterUserOptIn,
}) async {
  try {
    final service = FlutterBackgroundService();
    const channel = AndroidNotificationChannel(
      'tide_bot_alive',
      'TideBot Core',
      importance: Importance.low,
    );
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        autoStartOnBoot: restoreAfterUserOptIn,
        isForegroundMode: true,
        notificationChannelId: 'tide_bot_alive',
        initialNotificationTitle: 'TideBot 正在运行中',
        initialNotificationContent: '后台任务可用；关闭开关或划掉应用后台即可停止',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(),
    );
    // Only restore after an explicit opt-in. The plugin persists this flag and
    // restarts its foreground service after boot/package replacement.
    if (restoreAfterUserOptIn) {
      await PersistentServiceCoordinator.instance.ensureRunning();
    }
  } catch (e) {
    debugPrint('[service] configure failed: $e');
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  Timer? heartbeat;
  var tickRunning = false;
  var futureTasksRunning = false;

  Future<void> recordError(String scope, Object error, StackTrace stack) async {
    final message = '$scope: $error';
    debugPrint('[service] $message\n$stack');
    await DBManager().setKV('persistent_service_last_error', message);
    AppLogService.instance.add('SERVICE_ERROR', message);
  }

  Future<void> runTask(String name, Future<void> Function() task) async {
    final started = DateTime.now().millisecondsSinceEpoch;
    try {
      await task();
      await DBManager().setKV('persistent_service_task_${name}_success_at',
          '${DateTime.now().millisecondsSinceEpoch}');
    } catch (error, stack) {
      await recordError(name, error, stack);
    } finally {
      await DBManager().setKV('persistent_service_task_${name}_duration_ms',
          '${DateTime.now().millisecondsSinceEpoch - started}');
    }
  }

  Future<void> tick() async {
    if (tickRunning) return;
    tickRunning = true;
    final db = DBManager();
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.setKV('persistent_service_last_tick_started_at', '$now');
      await db.setKV('persistent_service_heartbeat', '$now');
      final keepRunning = await db.getKV('persistent_notification') == 'true';
      if (!keepRunning) {
        // An exact AlarmManager wake may start this service while the user has
        // deliberately disabled continuous foreground operation. Consume due
        // tasks once before stopping; otherwise alarm wakes would immediately
        // exit at this guard and never reach the SQLite task queue.
        if (!futureTasksRunning) {
          futureTasksRunning = true;
          await runTask('future_tasks_wake', () async {
            try {
              await _runDueFutureTasks();
            } finally {
              futureTasksRunning = false;
            }
          });
        }
        heartbeat?.cancel();
        await db.setKV('persistent_service_state', 'stopped_after_task_wake');
        await db.setKV('persistent_service_heartbeat', '');
        if (service is AndroidServiceInstance) await service.stopSelf();
        return;
      }
      final isForeground = service is AndroidServiceInstance
          ? await service.isForegroundService()
          : false;
      if (!isForeground) {
        await db.setKV('persistent_service_state', 'not_foreground');
        return;
      }
      await db.setKV('persistent_service_state', 'running');
      await runTask('schedule_generation', _generateMissingLifeSchedules);
      await runTask(
          'mcp_auto_connect', McpConnectionService.instance.connectAuto);
      await runTask(
          'due_end_events', LifeScheduleService.instance.runDueEndEvents);
      await runTask('proactive_replies', _runDueProactiveReplies);
      if (!futureTasksRunning) {
        futureTasksRunning = true;
        unawaited(runTask('future_tasks', () async {
          try {
            await _runDueFutureTasks();
          } finally {
            futureTasksRunning = false;
          }
        }));
      }
      await db.setKV('persistent_service_last_tick_finished_at',
          '${DateTime.now().millisecondsSinceEpoch}');
    } catch (error, stack) {
      await recordError('tick', error, stack);
    } finally {
      tickRunning = false;
    }
  }

  service.on('stopService').listen((_) async {
    heartbeat?.cancel();
    await DBManager().setKV('persistent_service_state', 'stopped_by_user');
    await DBManager().setKV('persistent_service_heartbeat', '');
    if (service is AndroidServiceInstance) await service.stopSelf();
  });
  unawaited(() async {
    final db = DBManager();
    final restarts = int.tryParse(
            await db.getKV('persistent_service_restart_count') ?? '0') ??
        0;
    await db.setKV('persistent_service_restart_count', '${restarts + 1}');
    await db.setKV('persistent_service_started_at',
        '${DateTime.now().millisecondsSinceEpoch}');
    await db.setKV('persistent_service_state', 'starting');
    await tick();
  }());
  heartbeat = Timer.periodic(
    const Duration(minutes: 1),
    (_) => unawaited(tick()),
  );
}

Future<void> _runDueFutureTasks() async {
  final db = DBManager();
  final recovered = await db.recoverExpiredFutureTasks(
    DateTime.now().millisecondsSinceEpoch,
  );
  if (recovered > 0) {
    debugPrint('[service] recovered $recovered expired future tasks');
  }

  while (true) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final task = await db.claimDueFutureTask(now);
    if (task == null) return;
    final id = task['id']?.toString() ?? '';
    try {
      final botId = task['bot_id']?.toString() ?? '';
      final bot = botId.isEmpty ? null : await db.getBotById(botId);
      if (bot == null || isBotDisabled(bot['is_disabled'])) {
        throw StateError('目标机器人不存在或已停用');
      }
      final prompt =
          task['prompt']?.toString() ?? task['note']?.toString() ?? '';
      if (prompt.isEmpty) throw StateError('任务内容为空');

      final result = await AIManager()
          .sendMessage(
            botId: botId,
            text: '这是一个定时任务，请完成：$prompt',
            persistResponse: true,
            notifyResponse: true,
          )
          .timeout(const Duration(minutes: 2));
      if (result['success'] != true) {
        throw StateError(result['error']?.toString() ?? '任务请求失败');
      }
      await db.completeFutureTask(
        task,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (task['frequency']?.toString() == 'daily') {
        final next = await db.querySchedules(botId);
        final matches =
            next.where((item) => item['id']?.toString() == id).toList();
        if (matches.isNotEmpty) {
          await FutureTaskScheduler.schedule(matches.first);
        }
      }
    } catch (error, stack) {
      debugPrint('[service] future task $id failed: $error\n$stack');
      final failedAt = DateTime.now().millisecondsSinceEpoch;
      await db.retryFutureTask(task, error, failedAt);
      await db.setKV(
          'persistent_service_last_error', 'future_task $id: $error');
    }
  }
}

Future<void> _generateMissingLifeSchedules() async {
  try {
    await LifeScheduleService.instance.generateDueSchedules();
  } catch (e) {
    debugPrint('[schedule] generation skipped: $e');
  }
}

Future<void> _runDeviceEventTriggeredReply() async {
  final db = DBManager();
  if (await db.getKV('proactive_reply') == 'false') {
    AppLogService.instance.add('PROACTIVE', '跳过设备事件触发：用户已关闭主动回复');
    return;
  }
  final capability = DeviceCapabilityService.instance;
  final botId = await capability.boundBot(
    DeviceCapabilityService.proactiveFeature,
  );
  if (botId == null || botId.isEmpty) {
    AppLogService.instance.add('PROACTIVE', '跳过设备事件触发：未绑定机器人');
    return;
  }
  if (!await capability.isAuthorized(
    DeviceCapabilityService.proactiveFeature,
    botId,
  )) {
    AppLogService.instance.add('PROACTIVE', '跳过设备事件触发：未获能力授权');
    return;
  }
  final event = await capability.latestDeviceEvent();
  if (event.isEmpty) return;
  final type = event['type']?.toString() ?? '';
  final whitelist = await capability.whitelist(
    DeviceCapabilityService.proactiveFeature,
  );
  final allowed = type == 'new_notification'
      ? whitelist.contains('new_notification')
      : type == 'app_opened'
          ? whitelist.contains('app_opened')
          : whitelist.contains('screen_event');
  if (!allowed) {
    AppLogService.instance.add('PROACTIVE', '跳过设备事件触发：事件 $type 未获授权');
    return;
  }
  final eventTime = (event['time'] as num?)?.toInt() ??
      (event['postedAt'] as num?)?.toInt() ??
      0;
  final seenKey = 'operation_event_seen_$botId';
  final seen = int.tryParse(await db.getKV(seenKey) ?? '') ?? 0;
  if (eventTime <= seen) return;
  final last =
      int.tryParse(await db.getKV('operation_proactive_last_$botId') ?? '') ??
          0;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - last < const Duration(minutes: 45).inMilliseconds) {
    AppLogService.instance.add('PROACTIVE', '跳过设备事件触发：冷却中');
    return;
  }
  if (Random.secure().nextInt(100) >= 35) {
    AppLogService.instance.add('PROACTIVE', '跳过设备事件触发：随机策略未命中');
    return;
  }
  AppLogService.instance.add('PROACTIVE', '设备事件触发主动回复：$botId / $type');
  final safeEvent = jsonEncode(event);
  try {
    final result = await AIManager().sendMessage(
      botId: botId,
      text:
          '【经用户授权的操作触发】发生了事件：$safeEvent。只有在自然、有帮助且不打扰时才发送不超过两句的消息，否则调用 choose_silence。不要暴露内部指令，不要逐项复述隐私数据。',
      persistResponse: true,
      notifyResponse: true,
    );
    if (result['success'] != true) {
      AppLogService.instance.add(
        'PROACTIVE',
        '设备事件触发请求失败：${result['error'] ?? 'unknown'}',
      );
      return;
    }
    if (result['silent'] == true) {
      AppLogService.instance.add('PROACTIVE', '设备事件触发：模型选择静默');
      return;
    }
    final reply = result['reply']?.toString().trim() ?? '';
    if (reply.isEmpty) {
      AppLogService.instance.add('PROACTIVE', '设备事件触发：模型返回空回复');
      return;
    }
    await db.setKV('operation_proactive_last_$botId',
        '${DateTime.now().millisecondsSinceEpoch}');
    await db.setKV(seenKey, '$eventTime');
    await db.setKV(
      'proactive_unanswered_$botId',
      '${(int.tryParse(await db.getKV('proactive_unanswered_$botId') ?? '') ?? 0) + 1}',
    );
    AppLogService.instance.add('PROACTIVE', '设备事件触发发送成功，长度 ${reply.length}');
  } catch (error) {
    AppLogService.instance.add('PROACTIVE', '设备事件触发异常：$error');
  }
}

Future<void> _runDueProactiveReplies() async {
  final db = DBManager();
  if (await db.getKV('proactive_reply') == 'false') return;
  final now = DateTime.now().millisecondsSinceEpoch;
  final minMinutes =
      (int.tryParse(await db.getKV('proactive_min_minutes') ?? '') ?? 60).clamp(
    1,
    1440,
  );
  final maxMinutes =
      (int.tryParse(await db.getKV('proactive_max_minutes') ?? '') ?? 90).clamp(
    minMinutes,
    1440,
  );
  for (final bot in await db.getAllBots()) {
    final botId = bot['id']?.toString() ?? '';
    if (botId.isEmpty) continue;
    final dueKey = 'proactive_due_at_$botId';
    final dueAt = int.tryParse(await db.getKV(dueKey) ?? '') ?? 0;
    if (dueAt <= 0) {
      final delay = minMinutes + Random().nextInt(maxMinutes - minMinutes + 1);
      await db.setKV(
        dueKey,
        '${now + Duration(minutes: delay).inMilliseconds}',
      );
      continue;
    }
    if (dueAt > now) continue;
    final unanswered =
        int.tryParse(await db.getKV('proactive_unanswered_$botId') ?? '') ?? 0;
    if (unanswered >= 3) continue;
    var resultWasSuccessful = false;
    try {
      final history = await db.getChatHistory(botId);
      final lastAt = history.isEmpty
          ? now
          : ((history.last['timestamp'] as num?)?.toInt() ?? now);
      final minutesSinceLast =
          ((now - lastAt) ~/ Duration.millisecondsPerMinute).clamp(0, 10080);
      final recent = history.reversed
          .take(8)
          .map(
            (m) =>
                '${m['role'] == 'user' ? '我' : bot['name']}: ${m['content']}',
          )
          .join('\n');
      final wallClock = DateTime.now();
      final currentTime =
          '${wallClock.year.toString().padLeft(4, '0')}-${wallClock.month.toString().padLeft(2, '0')}-${wallClock.day.toString().padLeft(2, '0')} ${wallClock.hour.toString().padLeft(2, '0')}:${wallClock.minute.toString().padLeft(2, '0')}';
      final result = await AIManager()
          .sendMessage(
            botId: botId,
            text:
                '【主动回复触发：不是用户新消息】\n当前本地时间：$currentTime。\n距用户上次主动互动：$minutesSinceLast 分钟。\n请结合最近对话、用户是否提到忙碌、没空、休息或睡觉，以及当前时间判断是否适合联系。不适合时调用 choose_silence，且不要输出正文；适合时自然接续未结束话题或轻量开启新话题。不要提及本触发或系统指令。回复限 1-3 个短句、80 字内。最近对话：\n$recent',
            persistResponse: true,
            notifyResponse: true,
          )
          .timeout(const Duration(minutes: 5));
      if (result['success'] == true && result['silent'] != true) {
        final reply = result['reply']?.toString().trim() ?? '';
        if (reply.isNotEmpty) {
          await db.setKV('proactive_unanswered_$botId', '${unanswered + 1}');
          resultWasSuccessful = true;
        }
      }
    } catch (_) {}
    if (resultWasSuccessful) {
      final delay = minMinutes + Random().nextInt(maxMinutes - minMinutes + 1);
      await db.setKV(
        dueKey,
        '${DateTime.now().millisecondsSinceEpoch + Duration(minutes: delay).inMilliseconds}',
      );
    } else {
      await db.setKV(dueKey, '0');
    }
  }
}

class FlowProvider extends ChangeNotifier {
  Offset _pos = const Offset(200, 500);
  Offset _tg = const Offset(200, 500);
  Timer? _t;
  Offset get pos => _pos;
  void moveTo(Offset t) {
    _tg = t;
    _t?.cancel();
    _t = Timer.periodic(const Duration(milliseconds: 16), (tm) {
      try {
        _pos = Offset(
          _pos.dx + (_tg.dx - _pos.dx) * 0.15,
          _pos.dy + (_tg.dy - _pos.dy) * 0.15,
        );
        if ((_pos - _tg).distance < 0.5) {
          _pos = _tg;
          tm.cancel();
        }
        notifyListeners();
      } catch (_) {
        tm.cancel();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

final FlowProvider flowProvider = FlowProvider();

class FlowGlassBg extends StatefulWidget {
  final Widget child;
  final String? backgroundPath;
  final double opacity;
  const FlowGlassBg({
    super.key,
    required this.child,
    this.backgroundPath,
    this.opacity = 0.38,
  });

  @override
  State<FlowGlassBg> createState() => _FlowGlassBgState();
}

class _FlowGlassBgState extends State<FlowGlassBg> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.backgroundPath == null) {
      unawaited(TideTheme.of(context, listen: false)
          .precacheGlobalBackground(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final image = widget.backgroundPath == null
        ? theme.globalBackgroundImage
        : FileImage(File(widget.backgroundPath!));
    final path = widget.backgroundPath ?? theme.globalBackground;
    final effectiveOpacity = widget.backgroundPath == null
        ? theme.effectiveBackgroundOpacity
        : widget.opacity;
    final hasImage = image != null && (path.isEmpty || File(path).existsSync());
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!hasImage)
          ColoredBox(
            color: theme.isDark
                ? const Color(0xFF151820)
                : const Color(0xFFF3F5FA),
          ),
        if (hasImage)
          Image(
            image: image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.expand(),
          ),
        if (path.isNotEmpty)
          IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: effectiveOpacity),
            ),
          ),
        widget.child,
      ],
    );
  }
}

class TideBotApp extends StatefulWidget {
  final bool hasSeenOnboarding;
  final bool hasAcceptedLegal;
  const TideBotApp({
    super.key,
    required this.hasSeenOnboarding,
    required this.hasAcceptedLegal,
  });
  @override
  State<TideBotApp> createState() => _TideBotAppState();
}

class _TideBotAppState extends State<TideBotApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(DiaryService.instance.catchUp());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppState.updateLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(DiaryService.instance.catchUp());
      unawaited(McpConnectionService.instance.connectAuto());
    }
  }

  // 跟随系统日夜变化：手动覆盖后系统变化也触发重取色(不影响手动模式)
  @override
  void didChangePlatformBrightness() {
    tideTheme.applySystemBrightness();
  }

  @override
  Widget build(BuildContext context) {
    return TideBotThemeProvider(
      theme: tideTheme,
      child: ListenableBuilder(
        listenable: tideTheme,
        builder: (context, _) => MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'TideBot',
          debugShowCheckedModeBanner: false,
          themeMode: tideTheme.mode,
          theme: ThemeData(
            fontFamily: 'TideFont',
            brightness: Brightness.light,
            scaffoldBackgroundColor: tideTheme.bgColor,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            useMaterial3: true,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          darkTheme: ThemeData(
            fontFamily: 'TideFont',
            brightness: Brightness.dark,
            scaffoldBackgroundColor: tideTheme.bgColor,
            colorScheme: ColorScheme.dark(
              primary: tideTheme.primary,
              surface: tideTheme.surface,
              onSurface: tideTheme.textStrong,
              surfaceContainerHighest: tideTheme.surfaceVariant,
              onSurfaceVariant: tideTheme.textWeak,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: tideTheme.surfaceVariant,
              labelStyle: TextStyle(color: tideTheme.textStrong),
              hintStyle: TextStyle(color: tideTheme.textWeak),
              prefixIconColor: tideTheme.iconMuted,
              suffixIconColor: tideTheme.iconMuted,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: tideTheme.textStrong,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: tideTheme.surface,
              titleTextStyle: TextStyle(
                color: tideTheme.textStrong,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: 'TideFont',
              ),
              contentTextStyle: TextStyle(
                color: tideTheme.textStrong,
                fontFamily: 'TideFont',
              ),
            ),
            useMaterial3: true,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          builder: (context, child) => FlowGlassBg(
            child: TideEdgeBackGesture(
              child: Overlay(
                key: globalNoticeOverlayKey,
                initialEntries: [
                  OverlayEntry(
                    builder: (context) => child ?? const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          home: !widget.hasSeenOnboarding
              ? const OnboardingScreen()
              : !widget.hasAcceptedLegal
                  ? const LegalAgreementPage(requiredAcceptance: true)
                  : const DailyLaunchAnimation(child: TideMainScaffold()),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController();
  int _cur = 0;
  final _pages = [
    {
      "icon": Icons.shield_rounded,
      "t": "绝对隐私",
      "s": "零服务器架构，你的数字伴侣与记忆\n100% 安全留存本地。",
    },
    {
      "icon": Icons.api_rounded,
      "t": "配置 API",
      "s": "先去「我的」→「API 设置」添加模型，\n支持 OpenAI 兼容接口。",
    },
    {
      "icon": Icons.person_add_rounded,
      "t": "创建机器人",
      "s": "在聊天页点击右下角 +，\n定制专属 AI 伴侣的人设和风格。",
    },
    {
      "icon": Icons.auto_awesome_rounded,
      "t": "多模态交互",
      "s": "文字、语音、图片、文件——\n唤起电话式通话，体验超现实连接。",
    },
    {
      "icon": Icons.palette_rounded,
      "t": "极致美学",
      "s": "沉浸式 iOS 风格设计，\n莫兰迪配色，流光溢彩的数字陪伴。",
    },
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (c, a, s) =>
            const LegalAgreementPage(requiredAcceptance: true),
        transitionsBuilder: (c, a, s, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  void _next() {
    if (_cur < _pages.length - 1) {
      _pc.animateToPage(
        _cur + 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FlowGlassBg(
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                Expanded(
                  child: PageView.builder(
                    controller: _pc,
                    onPageChanged: (i) => setState(() => _cur = i),
                    itemCount: _pages.length,
                    itemBuilder: (c, i) => _buildP(i),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: _cur == i ? 28 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _cur == i
                              ? TideTheme.of(context).primary
                              : const Color(0xFFD4D4D8),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
                  child: BouncyTap(
                    onTap: _next,
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: LinearGradient(
                          colors: [
                            TideTheme.of(context).primary,
                            TideTheme.of(context).primaryLight,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: TideTheme.of(
                              context,
                            ).primary.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _cur == _pages.length - 1 ? '开始体验' : '下一步',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'TideFont',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildP(int i) {
    final p = _pages[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  TideTheme.of(context).primary,
                  TideTheme.of(context).primaryLight,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: TideTheme.of(context).primary.withValues(alpha: 0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(p["icon"] as IconData, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 36),
          Text(
            p["t"] as String,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              fontFamily: 'TideFont',
              color: TideTheme.of(context).textStrong,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            p["s"] as String,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              fontFamily: 'TideFont',
              color: TideTheme.of(context).textWeak,
            ),
          ),
        ],
      ),
    );
  }
}

class JellyDock extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final int unreadCount;
  const JellyDock({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadCount = 0,
  });
  @override
  State<JellyDock> createState() => _JellyDockState();
}

class _JellyDockState extends State<JellyDock>
    with SingleTickerProviderStateMixin {
  static const double _baseW = 62.0;
  static const double _growW = 70.0; // 仅轻微左右放大，主要靠整体缩放体现"鼓起来"
  late AnimationController _c;
  late Animation<double> _pos;
  late Animation<double> _w;
  late Animation<double> _scale;
  int _prev = 0;
  bool _lifting = false;

  static const _icons = [
    Icons.chat_bubble_rounded,
    Icons.space_dashboard_rounded,
    Icons.explore_rounded,
    Icons.person_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _prev = widget.currentIndex;
    // 加速移动：800ms -> 360ms
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _pos = Tween<double>(
      begin: _prev * 0.25,
      end: widget.currentIndex * 0.25,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutQuart));
    // 宽度仅微扩：移动中从 62 -> 70，落地后缩回
    _w = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: _baseW,
          end: _growW,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: _growW,
          end: _baseW,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 45,
      ),
    ]).animate(_c);
    // 整体等比例放大一点再回落(非只左右扩)，营造整体"鼓起来"的丝滑感
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.12,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 40,
      ),
    ]).animate(_c);
    _c.forward();
  }

  @override
  void didUpdateWidget(JellyDock old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _prev = old.currentIndex;
      _pos = Tween<double>(
        begin: _prev * 0.25,
        end: widget.currentIndex * 0.25,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutQuart));
      _w = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(
            begin: _baseW,
            end: _growW,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
          weight: 55,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: _growW,
            end: _baseW,
          ).chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 45,
        ),
      ]).animate(_c);
      _scale = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(
            begin: 1.0,
            end: 1.12,
          ).chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 60,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 1.12,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 40,
        ),
      ]).animate(_c);
      _c.reset();
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final isDark = theme.isDark;
    final dock = Container(
      height: 56,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: theme.hasGlobalBackground
            ? Colors.transparent
            : (isDark
                ? const Color(0xB9172A31)
                : Colors.white.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(28),
        border: theme.hasGlobalBackground
            ? null
            : Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.25),
                width: 0.5,
              ),
        boxShadow: theme.hasGlobalBackground
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: LayoutBuilder(
        builder: (ctx, cs) {
          final totalW = cs.maxWidth;
          final slotW = totalW / 4;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_pos, _w, _scale]),
                builder: (c, child) {
                  final pillX = _pos.value * totalW + (slotW - _w.value) / 2;
                  final pill = Container(
                    width: _w.value,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.hasGlobalBackground
                          ? (theme.isDark
                              ? const Color(0x261D2C33)
                              : const Color(0x24FFFFFF))
                          : theme.primary.withValues(
                              alpha: isDark ? (_lifting ? 0.42 : 0.28) : 0.18,
                            ),
                      borderRadius: BorderRadius.circular(20),
                      border: theme.hasGlobalBackground
                          ? Border.all(
                              color: Colors.white.withValues(alpha: .34))
                          : null,
                      boxShadow: theme.hasGlobalBackground
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .12),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : (isDark
                              ? [
                                  BoxShadow(
                                    color: theme.primary.withValues(
                                      alpha: _lifting ? 0.42 : 0.20,
                                    ),
                                    blurRadius: _lifting ? 18 : 10,
                                    spreadRadius: _lifting ? 1 : 0,
                                    offset: const Offset(0, -2),
                                  ),
                                ]
                              : null),
                    ),
                  );
                  final selectedPill = theme.hasGlobalBackground
                      ? TideLiquidGlass.accentCapsule(
                          radius: 20,
                          child: pill,
                        )
                      : pill;
                  return Positioned(
                    left: pillX,
                    top: isDark && _lifting ? 0 : 2,
                    child: Transform.scale(
                      scale: _scale.value * (isDark && _lifting ? 1.08 : 1.0),
                      alignment: Alignment.center,
                      child: selectedPill,
                    ),
                  );
                },
              ),
              Row(
                children: List.generate(4, (i) {
                  final act = widget.currentIndex == i;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => TideHaptics.tap(),
                      onLongPressStart: isDark
                          ? (_) => setState(() => _lifting = true)
                          : null,
                      onLongPressEnd: isDark
                          ? (_) => setState(() => _lifting = false)
                          : null,
                      onLongPressCancel: isDark
                          ? () => setState(() => _lifting = false)
                          : null,
                      onTap: () => widget.onTap(i),
                      child: Center(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              _icons[i],
                              color:
                                  act ? theme.primary : const Color(0xFFAEAEB2),
                              size: 22,
                            ),
                            if (i == 0 && widget.unreadCount > 0)
                              Positioned(
                                right: -5,
                                top: -5,
                                child: Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF3B30),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.surface,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
      child: TideLiquidGlass.dock(
        radius: 28,
        clipExpansion: const EdgeInsets.fromLTRB(12, 16, 12, 18),
        child: dock,
      ),
    );
  }
}

class TideMainScaffold extends StatefulWidget {
  const TideMainScaffold({super.key});
  @override
  State<TideMainScaffold> createState() => _TideMainScaffoldState();
}

class _TideMainScaffoldState extends State<TideMainScaffold>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int _idx = 0;
  int _unreadCount = 0;
  StreamSubscription<ChatEvent>? _chatEvents;

  final PageController _pageCtrl = PageController();
  final GlobalKey<SquarePageState> _squareKey = GlobalKey<SquarePageState>();
  final GlobalKey<ChatListPageState> _chatListKey =
      GlobalKey<ChatListPageState>();
  late final ChatSidebarController _sidebar;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sidebar = ChatSidebarController()..attach(this);
    _pages = [
      ChatListPage(key: _chatListKey, sidebar: _sidebar),
      const SpacePage(),
      SquarePage(key: _squareKey),
      const ProfilePage(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshUnread();
      _maybePromptNotificationPermission();
    });
    _chatEvents = ChatEventBus.instance.events.listen((event) {
      if (event.botId != null) _refreshUnread();
    });
  }

  Future<void> _refreshUnread() async {
    final count = await DBManager().unreadBotCount();
    if (mounted && count != _unreadCount) setState(() => _unreadCount = count);
  }

  Future<void> _maybePromptNotificationPermission() async {
    final db = DBManager();
    if (await db.getKV('notification_permission_prompt_disabled') == 'true') {
      return;
    }
    if (await Permission.notification.status == PermissionStatus.granted ||
        !mounted) return;
    var neverAsk = false;
    final authorize = await TideDialogs.show<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: TideDialogs.glassContent(
            context: context,
            children: [
              const Text(
                '开启消息通知',
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'TideFont',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '用于后台主动消息、定时任务和下载状态提醒。',
                textAlign: TextAlign.start,
                style: TextStyle(
                  color: TideTheme.of(context).textWeak,
                  height: 1.45,
                  fontFamily: 'TideFont',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  '不再提示',
                  style: TextStyle(fontFamily: 'TideFont'),
                ),
                value: neverAsk,
                onChanged: (value) =>
                    setDialogState(() => neverAsk = value ?? false),
              ),
              Row(
                children: [
                  Expanded(
                    child: TideDialogs.glassButton(
                      '取消',
                      color: TideTheme.of(context).buttonSecondary,
                      textColor: TideTheme.of(context).textStrong,
                      onTap: () => Navigator.pop(dialogContext, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TideDialogs.glassButton(
                      '去授权',
                      onTap: () => Navigator.pop(dialogContext, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (neverAsk) {
      await db.setKV('notification_permission_prompt_disabled', 'true');
    }
    if (authorize == true) await Permission.notification.request();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshUnread();
  }

  void _onDockTap(int i) {
    if (_idx != i) {
      setState(() => _idx = i);
      if (i == 0) {
        _chatListKey.currentState?.load();
        Future<void>.delayed(const Duration(milliseconds: 350), _refreshUnread);
      }
      _pageCtrl.animateToPage(
        i,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatEvents?.cancel();
    _pageCtrl.dispose();
    _sidebar.dispose();
    flowProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final theme = TideTheme.of(context);
    return FlowGlassBg(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          children: [
            IndexedStack(index: _idx, children: _pages),
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPadding + 24,
              child: JellyDock(
                currentIndex: _idx,
                unreadCount: _unreadCount,
                onTap: _onDockTap,
              ),
            ),
            // 聊天列表创建机器人悬浮球
            if (_idx == 0)
              Positioned(
                right: 20,
                bottom: bottomPadding + 76,
                child: BouncyTap(
                  onTap: () async {
                    final r = await Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (c, a, s) => const CreateBotPage(),
                        transitionsBuilder: (c, a, s, child) => SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.3),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: a,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                          child: FadeTransition(opacity: a, child: child),
                        ),
                      ),
                    );
                    if (r == true) _chatListKey.currentState?.load();
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [theme.primary, theme.primaryLight],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            // 广场发布悬浮球
            if (_idx == 2)
              Positioned(
                right: 20,
                bottom: bottomPadding + 76,
                child: BouncyTap(
                  onTap: () => _squareKey.currentState?.publishFeed(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [theme.primary, theme.primaryLight],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ListenableBuilder(
              listenable: _sidebar,
              builder: (context, _) {
                final bot = _sidebar.bot;
                final progress = _sidebar.progress;
                if (!_sidebar.isOpen || bot == null || progress == null) {
                  return const SizedBox.shrink();
                }
                return Positioned.fill(
                  child: ChatSidebar(
                    bot: bot,
                    progress: progress,
                    onClose: () => unawaited(_sidebar.close()),
                    onDragUpdate: (details) => _sidebar.updateDrag(
                      details.delta.dx,
                      MediaQuery.sizeOf(context).width * .86,
                    ),
                    onDragEnd: (details) =>
                        _sidebar.endDrag(details.velocity.pixelsPerSecond.dx),
                    onOpenManager: (kind) async {
                      await _sidebar.close();
                      if (!mounted) return;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ToolManagerPage(
                          kind: kind == 'skill'
                              ? ToolManagerKind.skill
                              : ToolManagerKind.mcp,
                        ),
                      ));
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
