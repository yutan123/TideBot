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
// 全局基座：带有“粘性”物理过渡的毛玻璃流光底部导航
// ======================================================================
class TideMainScaffold extends StatefulWidget {
  final ThemeColors themeColors;
  const TideMainScaffold({Key? key, required this.themeColors}) : super(key: key);
  @override
  State<TideMainScaffold> createState() => _TideMainScaffoldState();
}

class _TideMainScaffoldState extends State<TideMainScaffold> {
  int _currentIndex = 0; // 默认打开 Chats
  final List<String> _tabs = ["聊天", "空间", "广场", "我的"];

  // 控制滑动胶囊的动画变量
  double _dragPosition = 0.0; 

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dockWidth = screenWidth * 0.9; 
    final tabWidth = dockWidth / 4;      

    return Scaffold(
      backgroundColor: widget.themeColors.chatBg, 
      body: Stack(
        children: [
          // 主体内容路由
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                ChatListPage(),    // 聊天
                SpacePage(),       // 空间
                SquarePage(),      // 广场
                ProfilePage(),     // 我的
              ],
            ),
          ),

          // 悬浮滑动 Dock 
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
                      // 带有弹簧粘性动效的流光胶囊底座
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.elasticOut, // 弹性/粘性曲线，滑过去会有黏糊糊的颤动
                        left: _currentIndex * tabWidth + (tabWidth * 0.1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          width: tabWidth * 0.8,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white, // 流光白色滑块
                            borderRadius: BorderRadius.circular(23),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 2))
                            ]
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
      chatBg: const Color(0xFFF2F2F7), // iOS 灰背景
      isDark: false,
    );
  }
}
