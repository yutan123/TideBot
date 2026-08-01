import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// 拆分后的核心 UI 组件库
import 'ui_chat_core.dart'; 
import 'ui_space_square.dart';

// 本地通知插件实例
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. 初始化保活服务与通知，确保微信转发和日记生成的持久化
  await initBackgroundService();
  
  // 2. 强制竖屏，保障沉浸式体验
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  // 3. 隐藏状态栏和底部导航栏，实现全屏沉浸
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 4. 获取本地存储的主题偏好（默认绿色）
  final prefs = await SharedPreferences.getInstance();
  final String themeStr = prefs.getString('tide_theme') ?? 'green';

  runApp(TideBotApp(initialTheme: themeStr));
}

@pragma('vm:entry-point')
Future<void> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  // 前台服务持续运行，定时执行心跳，保持后台存活
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 每 15 分钟触发一次后台任务 (例如：检查待回复的微信消息、生成日记)
  // 此处仅维持保活心跳，具体业务逻辑在 ops.dart 和 ai.dart 中调度
}

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'tide_bot_foreground', 
    'TideBot 后台服务', 
    description: '保持 TideBot 核心引擎在后台持续运行，接收微信与生态消息',
    importance: Importance.low, 
  );

  await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'tide_bot_foreground',
      initialNotificationTitle: 'TideBot',
      initialNotificationContent: '数字生命引擎正在运行中...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
  
  await service.startService();
}

class TideBotApp extends StatefulWidget {
  final String initialTheme;
  const TideBotApp({Key? key, required this.initialTheme}) : super(key: key);

  static _TideBotAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_TideBotAppState>()!;

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
    setState(() {
      currentTheme = ThemeConfig.getTheme(themeName);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tide_theme', themeName);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TideBot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'TideFont', // 强制使用项目自定义字体
        primaryColor: currentTheme.accentColor,
        scaffoldBackgroundColor: currentTheme.chatBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: currentTheme.accentColor,
          brightness: currentTheme.isDark ? Brightness.dark : Brightness.light,
        ),
        useMaterial3: true,
      ),
      // 入口：全局流光毛玻璃主框架
      home: TideMainScaffold(themeColors: currentTheme), 
    );
  }
}

// ----------------------------------------------------------------------
// 全局动态流光基座与底部悬浮 Dock 导航
// ----------------------------------------------------------------------
class TideMainScaffold extends StatefulWidget {
  final ThemeColors themeColors;
  const TideMainScaffold({Key? key, required this.themeColors}) : super(key: key);

  @override
  State<TideMainScaffold> createState() => _TideMainScaffoldState();
}

class _TideMainScaffoldState extends State<TideMainScaffold> with SingleTickerProviderStateMixin {
  late AnimationController _bgAnimController;
  int _currentIndex = 0; // 当前选中的导航索引
  
  // 控制流光球的平滑移动
  double targetX = 0;
  double targetY = 0;
  
  // 用于平滑插值的当前位置
  double currentX = 0;
  double currentY = 0;

  @override
  void initState() {
    super.initState();
    // 背景流光球的缓慢呼吸/旋转动画
    _bgAnimController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 15)
    )..repeat();
    
    // 监听动画更新以实现平滑跟随点击
    _bgAnimController.addListener(_updateGlowPosition);
  }
  
  void _updateGlowPosition() {
     // 简单的线性插值，使光球平滑移动到目标位置
     final double smoothingFactor = 0.05;
     if ((currentX - targetX).abs() > 0.5 || (currentY - targetY).abs() > 0.5) {
       setState(() {
         currentX += (targetX - currentX) * smoothingFactor;
         currentY += (targetY - currentY) * smoothingFactor;
       });
     }
  }

  @override
  void dispose() {
    _bgAnimController.removeListener(_updateGlowPosition);
    _bgAnimController.dispose();
    super.dispose();
  }

  void _onNavTapped(int index, Offset tapPosition) {
    setState(() {
      _currentIndex = index;
      // 流光跟随用户点击位置滑动 (限制移动范围，避免光球飞出屏幕太远)
      final size = MediaQuery.of(context).size;
      targetX = (tapPosition.dx - (size.width / 2)).clamp(-size.width * 0.8, size.width * 0.8);
      targetY = (tapPosition.dy - (size.height / 2)).clamp(-size.height * 0.8, size.height * 0.8);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.themeColors.chatBg,
      body: Stack(
        children: [
          // 1. 底层流光背景：两个高强度模糊的彩色球体
          Positioned(
            top: -50 + currentY * 0.3,
            right: -50 - currentX * 0.3,
            child: AnimatedBuilder(
              animation: _bgAnimController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _bgAnimController.value * 2 * 3.14159,
                  child: Container(
                    width: 350,
                    height: 350,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.themeColors.bgGrad1,
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: -90 - currentY * 0.15,
            left: -90 + currentX * 0.15,
            child: Container(
              width: 450,
              height: 450,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.themeColors.bgGrad2,
              ),
            ),
          ),
          
          // 2. 全局极强毛玻璃滤盖
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 90, sigmaY: 110),
              child: Container(color: Colors.transparent),
            ),
          ),
          
          // 3. 主体内容区（切换四大页面）
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _currentIndex,
              children: [
                // 占位，将由真实页面替换
                const ChatListPage(),
                const SpacePage(),
                const SquarePage(),
                const ProfilePage(),
              ],
            ),
          ),

          // 4. 底部悬浮毛玻璃 Dock
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 14,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    height: 56,
                    decoration: BoxDecoration(
                      color: widget.themeColors.panelBg,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildDockItem(0, "聊天", Icons.chat_bubble_outline),
                        _buildDockItem(1, "空间", Icons.explore_outlined),
                        _buildDockItem(2, "广场", Icons.public),
                        _buildDockItem(3, "我的", Icons.person_outline),
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

  Widget _buildDockItem(int index, String label, IconData icon) {
    bool isActive = _currentIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        _onNavTapped(index, details.globalPosition);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(isActive ? 1.0 : 0.85),
        alignment: Alignment.center,
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isActive ? widget.themeColors.accentColor : const Color(0xFF86868B),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isActive ? widget.themeColors.accentColor : const Color(0xFF86868B),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 主题引擎：色彩池定义，完全继承原 CSS 的色彩精髓
// ----------------------------------------------------------------------
class ThemeColors {
  final Color bgGrad1;
  final Color bgGrad2;
  final Color accentColor;
  final Color panelBg;
  final Color textMain;
  final Color chatBg;
  final bool isDark;

  ThemeColors({
    required this.bgGrad1,
    required this.bgGrad2,
    required this.accentColor,
    required this.panelBg,
    required this.textMain,
    required this.chatBg,
    this.isDark = false,
  });
}

class ThemeConfig {
  static ThemeColors getTheme(String name) {
    switch (name) {
      case 'black':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(40, 40, 40, 0.5),
          bgGrad2: const Color.fromRGBO(20, 20, 20, 0.5),
          accentColor: const Color(0xFF1DA1F2),
          panelBg: const Color.fromRGBO(30, 30, 30, 0.8),
          textMain: const Color(0xFFEEEEEE),
          chatBg: const Color(0xFF121212),
          isDark: true,
        );
      case 'white':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(200, 200, 200, 0.25),
          bgGrad2: const Color.fromRGBO(230, 230, 230, 0.3),
          accentColor: const Color(0xFF333333),
          panelBg: const Color.fromRGBO(255, 255, 255, 0.8),
          textMain: const Color(0xFF111111),
          chatBg: const Color(0xFFF5F5F7),
          isDark: false,
        );
      case 'blue':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(135, 206, 250, 0.4),
          bgGrad2: const Color.fromRGBO(0, 191, 255, 0.3),
          accentColor: const Color(0xFF1DA1F2),
          panelBg: const Color.fromRGBO(240, 248, 255, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFE3F2FD),
          isDark: false,
        );
      case 'purple':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(224, 195, 252, 0.4),
          bgGrad2: const Color.fromRGBO(142, 197, 252, 0.4),
          accentColor: const Color(0xFF8A2BE2),
          panelBg: const Color.fromRGBO(250, 245, 255, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFF3E5F5),
          isDark: false,
        );
      case 'orange':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(255, 209, 148, 0.4),
          bgGrad2: const Color.fromRGBO(255, 134, 122, 0.3),
          accentColor: const Color(0xFFFF6B22),
          panelBg: const Color.fromRGBO(255, 249, 245, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFFFF3E0),
          isDark: false,
        );
      case 'pink':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(255, 182, 193, 0.4),
          bgGrad2: const Color.fromRGBO(255, 105, 180, 0.2),
          accentColor: const Color(0xFFFF4785),
          panelBg: const Color.fromRGBO(255, 245, 248, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFFCE4EC),
          isDark: false,
        );
      case 'cyan':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(0, 229, 255, 0.2),
          bgGrad2: const Color.fromRGBO(0, 150, 136, 0.25),
          accentColor: const Color(0xFF009688),
          panelBg: const Color.fromRGBO(240, 253, 250, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFE0F2F1),
          isDark: false,
        );
      case 'gold':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(255, 215, 0, 0.3),
          bgGrad2: const Color.fromRGBO(218, 165, 32, 0.3),
          accentColor: const Color(0xFFD4AF37),
          panelBg: const Color.fromRGBO(255, 253, 240, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFFFFDE7),
          isDark: false,
        );
      case 'mint':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(0, 255, 170, 0.2),
          bgGrad2: const Color.fromRGBO(0, 200, 120, 0.2),
          accentColor: const Color(0xFF00B894),
          panelBg: const Color.fromRGBO(240, 255, 245, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFE8F8F5),
          isDark: false,
        );
      case 'rose':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(255, 150, 150, 0.2),
          bgGrad2: const Color.fromRGBO(255, 100, 120, 0.2),
          accentColor: const Color(0xFFFF7675),
          panelBg: const Color.fromRGBO(255, 245, 245, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFFFEFEF),
          isDark: false,
        );
      case 'lavender':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(162, 155, 254, 0.3),
          bgGrad2: const Color.fromRGBO(108, 92, 231, 0.2),
          accentColor: const Color(0xFFA29BFE),
          panelBg: const Color.fromRGBO(245, 245, 255, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFF0F0FA),
          isDark: false,
        );
      case 'slate':
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(150, 150, 150, 0.2),
          bgGrad2: const Color.fromRGBO(100, 100, 100, 0.2),
          accentColor: const Color(0xFF636E72),
          panelBg: const Color.fromRGBO(250, 250, 250, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFF1F2F6),
          isDark: false,
        );
      case 'green':
      default:
        return ThemeColors(
          bgGrad1: const Color.fromRGBO(105, 240, 174, 0.25),
          bgGrad2: const Color.fromRGBO(76, 175, 80, 0.25),
          accentColor: const Color(0xFF4CAF50),
          panelBg: const Color.fromRGBO(244, 253, 245, 0.6),
          textMain: const Color(0xFF1D1D1F),
          chatBg: const Color(0xFFF4FDF5),
          isDark: false,
        );
    }
  }
}
