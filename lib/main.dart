import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// 拆分后的核心 UI 组件库
import 'ui_chat_core.dart'; 
import 'ui_space_square.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  // 1. 初始化引擎
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();
  // 彻底变更为纯净的 Apple 白主题
  final String themeStr = prefs.getString('tide_theme') ?? 'white'; 

  runApp(TideBotApp(initialTheme: themeStr));

  // ==========================================
  // 【闪退修复核心】
  // 延后执行后台服务，且主动处理 Android 13+ 通知权限
  // 绝不阻塞 runApp 导致主线程 ANR
  // ==========================================
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      if (Platform.isAndroid) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      await initBackgroundService();
    } catch (e) {
      debugPrint("Background Service Init Failed (Ignored): \$e");
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
    'tide_bot_foreground', 'TideBot 后台守护', 
    description: '保持 TideBot 在后台持续运行', importance: Importance.low, 
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, autoStart: true, isForegroundMode: true,
      notificationChannelId: 'tide_bot_foreground',
      initialNotificationTitle: 'TideBot 运行中',
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
        fontFamily: 'TideFont',
        primaryColor: currentTheme.accentColor,
        scaffoldBackgroundColor: currentTheme.chatBg, // 变更为极致极简的白色系
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

// ----------------------------------------------------------------------
// 全局基座：去掉了杂乱的花哨背景，回归纯净 iOS 风
// 保留了底部毛玻璃 Dock，且发光球现在仅在底部跟随点击，不污染全屏
// ----------------------------------------------------------------------
class TideMainScaffold extends StatefulWidget {
  final ThemeColors themeColors;
  const TideMainScaffold({Key? key, required this.themeColors}) : super(key: key);
  @override
  State<TideMainScaffold> createState() => _TideMainScaffoldState();
}

class _TideMainScaffoldState extends State<TideMainScaffold> {
  int _currentIndex = 0; 
  double targetX = 0;
  double currentX = 0;

  void _onNavTapped(int index, Offset tapPosition) {
    setState(() {
      _currentIndex = index;
      final size = MediaQuery.of(context).size;
      targetX = tapPosition.dx - (size.width / 2);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 背景颜色直接采用极简灰白 (类似 Apple 的 #F2F2F7)
      backgroundColor: const Color(0xFFF2F2F7),
      body: Stack(
        children: [
          // 主体内容区
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

          // 底部悬浮毛玻璃 Dock 导航
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 14,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7), // 纯净的白色毛玻璃
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Stack(
                      children: [
                        // 底部跟踪滑动的流光点 (您要求的必须要滑过去)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          left: (MediaQuery.of(context).size.width * 0.85 / 2) - 30 + targetX,
                          top: 10,
                          child: Container(
                            width: 60, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                        // 图标层
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildDockItem(0, "Home"),
                            _buildDockItem(1, "Chats"),
                            _buildDockItem(2, "Square"),
                            _buildDockItem(3, "Diary"),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 严格参考图1：纯文字极简 Dock
  Widget _buildDockItem(int index, String label) {
    bool isActive = _currentIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        // 计算点击位置在 Dock 内的相对偏移量
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final localPosition = renderBox.globalToLocal(details.globalPosition);
          _onNavTapped(index, localPosition);
        } else {
          _onNavTapped(index, details.globalPosition);
        }
      },
      child: Container(
        alignment: Alignment.center,
        width: 70,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'TideFont', // 强制 TideFont
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
            color: isActive ? Colors.black : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 主题引擎：全部退回到纯粹极简白/灰风格
// ----------------------------------------------------------------------
class ThemeColors {
  final Color bgGrad1;
  final Color bgGrad2;
  final Color accentColor;
  final Color panelBg;
  final Color textMain;
  final Color chatBg;
  final bool isDark;

  ThemeColors({required this.bgGrad1, required this.bgGrad2, required this.accentColor, required this.panelBg, required this.textMain, required this.chatBg, this.isDark = false});
}

class ThemeConfig {
  static ThemeColors getTheme(String name) {
    return ThemeColors(
      bgGrad1: Colors.white,
      bgGrad2: Colors.white,
      accentColor: Colors.black, // Apple 风的强调色往往是纯黑
      panelBg: Colors.white,
      textMain: Colors.black87,
      chatBg: const Color(0xFFF2F2F7), // Apple 标准底色
      isDark: false,
    );
  }
}
