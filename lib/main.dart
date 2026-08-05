import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'ui_chat_list.dart';
import 'ui_space_square.dart';
import 'ui_profile.dart';
import 'db.dart';
import 'ui_components.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
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
  void moveTo(Offset t) { _tg = t; _t?.cancel(); _t = Timer.periodic(const Duration(milliseconds: 16), (tm) { _pos = Offset(_pos.dx + (_tg.dx - _pos.dx) * 0.15, _pos.dy + (_tg.dy - _pos.dy) * 0.15); if ((_pos - _tg).distance < 0.5) { _pos = _tg; tm.cancel(); } notifyListeners(); }); }
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
  @override Widget build(BuildContext context) => MaterialApp(title: 'TideBot', debugShowCheckedModeBanner: false, theme: ThemeData(fontFamily: 'TideFont', scaffoldBackgroundColor: const Color(0xFFF2F2F7), appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0), useMaterial3: true, splashColor: Colors.transparent, highlightColor: Colors.transparent), home: hasSeenOnboarding ? const TideMainScaffold() : const OnboardingScreen());
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}
class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController(); int _cur = 0;
  final _pages = [
    {"icon": Icons.shield_rounded, "t": "绝对隐私", "s": "零服务器架构，你的数字伴侣与记忆\n100% 安全留存本地。"},
    {"icon": Icons.auto_awesome_rounded, "t": "多模态感知", "s": "支持语音、视觉与系统级操作，\n不仅仅是对话工具。"},
    {"icon": Icons.palette_rounded, "t": "极致美学", "s": "沉浸式 iOS 风格设计，\n流光溢彩的数字陪伴。"},
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    try {
      await DBManager().insertBot({'id': 'bot_1', 'name': '屿潭', 'desc': '温柔傲娇的数字伴侣', 'prompt': '说话温柔细腻，偶尔害羞。【输出格式】每条回复最前面用方括号标明心情', 'avatar': '', 'created_at': DateTime.now().millisecondsSinceEpoch});
    } catch (_) {}
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
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: _cur == i ? const Color(0xFF6B5B95) : const Color(0xFFD4D4D8)),
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
            gradient: const LinearGradient(colors: [Color(0xFF6B5B95), Color(0xFF9B8EC4)]),
            boxShadow: [BoxShadow(color: const Color(0xFF6B5B95).withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
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
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFF6B5B95), Color(0xFF9B8EC4)]), boxShadow: [BoxShadow(color: const Color(0xFF6B5B95).withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))]),
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
  late AnimationController _c;
  late Animation<double> _pos;
  late Animation<double> _w;
  int _prev = 0;

  static const _icons = [Icons.chat_bubble_rounded, Icons.space_dashboard_rounded, Icons.explore_rounded, Icons.person_rounded];

  @override void initState() {
    super.initState();
    _prev = widget.currentIndex;
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _pos = Tween<double>(begin: _prev * 0.25, end: widget.currentIndex * 0.25).animate(
      CurvedAnimation(parent: _c, curve: Curves.elasticOut)
    );
    _w = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 36.0, end: 48.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 48.0, end: 36.0), weight: 75),
    ]).animate(CurvedAnimation(parent: _c, curve: Curves.elasticOut));
    _c.forward();
  }

  @override void didUpdateWidget(JellyDock old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _prev = old.currentIndex;
      _pos = Tween<double>(begin: _prev * 0.25, end: widget.currentIndex * 0.25).animate(
        CurvedAnimation(parent: _c, curve: Curves.elasticOut)
      );
      _w = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 36.0, end: 48.0), weight: 25),
        TweenSequenceItem(tween: Tween(begin: 48.0, end: 36.0), weight: 75),
      ]).animate(CurvedAnimation(parent: _c, curve: Curves.elasticOut));
      _c.reset(); _c.forward();
    }
  }

  @override void dispose() { _c.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.45),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 0.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 6))],
          ),
          child: LayoutBuilder(builder: (ctx, cs) {
            final totalW = cs.maxWidth;
            final slotW = totalW / 4;
            return Stack(children: [
              AnimatedBuilder(
                animation: Listenable.merge([_pos, _w]),
                builder: (c, child) {
                  final pillX = _pos.value * totalW + (slotW - _w.value) / 2;
                  return Positioned(
                    left: pillX,
                    top: 4,
                    child: Container(
                      width: _w.value, height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B5B95).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(18),
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
                    child: Center(child: AnimatedScale(
                      duration: const Duration(milliseconds: 200),
                      scale: act ? 1.15 : 0.9,
                      child: Icon(_icons[i], color: act ? const Color(0xFF6B5B95) : const Color(0xFF9E9E9E), size: 24),
                    )),
                  ));
                }),
              ),
            ]);
          }),
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
  late final List<Widget> _pages;

  @override void initState() {
    super.initState();
    _pages = [const ChatListPage(), const SpacePage(), SquarePage(key: _squareKey), const ProfilePage()];
  }

  void _onDockTap(int i) {
    if (_idx != i) {
      setState(() => _idx = i);
      _pageCtrl.animateToPage(i, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return FlowGlassBg(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(children: [
          GestureDetector(
            onTapDown: (d) => flowProvider.moveTo(d.localPosition),
            behavior: HitTestBehavior.translucent,
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _idx = i),
              children: _pages,
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: bottomPadding + 8,
            child: JellyDock(currentIndex: _idx, onTap: _onDockTap),
          ),
          // 广场发布悬浮球 — 在 Dock 上方
          if (_idx == 2)
            Positioned(
              right: 16,
              bottom: bottomPadding + 64,
              child: BouncyTap(
                onTap: () => _squareKey.currentState?.publishFeed(),
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFF6B5B95), Color(0xFF9B8EC4)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF6B5B95).withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 4))],
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
