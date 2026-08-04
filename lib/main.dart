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
  _initPersistentService();
}

Future<void> _initPersistentService() async {
  final service = FlutterBackgroundService();
  const channel = AndroidNotificationChannel('tide_bot_alive', 'TideBot Core', importance: Importance.low);
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: (s) {}, autoStart: true, isForegroundMode: true,
      notificationChannelId: 'tide_bot_alive', initialNotificationTitle: 'TideBot', initialNotificationContent: '数字生命引擎已连接', foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
  service.startService();
}

class TideBotApp extends StatelessWidget {
  final bool hasSeenOnboarding;
  const TideBotApp({Key? key, required this.hasSeenOnboarding}) : super(key: key);
  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TideBot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'TideFont',
        scaffoldBackgroundColor: const Color(0xFFF5F5F7), // iOS 灰背景
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
        useMaterial3: true,
      ),
      home: hasSeenOnboarding ? const TideMainScaffold() : const OnboardingScreen(), 
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}
class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController();
  int _cur = 0;
  final _pages = [{"t": "纯本地 绝对隐私", "s": "没有任何官方服务器，记忆与设定100%安全留存本地。"}, {"t": "沉浸式 情感陪伴", "s": "极致 iOS 风毛玻璃美学与阻尼动画。"}, {"t": "智能 Agent 助手", "s": "支持小游戏对弈、动态广场互动以及微信桥接同步。"}];
  
  void _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    await DBManager().insertBot({'id': 'bot_1', 'name': '屿潭', 'desc': '一个温柔略带傲娇的数字伴侣。', 'prompt': '说话温柔细腻，对主人充满关怀。', 'created_at': DateTime.now().millisecondsSinceEpoch});
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TideMainScaffold()));
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(child: Column(children: [
        Expanded(child: PageView.builder(controller: _pc, itemCount: 3, onPageChanged: (i) => setState(() => _cur = i), itemBuilder: (c, i) => Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 120, height: 120, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(36)), alignment: Alignment.center, child: const Text("T", style: TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w900))), const SizedBox(height: 48), Text(_pages[i]['t']!, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5), textAlign: TextAlign.center), const SizedBox(height: 16), Text(_pages[i]['s']!, style: TextStyle(fontSize: 16, color: Colors.grey.shade600, height: 1.5), textAlign: TextAlign.center)])))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 4), width: _cur == i ? 24 : 8, height: 8, decoration: BoxDecoration(color: _cur == i ? Colors.black : Colors.grey.shade300, borderRadius: BorderRadius.circular(4))))),
        const SizedBox(height: 32),
        Padding(padding: const EdgeInsets.all(32), child: GestureDetector(onTap: () { HapticFeedback.mediumImpact(); if (_cur < 2) _pc.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); else _finish(); }, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(24)), alignment: Alignment.center, child: Text(_cur == 2 ? "开启旅程" : "下一步", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))))),
      ])),
    );
  }
}

// 核心主页布局 (彻底修复白屏和底部栏巨大问题)
class TideMainScaffold extends StatefulWidget {
  const TideMainScaffold({Key? key}) : super(key: key);
  @override State<TideMainScaffold> createState() => _TideMainScaffoldState();
}

class _TideMainScaffoldState extends State<TideMainScaffold> {
  int _currentIndex = 0;
  final List<String> _tabs = ["聊天", "空间", "广场", "我的"];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dockWidth = screenWidth * 0.9; 
    final tabWidth = dockWidth / _tabs.length;      

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7), 
      body: Stack(
        children: [
          // 1. 内容层 (占满全屏)
          Positioned.fill(
            child: IndexedStack(
              index: _currentIndex,
              children: const [ChatListPage(), SpacePage(), SquarePage(), ProfilePage()],
            ),
          ),
          
          // 2. 悬浮底座层 (绝对定位，避免 SafeArea 拉伸)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 20,
            left: (screenWidth - dockWidth) / 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: dockWidth,
                  height: 64, // 严格固定高度
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.65), 
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white.withOpacity(0.6), width: 1),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // 叠加在上面的流光白块
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.fastOutSlowIn,
                        left: _currentIndex * tabWidth + 4,
                        top: 4, bottom: 4,
                        width: tabWidth - 8,
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 2))]),
                        ),
                      ),
                      // 文字
                      Row(
                        children: List.generate(_tabs.length, (index) {
                          bool isActive = _currentIndex == index;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () { HapticFeedback.selectionClick(); setState(() => _currentIndex = index); },
                            child: SizedBox(
                              width: tabWidth, height: 64,
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(fontFamily: 'TideFont', fontSize: 16, fontWeight: isActive ? FontWeight.w800 : FontWeight.w600, color: isActive ? Colors.black : Colors.grey.shade500),
                                  child: Text(_tabs[index]),
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