import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'theme.dart';
import 'ui_chat_list.dart';
import 'ui_create_bot.dart';
import 'ui_space_square.dart';
import 'ui_profile.dart';
import 'ui_components.dart';

final TideTheme tideTheme = TideTheme();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  await tideTheme.loadFromDB();
  final bool hasSeenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  runApp(TideBotApp(hasSeenOnboarding: hasSeenOnboarding));
  await _initPersistentService();
}

Future<void> _initPersistentService() async {
  final service = FlutterBackgroundService();
  const channel = AndroidNotificationChannel('tide_bot_alive', 'TideBot Core', importance: Importance.low);
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, autoStart: true, isForegroundMode: true,
      notificationChannelId: 'tide_bot_alive',
      initialNotificationTitle: 'TideBot',
      initialNotificationContent: '数字生命引擎已连接',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
  service.startService();
}

@pragma('vm:entry-point')
Future<bool> onStart(ServiceInstance service) async => true;

class FlowProvider extends ChangeNotifier {
  Offset _pos = const Offset(200, 500);
  Offset _tg = const Offset(200, 500);
  Timer? _t;
  Offset get pos => _pos;
  void moveTo(Offset t) { _tg = t; _t?.cancel(); _t = Timer.periodic(const Duration(milliseconds: 16), (tm) { try { _pos = Offset(_pos.dx + (_tg.dx - _pos.dx) * 0.15, _pos.dy + (_tg.dy - _pos.dy) * 0.15); if ((_pos - _tg).distance < 0.5) { _pos = _tg; tm.cancel(); } notifyListeners(); } catch (_) { tm.cancel(); } }); }
  @override void dispose() { _t?.cancel(); super.dispose(); }
}
final FlowProvider flowProvider = FlowProvider();

class FlowGlassBg extends StatelessWidget {
  final Widget child;
  const FlowGlassBg({Key? key, required this.child}) : super(key: key);
  @override Widget build(BuildContext context) => Stack(children: [
    Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF2F2F7), Color(0xFFE8E8F0), Color(0xFFF0F0F5)]))),
    ListenableBuilder(listenable: flowProvider, builder: (c, _) => Stack(children: [
      Positioned(left: flowProvider.pos.dx - 120, top: flowProvider.pos.dy - 80, child: IgnorePointer(child: Container(width: 240, height: 240, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFFFB5A7).withOpacity(0.3), const Color(0xFFFCD5CE).withOpacity(0.1), Colors.transparent]))))),
      Positioned(left: flowProvider.pos.dx - 160, top: flowProvider.pos.dy - 40, child: IgnorePointer(child: Container(width: 280, height: 280, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFA2D2FF).withOpacity(0.25), const Color(0xFFBDE0FE).withOpacity(0.08), Colors.transparent]))))),
      Positioned(left: flowProvider.pos.dx - 100, top: flowProvider.pos.dy - 100, child: IgnorePointer(child: Container(width: 180, height: 180, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFCDB4DB).withOpacity(0.2), Colors.transparent]))))),
    ])),
    child,
  ]);
}

class TideBotApp extends StatelessWidget {
  final bool hasSeenOnboarding;
  const TideBotApp({Key? key, required this.hasSeenOnboarding}) : super(key: key);
  @override Widget build(BuildContext context) => TideBotThemeProvider(theme: tideTheme, child: MaterialApp(title: 'TideBot', debugShowCheckedModeBanner: false, theme: ThemeData(fontFamily: 'TideFont', scaffoldBackgroundColor: const Color(0xFFF2F2F7), appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0), useMaterial3: true, splashColor: Colors.transparent, highlightColor: Colors.transparent), home: hasSeenOnboarding ? const TideMainScaffold() : const OnboardingScreen()));
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}
class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController(); int _cur = 0;
  final _pages = [
    {"icon": Icons.shield_rounded, "t": "绝对隐私", "s": "零服务器架构，你的数字伴侣与记忆\n100% 安全留存本地。"},
    {"icon": Icons.api_rounded, "t": "配置 API", "s": "先去「我的」→「API 设置」添加模型，\n支持 OpenAI 兼容接口。"},
    {"icon": Icons.person_add_rounded, "t": "创建机器人", "s": "在聊天页点击右下角 +，\n定制专属 AI 伴侣的人设和风格。"},
    {"icon": Icons.auto_awesome_rounded, "t": "多模态交互", "s": "文字、语音、图片、文件——\n唤起电话式通话，体验超现实连接。"},
    {"icon": Icons.palette_rounded, "t": "极致美学", "s": "沉浸式 iOS 风格设计，\n莫兰迪配色，流光溢彩的数字陪伴。"},
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    if (!mounted) return;
    Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (c, a, s) => const TideMainScaffold(), transitionsBuilder: (c, a, s, child) => FadeTransition(opacity: a, child: child), transitionDuration: const Duration(milliseconds: 600)));
  }

  void _next() {
    if (_cur < _pages.length - 1) {
      _pc.animateToPage(_cur + 1, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  @override Widget build(BuildContext context) => Scaffold(body: FlowGlassBg(child: SafeArea(child: Column(children: [
    const SizedBox(height: 40),
    Expanded(child: PageView.builder(
      controller: _pc, onPageChanged: (i) => setState(() => _cur = i),
      itemCount: _pages.length, itemBuilder: (c, i) => _buildP(i),
    )),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_pages.length, (i) =>
        AnimatedContainer(duration: const Duration(milliseconds: 350), width: _cur == i ? 28 : 8, height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: _cur == i ? TideTheme.of(context).primary : const Color(0xFFD4D4D8)),
        )),
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
      child: BouncyTap(
        onTap: _next,
        child: Container(
          width: double.infinity, height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(colors: [TideTheme.of(context).primary, TideTheme.of(context).primaryLight]),
            boxShadow: [BoxShadow(color: TideTheme.of(context).primary.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Center(child: Text(_cur == _pages.length - 1 ? '开始体验' : '下一步', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'TideFont'))),
        ),
      ),
    ),
  ]))));

  Widget _buildP(int i) {
    final p = _pages[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 100, height: 100,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [TideTheme.of(context).primary, TideTheme.of(context).primaryLight]), boxShadow: [BoxShadow(color: TideTheme.of(context).primary.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))]),
          child: Icon(p["icon"] as IconData, color: Colors.white, size: 44)),
        const SizedBox(height: 36),
        Text(p["t"] as String, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, fontFamily: 'TideFont', color: Color(0xFF1C1C1E))),
        const SizedBox(height: 14),
        Text(p["s"] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.5, fontFamily: 'TideFont', color: Color(0xFF636366))),
      ]),
    );
  }
}

class JellyDock extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  const JellyDock({Key? key, required this.currentIndex, required this.onTap}) : super(key: key);
  @override State<JellyDock> createState() => _JellyDockState();
}
class _JellyDockState extends State<JellyDock> with SingleTickerProviderStateMixin {
  static const double _baseW = 64.0;
  static const double _growW = 98.0;
  late AnimationController _c;
  late Animation<double> _pos;
  late Animation<double> _w;
  late Animation<double> _scale;
  int _prev = 0;

  static const _icons = [Icons.chat_bubble_rounded, Icons.space_dashboard_rounded, Icons.explore_rounded, Icons.person_rounded];

  @override void initState() {
    super.initState();
    _prev = widget.currentIndex;
    // 加速移动：800ms -> 380ms
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _pos = Tween<double>(begin: _prev * 0.25, end: widget.currentIndex * 0.25).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOutQuart)
    );
    // 移动中放大，落下后极速缩回（前 60% 放大，后 40% 缩回基数）
    _w = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: _baseW, end: _growW).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 60),
      TweenSequenceItem(tween: Tween(begin: _growW, end: _baseW).chain(CurveTween(curve: Curves.easeInBack)), weight: 40),
    ]).animate(_c);
    // 整块胶囊轻微上浮再回落，增强"弹到位置"的丝滑感
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1).chain(CurveTween(curve: Curves.easeOutBack)), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 45),
    ]).animate(_c);
    _c.forward();
  }

  @override void didUpdateWidget(JellyDock old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _prev = old.currentIndex;
      _pos = Tween<double>(begin: _prev * 0.25, end: widget.currentIndex * 0.25).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeOutQuart)
      );
      _w = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: _baseW, end: _growW).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 60),
        TweenSequenceItem(tween: Tween(begin: _growW, end: _baseW).chain(CurveTween(curve: Curves.easeInBack)), weight: 40),
      ]).animate(_c);
      _scale = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1).chain(CurveTween(curve: Curves.easeOutBack)), weight: 55),
        TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 45),
      ]).animate(_c);
      _c.reset(); _c.forward();
    }
  }

  @override void dispose() { _c.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
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
              color: Colors.white.withOpacity(0.35),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 4))],
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
                        width: _w.value, height: 44,
                        decoration: BoxDecoration(
                          color: theme.primary.withOpacity(0.18),
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
                  return Expanded(child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => HapticFeedback.lightImpact(),
                    onTap: () => widget.onTap(i),
                    child: Center(child: Icon(_icons[i], color: act ? theme.primary : const Color(0xFFAEAEB2), size: 22)),
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
  const TideMainScaffold({Key? key}) : super(key: key);
  @override State<TideMainScaffold> createState() => _TideMainScaffoldState();
}
class _TideMainScaffoldState extends State<TideMainScaffold> {
  int _idx = 0;
  final PageController _pageCtrl = PageController();
  final GlobalKey<SquarePageState> _squareKey = GlobalKey<SquarePageState>();
  final GlobalKey<ChatListPageState> _chatListKey = GlobalKey<ChatListPageState>();
  late final List<Widget> _pages;

  @override void initState() {
    super.initState();
    _pages = [ChatListPage(key: _chatListKey), const SpacePage(), SquarePage(key: _squareKey), const ProfilePage()];
  }

  void _onDockTap(int i) {
    if (_idx != i) {
      setState(() => _idx = i);
      _pageCtrl.animateToPage(i, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override void dispose() {
    _pageCtrl.dispose();
    flowProvider.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context) {
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
            left: 0, right: 0, bottom: bottomPadding + 24,
            child: JellyDock(currentIndex: _idx, onTap: _onDockTap),
          ),
          // 聊天列表创建机器人悬浮球
          if (_idx == 0)
            Positioned(
              right: 20,
              bottom: bottomPadding + 76,
              child: BouncyTap(
                onTap: () async {
                  final r = await Navigator.push(context, PageRouteBuilder(pageBuilder: (c, a, s) => const CreateBotPage(), transitionsBuilder: (c, a, s, child) => SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: FadeTransition(opacity: a, child: child))));
                  if (r == true) _chatListKey.currentState?.load();
                },
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [theme.primary, theme.primaryLight]),
                    boxShadow: [BoxShadow(color: theme.primary.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
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
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [theme.primary, theme.primaryLight]),
                    boxShadow: [BoxShadow(color: theme.primary.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
