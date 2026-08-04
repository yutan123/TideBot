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

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();
  final String themeStr = prefs.getString('tide_theme') ?? 'apple'; 

  runApp(TideBotApp(initialTheme: themeStr));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      if (Platform.isAndroid) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      await initBackgroundService();
    } catch (e) {
      debugPrint("Background Service Init Failed: \$e");
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
    description: '数字生命持续链接中', importance: Importance.low, 
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
  const TideBotApp({Key? key, required this.initialTheme}) : super(key: key);
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
        fontFamily: 'TideFont', // 全局指定自有字体
        primaryColor: currentTheme.accentColor,
        scaffoldBackgroundColor: currentTheme.chatBg, 
        colorScheme: ColorScheme.fromSeed(
          seedColor: currentTheme.accentColor,
          brightness: currentTheme.isDark ? Brightness.dark : Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: TideMainScaffold(themeColors: currentTheme), 
    );
  }
}

// ======================================================================
// 全局基座：复刻图片 1000037076.jpg 的丝滑胶囊滑动导航
// ======================================================================
class TideMainScaffold extends StatefulWidget {
  final ThemeColors themeColors;
  const TideMainScaffold({Key? key, required this.themeColors}) : super(key: key);
  @override
  State<TideMainScaffold> createState() => _TideMainScaffoldState();
}

class _TideMainScaffoldState extends State<TideMainScaffold> {
  int _currentIndex = 1; // 默认打开 Chats
  final List<String> _tabs = ["Home", "Chats", "Square", "Diary"];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dockWidth = screenWidth * 0.9; // Dock 总宽度
    final tabWidth = dockWidth / 4;      // 单个 Tab 宽度
    final capsuleWidth = tabWidth * 0.9; // 灰色滑块胶囊宽度

    return Scaffold(
      backgroundColor: widget.themeColors.chatBg, // 极简底色
      body: Stack(
        children: [
          // 主体内容路由
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                SpacePage(),       // Home对应的是Space界面
                ChatListPage(),    // Chats对应的是聊天列表
                SquarePage(),      // Square广场
                ProfilePage(),     // Diary对应设置和日记
              ],
            ),
          ),

          // 悬浮滑动 Dock (严格参照图片设计)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: (screenWidth - dockWidth) / 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  width: dockWidth,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85), // iOS 毛玻璃白
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // 滑动的灰色胶囊底座
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic, // 丝滑阻尼曲线
                        left: _currentIndex * tabWidth + (tabWidth - capsuleWidth) / 2,
                        child: Container(
                          width: capsuleWidth,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.06), // 极淡的灰色
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                      ),
                      // 文字层
                      Row(
                        children: List.generate(_tabs.length, (index) {
                          bool isActive = _currentIndex == index;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.lightImpact(); // 触感反馈
                              setState(() { _currentIndex = index; });
                            },
                            child: SizedBox(
                              width: tabWidth,
                              height: 60,
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 300),
                                  style: TextStyle(
                                    fontFamily: 'TideFont',
                                    fontSize: 16,
                                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                                    color: isActive ? Colors.black : Colors.grey.shade400,
                                    letterSpacing: 0.5,
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

// ----------------------------------------------------------------------
// 主题色彩管理：极致 Apple 白
// ----------------------------------------------------------------------
class ThemeColors {
  final Color accentColor;
  final Color textMain;
  final Color chatBg;
  final bool isDark;

  ThemeColors({required this.accentColor, required this.textMain, required this.chatBg, this.isDark = false});
}

class ThemeConfig {
  static ThemeColors getTheme(String name) {
    return ThemeColors(
      accentColor: Colors.black, 
      textMain: Colors.black87,
      chatBg: const Color(0xFFF2F2F7), // Apple 经典的浅灰色背景
      isDark: false,
    );
  }
}
