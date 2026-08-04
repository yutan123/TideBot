import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'ui_chat_core.dart'; 
import 'ui_space_square.dart';
import 'db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  final bool hasSeenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  runApp(TideBotApp(hasSeenOnboarding: hasSeenOnboarding));
  await _initPersistentService();
}

// 严格遵循 flutter_background_service ^5.1.0 的要求，确保在 Android 上不被杀后台
Future<void> _initPersistentService() async {
  final service = FlutterBackgroundService();
  const channel = AndroidNotificationChannel(
    'tide_bot_alive', 
    'TideBot Core', 
    importance: Importance.low
  );
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
      
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, 
      autoStart: true, 
      isForegroundMode: true,
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
Future<bool> onStart(ServiceInstance service) async {
  // 保持后台活跃
  return true; 
}

class TideBotApp extends StatelessWidget {
  final bool hasSeenOnboarding;
  const TideBotApp({Key? key, required this.hasSeenOnboarding}) : super(key: key);
  
  @override 
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TideBot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'TideFont', // 强制使用全局自定义字体
        scaffoldBackgroundColor: const Color(0xFFF2F2F7), // 标准 iOS 灰色背景
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
        useMaterial3: true,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent, // 彻底禁用原生水波纹
      ),
      home: hasSeenOnboarding ? const TideMainScaffold() : const OnboardingScreen(), 
    );
  }
}

// 新手引导页 (极致简约 iOS 风)
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController();
  int _cur = 0;
  final _pages = [
    {"t": "绝对隐私", "s": "零服务器，你的数字伴侣与记忆 100% 安全留存本地。"}, 
    {"t": "多模态感知", "s": "支持语音、视觉与系统级操作，不仅仅是对话。"}, 
    {"t": "极致美学", "s": "沉浸式 iOS 风格，流光溢彩的陪伴。"}
  ];
  
  void _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    await DBManager().insertBot({'id': 'bot_1', 'name': '屿潭', 'desc': '一个温柔略带傲娇的数字伴侣。', 'prompt': '说话温柔细腻，对主人充满关怀。', 'created_at': DateTime.now().millisecondsSinceEpoch});
    if (!mounted) return;
    Navigator.pushReplacement(context, PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => const TideMainScaffold(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 600),
    ));
  }

  @override 
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Column(children: [
        Expanded(child: PageView.builder(
          controller: _pc, 
          itemCount: 3, 
          onPageChanged: (i) {
            HapticFeedback.lightImpact();
            setState(() => _cur = i);
          }, 
          itemBuilder: (c, i) => Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 140, height: 140, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(42), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 15))]), alignment: Alignment.center, child: const Icon(Icons.all_inclusive, color: Colors.white, size: 70)), 
            const SizedBox(height: 60), 
            Text(_pages[i]['t']!, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5), textAlign: TextAlign.center), 
            const SizedBox(height: 20), 
            Text(_pages[i]['s']!, style: TextStyle(fontSize: 17, color: Colors.grey.shade600, height: 1.6), textAlign: TextAlign.center)
          ]))
        )),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) => AnimatedContainer(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic, margin: const EdgeInsets.symmetric(horizontal: 5), width: _cur == i ? 32 : 10, height: 10, decoration: BoxDecoration(color: _cur == i ? Colors.black : Colors.grey.shade300, borderRadius: BorderRadius.circular(5))))),
        const SizedBox(height: 48),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20), child: GestureDetector(onTap: () { HapticFeedback.mediumImpact(); if (_cur < 2) _pc.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic); else _finish(); }, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))]), alignment: Alignment.center, child: Text(_cur == 2 ? "开启旅程" : "下一步", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))))),
      ])),
    );
  }
}

// 核心主页布局 (流光玻璃 Dock 导航)
class TideMainScaffold extends StatefulWidget {
  const TideMainScaffold({Key? key}) : super(key: key);
  @override State<TideMainScaffold> createState() => _TideMainScaffoldState();
}

class _TideMainScaffoldState extends State<TideMainScaffold> {
  int _currentIndex = 0;
  final List<Map<String, dynamic>> _tabs = [
    {"name": "聊天", "icon": Icons.chat_bubble_rounded},
    {"name": "空间", "icon": Icons.space_dashboard_rounded},
    {"name": "广场", "icon": Icons.public},
    {"name": "我的", "icon": Icons.person_rounded}
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dockWidth = screenWidth * 0.92; 
    final tabWidth = dockWidth / _tabs.length;      

    return Scaffold(
      // 禁用默认底部导航，完全自定义
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _currentIndex,
              children: const [ChatListPage(), SpacePage(), SquarePage(), ProfilePage()],
            ),
          ),
          
          // 悬浮流光底座
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom + 10 : 30,
            left: (screenWidth - dockWidth) / 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  width: dockWidth,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.55), 
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 30, offset: const Offset(0, 15))],
                  ),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // 滑动流光指示器
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        left: _currentIndex * tabWidth + 6,
                        top: 6, bottom: 6,
                        width: tabWidth - 12,
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
                        ),
                      ),
                      // 按钮内容
                      Row(
                        children: List.generate(_tabs.length, (index) {
                          bool isActive = _currentIndex == index;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () { 
                              HapticFeedback.lightImpact(); 
                              setState(() => _currentIndex = index); 
                            },
                            child: SizedBox(
                              width: tabWidth, height: 72,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 250),
                                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                      child: Icon(_tabs[index]["icon"], key: ValueKey(isActive), size: 24, color: isActive ? Colors.black : Colors.grey.shade400),
                                    ),
                                    const SizedBox(height: 4),
                                    AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 200),
                                      style: TextStyle(fontFamily: 'TideFont', fontSize: 11, fontWeight: isActive ? FontWeight.w900 : FontWeight.w600, color: isActive ? Colors.black : Colors.grey.shade400),
                                      child: Text(_tabs[index]["name"]),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}