import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'theme.dart';
import 'ui_chat_list.dart';
import 'ui_create_bot.dart';
import 'ui_space_square.dart';
import 'ui_profile.dart';
import 'ui_components.dart';
import 'app_state.dart';
import 'app_navigation.dart';
import 'db.dart';
import 'global_notice.dart';
import 'ops.dart';
import 'ota_update.dart';
import 'ai.dart';
import 'daily_launch_animation.dart';

final TideTheme tideTheme = TideTheme();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  await tideTheme.loadFromDB();
  await TideHaptics.load();
  await AppLogService.instance.restoreForLaunch();
  final bool hasSeenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  runApp(TideBotApp(hasSeenOnboarding: hasSeenOnboarding));
  Future<void>.delayed(const Duration(seconds: 2), OtaUpdate.checkOncePerDay);

  // 通知回调需要在根导航器建立后才能打开对应聊天室。
  unawaited(OpsManager().initializeNotifications().catchError((e, st) {
    debugPrint('[notification] init skipped: $e');
  }));

  // 与通知设置页共用 DB KV，避免 SharedPreferences 与数据库的状态分叉。
  // 只恢复用户此前主动开启过的运行中服务；首次启动和关闭开关后绝不自启。
  final restorePersistentService =
      (await DBManager().getKV('persistent_notification')) == 'true';
  unawaited(_initPersistentService(
    restoreAfterUserOptIn: restorePersistentService,
  ).catchError((e, st) {
    debugPrint('[service] init skipped: $e');
  }));
}

Future<void> _initPersistentService({
  required bool restoreAfterUserOptIn,
}) async {
  try {
    final service = FlutterBackgroundService();
    const channel = AndroidNotificationChannel('tide_bot_alive', 'TideBot Core',
        importance: Importance.low);
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'tide_bot_alive',
        initialNotificationTitle: 'TideBot 正在运行中',
        initialNotificationContent: '后台任务可用；关闭开关或划掉应用后台即可停止',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(),
    );
    // 仅恢复曾由用户主动开启的服务；autoStart 保持 false，避免安装后或
    // 用户关闭开关后由系统/应用擅自启动。
    if (restoreAfterUserOptIn) {
      await service.startService();
    }
  } catch (e) {
    debugPrint('[service] configure failed: $e');
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  service.on('stopService').listen((_) async {
    if (service is AndroidServiceInstance) await service.stopSelf();
  });
  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      final due = await DBManager()
          .dueFutureTasks(DateTime.now().millisecondsSinceEpoch);
      for (final task in due) {
        final id = task['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await DBManager().updateFutureTask(id, {'status': 'running'});
        final botId = task['bot_id']?.toString() ?? '';
        final prompt =
            task['prompt']?.toString() ?? task['note']?.toString() ?? '';
        if (botId.isEmpty || prompt.isEmpty) continue;
        try {
          final result = await AIManager().sendMessage(
              botId: botId,
              text: '这是一个定时任务，请完成：$prompt',
              persistResponse: true);
          final answer = result['reply']?.toString() ?? '';
          await OpsManager().showSystemNotification(
              id: id.hashCode,
              title: task['title']?.toString() ?? '未来任务完成',
              body: answer.isEmpty ? '任务已执行' : answer,
              botId: botId);
          if (task['frequency']?.toString() == 'daily') {
            final next = DateTime.now()
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch;
            await DBManager()
                .updateFutureTask(id, {'run_at': next, 'status': 'pending'});
          } else {
            await DBManager().deleteFutureTask(id);
          }
        } catch (_) {
          await DBManager().updateFutureTask(id, {'status': 'pending'});
        }
      }
    } catch (_) {}
  });
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
        _pos = Offset(_pos.dx + (_tg.dx - _pos.dx) * 0.15,
            _pos.dy + (_tg.dy - _pos.dy) * 0.15);
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

class FlowGlassBg extends StatelessWidget {
  final Widget child;
  const FlowGlassBg({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Stack(children: [
      // 日间是柔和蓝白纸感，夜间是深蓝灰空间感；两者使用不同亮度层级。
      Container(
          decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.isDark
              ? [
                  const Color(0xFF10151D),
                  const Color(0xFF16212D),
                  const Color(0xFF111923)
                ]
              : [
                  const Color(0xFFF8FAFF),
                  const Color(0xFFF0F4FB),
                  const Color(0xFFF7F3FA)
                ],
        ),
      )),
      // Static background layers keep the page GPU-friendly. The previous
      // 16ms FlowProvider rebuild repainted the whole app continuously.
      Positioned(
        left: -80,
        top: 70,
        child: IgnorePointer(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                theme.primaryLight
                    .withValues(alpha: theme.isDark ? 0.08 : 0.16),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ),

      child,
    ]);
  }
}

class TideBotApp extends StatefulWidget {
  final bool hasSeenOnboarding;
  const TideBotApp({super.key, required this.hasSeenOnboarding});
  @override
  State<TideBotApp> createState() => _TideBotAppState();
}

class _TideBotAppState extends State<TideBotApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppState.updateLifecycle(state);
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
                scrolledUnderElevation: 0),
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
                scrolledUnderElevation: 0),
            dialogTheme: DialogThemeData(
              backgroundColor: tideTheme.surface,
              titleTextStyle: TextStyle(
                  color: tideTheme.textStrong,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'TideFont'),
              contentTextStyle: TextStyle(
                  color: tideTheme.textStrong, fontFamily: 'TideFont'),
            ),
            useMaterial3: true,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          builder: (context, child) => TideEdgeBackGesture(
            child: Overlay(
              key: globalNoticeOverlayKey,
              initialEntries: [
                OverlayEntry(
                  builder: (context) => child ?? const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          home: widget.hasSeenOnboarding
              ? const DailyLaunchAnimation(child: TideMainScaffold())
              : const OnboardingScreen(),
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
      "s": "零服务器架构，你的数字伴侣与记忆\n100% 安全留存本地。"
    },
    {
      "icon": Icons.api_rounded,
      "t": "配置 API",
      "s": "先去「我的」→「API 设置」添加模型，\n支持 OpenAI 兼容接口。"
    },
    {
      "icon": Icons.person_add_rounded,
      "t": "创建机器人",
      "s": "在聊天页点击右下角 +，\n定制专属 AI 伴侣的人设和风格。"
    },
    {
      "icon": Icons.auto_awesome_rounded,
      "t": "多模态交互",
      "s": "文字、语音、图片、文件——\n唤起电话式通话，体验超现实连接。"
    },
    {
      "icon": Icons.palette_rounded,
      "t": "极致美学",
      "s": "沉浸式 iOS 风格设计，\n莫兰迪配色，流光溢彩的数字陪伴。"
    },
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        PageRouteBuilder(
            pageBuilder: (c, a, s) => const TideMainScaffold(),
            transitionsBuilder: (c, a, s, child) =>
                FadeTransition(opacity: a, child: child),
            transitionDuration: const Duration(milliseconds: 600)));
  }

  void _next() {
    if (_cur < _pages.length - 1) {
      _pc.animateToPage(_cur + 1,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: FlowGlassBg(
              child: SafeArea(
                  child: Column(children: [
        const SizedBox(height: 40),
        Expanded(
            child: PageView.builder(
          controller: _pc,
          onPageChanged: (i) => setState(() => _cur = i),
          itemCount: _pages.length,
          itemBuilder: (c, i) => _buildP(i),
        )),
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
                              : const Color(0xFFD4D4D8)),
                    )),
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
                gradient: LinearGradient(colors: [
                  TideTheme.of(context).primary,
                  TideTheme.of(context).primaryLight
                ]),
                boxShadow: [
                  BoxShadow(
                      color:
                          TideTheme.of(context).primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ],
              ),
              child: Center(
                  child: Text(_cur == _pages.length - 1 ? '开始体验' : '下一步',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'TideFont'))),
            ),
          ),
        ),
      ]))));

  Widget _buildP(int i) {
    final p = _pages[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [
                  TideTheme.of(context).primary,
                  TideTheme.of(context).primaryLight
                ]),
                boxShadow: [
                  BoxShadow(
                      color:
                          TideTheme.of(context).primary.withValues(alpha: 0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10))
                ]),
            child: Icon(p["icon"] as IconData, color: Colors.white, size: 44)),
        const SizedBox(height: 36),
        Text(p["t"] as String,
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                fontFamily: 'TideFont',
                color: TideTheme.of(context).textStrong)),
        const SizedBox(height: 14),
        Text(p["s"] as String,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                height: 1.5,
                fontFamily: 'TideFont',
                color: TideTheme.of(context).textWeak)),
      ]),
    );
  }
}

class JellyDock extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  const JellyDock({super.key, required this.currentIndex, required this.onTap});
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

  static const _icons = [
    Icons.chat_bubble_rounded,
    Icons.space_dashboard_rounded,
    Icons.explore_rounded,
    Icons.person_rounded
  ];

  @override
  void initState() {
    super.initState();
    _prev = widget.currentIndex;
    // 加速移动：800ms -> 360ms
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 360));
    _pos = Tween<double>(begin: _prev * 0.25, end: widget.currentIndex * 0.25)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutQuart));
    // 宽度仅微扩：移动中从 62 -> 70，落地后缩回
    _w = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: _baseW, end: _growW)
              .chain(CurveTween(curve: Curves.easeOutCubic)),
          weight: 55),
      TweenSequenceItem(
          tween: Tween(begin: _growW, end: _baseW)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 45),
    ]).animate(_c);
    // 整体等比例放大一点再回落(非只左右扩)，营造整体"鼓起来"的丝滑感
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.12)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 60),
      TweenSequenceItem(
          tween: Tween(begin: 1.12, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 40),
    ]).animate(_c);
    _c.forward();
  }

  @override
  void didUpdateWidget(JellyDock old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _prev = old.currentIndex;
      _pos = Tween<double>(begin: _prev * 0.25, end: widget.currentIndex * 0.25)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutQuart));
      _w = TweenSequence<double>([
        TweenSequenceItem(
            tween: Tween(begin: _baseW, end: _growW)
                .chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 55),
        TweenSequenceItem(
            tween: Tween(begin: _growW, end: _baseW)
                .chain(CurveTween(curve: Curves.easeInOutCubic)),
            weight: 45),
      ]).animate(_c);
      _scale = TweenSequence<double>([
        TweenSequenceItem(
            tween: Tween(begin: 1.0, end: 1.12)
                .chain(CurveTween(curve: Curves.easeOutBack)),
            weight: 60),
        TweenSequenceItem(
            tween: Tween(begin: 1.12, end: 1.0)
                .chain(CurveTween(curve: Curves.easeInOutCubic)),
            weight: 40),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25), width: 0.5),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 4))
              ],
            ),
            child: LayoutBuilder(builder: (ctx, cs) {
              final totalW = cs.maxWidth;
              final slotW = totalW / 4;
              return Stack(children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_pos, _w, _scale]),
                  builder: (c, child) {
                    final pillX = _pos.value * totalW + (slotW - _w.value) / 2;
                    return Positioned(
                      left: pillX,
                      top: 0,
                      child: Transform.scale(
                        scale: _scale.value,
                        alignment: Alignment.center,
                        child: Container(
                          width: _w.value,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
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
                      onTap: () => widget.onTap(i),
                      child: Center(
                          child: Icon(_icons[i],
                              color:
                                  act ? theme.primary : const Color(0xFFAEAEB2),
                              size: 22)),
                    ));
                  }),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class TideMainScaffold extends StatefulWidget {
  const TideMainScaffold({super.key});
  @override
  State<TideMainScaffold> createState() => _TideMainScaffoldState();
}

class _TideMainScaffoldState extends State<TideMainScaffold> {
  int _idx = 0;
  final PageController _pageCtrl = PageController();
  final GlobalKey<SquarePageState> _squareKey = GlobalKey<SquarePageState>();
  final GlobalKey<ChatListPageState> _chatListKey =
      GlobalKey<ChatListPageState>();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      ChatListPage(key: _chatListKey),
      const SpacePage(),
      SquarePage(key: _squareKey),
      const ProfilePage()
    ];
  }

  void _onDockTap(int i) {
    if (_idx != i) {
      setState(() => _idx = i);
      _pageCtrl.animateToPage(i,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
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
        body: Stack(children: [
          IndexedStack(
            index: _idx,
            children: _pages,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPadding + 24,
            child: JellyDock(currentIndex: _idx, onTap: _onDockTap),
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
                          transitionsBuilder: (c, a, s, child) =>
                              SlideTransition(
                                  position: Tween<Offset>(
                                          begin: const Offset(0, 0.3),
                                          end: Offset.zero)
                                      .animate(CurvedAnimation(
                                          parent: a,
                                          curve: Curves.easeOutCubic)),
                                  child: FadeTransition(
                                      opacity: a, child: child))));
                  if (r == true) _chatListKey.currentState?.load();
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [theme.primary, theme.primaryLight]),
                    boxShadow: [
                      BoxShadow(
                          color: theme.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 26),
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
                        colors: [theme.primary, theme.primaryLight]),
                    boxShadow: [
                      BoxShadow(
                          color: theme.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 26),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
