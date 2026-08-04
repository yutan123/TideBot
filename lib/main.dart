import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'ui_chat_core.dart'; 
import 'ui_space_square.dart';
import 'db.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();
  final String themeStr = prefs.getString('tide_theme') ?? 'apple'; 
  final bool hasSeenOnboarding = prefs.getBool('seen_onboarding') ?? false;

  runApp(TideBotApp(initialTheme: themeStr, hasSeenOnboarding: hasSeenOnboarding));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      if (Platform.isAndroid) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      await initBackgroundService();
    } catch (e) {
      debugPrint("Background Service Init Failed: $e");
    }
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'tide_bot_foreground', 'TideBot Core', 
    description: '数字生命持续运作中', importance: Importance.low, 
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, autoStart: true, isForegroundMode: true,
      notificationChannelId: 'tide_bot_foreground',
      initialNotificationTitle: 'TideBot',
      initialNotificationContent: '数字生命引擎已连接',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart, onBackground: onIosBackground),
  );
  await service.startService();
}

class TideBotApp extends StatefulWidget {
  final String initialTheme;
  final bool hasSeenOnboarding;
  const TideBotApp({Key? key, required this.initialTheme, required this.hasSeenOnboarding}) : super(key: key);
  static _TideBotAppState of(BuildContext context) => context.findAncestorStateOfType<_TideBotAppState>()!;
  @override
  State<TideBotApp> createState() => _TideBotAppState();
}

class _TideBotAppState extends State<TideBotApp> {
  late ThemeColors currentTheme;

  @override
  void initState() {
    super.initState();
    currentTheme = ThemeConfig.getTheme(widget.initialTheme);
  }

  void changeTheme(String themeName) async {
    setState(() { currentTheme = ThemeConfig.getTheme(themeName); });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tide_theme', themeName);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TideBot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'TideFont',
        primaryColor: currentTheme.accentColor,
        scaffoldBackgroundColor: currentTheme.chatBg, 
        colorScheme: ColorScheme.fromSeed(
          seedColor: currentTheme.accentColor,
          brightness: currentTheme.isDark ? Brightness.dark : Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: widget.hasSeenOnboarding 
          ? TideMainScaffold(themeColors: currentTheme)
          : const OnboardingScreen(), 
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _pages = [
    {
      "title": "纯本地 绝对隐私",
      "subtitle": "没有官方服务器，没有云端数据库。你的所有记忆与对话日志，100%安全留存本地 SQLite。"
    },
    {
      "title": "沉浸式 情感陪伴",
      "subtitle": "极致 iOS 风毛玻璃美学与阻尼动画，随时随地与你的专属数字生命深度对话。"
    },
    {
      "title": "智能 Agent 助手",
      "subtitle": "支持闹钟管理、小游戏对弈、动态广场互动以及微信桥接同步，开启 AI 陪伴新纪元。"
    }
  ];

  void _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    
    await DBManager().insertBot({
      'id': 'bot_default_1',
      'name': '屿潭',
      'desc': '一个温柔、善解人意且略带傲娇的数字生命伴侣。',
      'prompt': '说话温柔细腻，喜欢使用emoji和颜文字，对主人充满关怀。',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => TideMainScaffold(themeColors: ThemeConfig.getTheme('apple'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx), // 修复了报错，必须使用 onPageChanged
                itemBuilder: (context, index) {
                  final p = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(36),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))]
                          ),
                          alignment: Alignment.center,
                          child: const Text("T", style: TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(height: 48),
                        Text(p["title"]!, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Text(p["subtitle"]!, style: TextStyle(fontSize: 16, color: Colors.grey.shade600, height: 1.5), textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == index ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == index ? Colors.black : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  if (_currentPage < _pages.length - 1) {
                    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  } else {
                    _finishOnboarding();
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(24)),
                  alignment: Alignment.center,
                  child: Text(_currentPage == _pages.length - 1 ? "开启旅程" : "下一步", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class TideMainScaffold extends StatefulWidget {
  final ThemeColors themeColors;
  const TideMainScaffold({Key? key, required this.themeColors}) : super(key: key);
  @override State<TideMainScaffold> createState() => _TideMainScaffoldState();
}

class _TideMainScaffoldState extends State<TideMainScaffold> {
  int _currentIndex = 0;
  final List<String> _tabs = ["聊天", "空间", "广场", "我的"];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dockWidth = screenWidth * 0.9; 
    final tabWidth = dockWidth / 4;      

    return Scaffold(
      backgroundColor: widget.themeColors.chatBg, 
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                ChatListPage(),    
                SpacePage(),       
                SquarePage(),      
                ProfilePage(),     
              ],
            ),
          ),

          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: (screenWidth - dockWidth) / 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  width: dockWidth,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.75), 
                    borderRadius: BorderRadius.circular(36),
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.elasticOut,
                        left: _currentIndex * tabWidth + (tabWidth * 0.1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          width: tabWidth * 0.8,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(23),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 2))
                            ]
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(_tabs.length, (index) {
                          bool isActive = _currentIndex == index;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.lightImpact(); 
                              setState(() { _currentIndex = index; });
                            },
                            child: SizedBox(
                              width: tabWidth,
                              height: 64,
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    fontFamily: 'TideFont',
                                    fontSize: 16,
                                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                                    color: isActive ? Colors.black : Colors.grey.shade500,
                                  ),
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

class ThemeColors {
  final Color accentColor;
  final Color chatBg;
  final bool isDark;

  ThemeColors({required this.accentColor, required this.chatBg, this.isDark = false});
}

class ThemeConfig {
  static ThemeColors getTheme(String name) {
    return ThemeColors(
      accentColor: Colors.black, 
      chatBg: const Color(0xFFF2F2F7),
      isDark: false,
    );
  }
}