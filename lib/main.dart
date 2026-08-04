import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'ui_chat_core.dart'; 
import 'ui_space_square.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: [SystemUiOverlay.top]);
  runApp(const TideBotApp());
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
      notificationChannelId: 'tide_bot_alive',
      initialNotificationTitle: 'TideBot', initialNotificationContent: '数字生命引擎已连接', foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
  service.startService();
}

class TideBotApp extends StatelessWidget {
  const TideBotApp({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TideBot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'TideFont', // 必须使用自定义字体
        scaffoldBackgroundColor: const Color(0xFFF5F5F7), // iOS灰底
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
        useMaterial3: true,
      ),
      home: const TideMainScaffold(), 
    );
  }
}

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
    final dockWidth = screenWidth * 0.92; 
    final tabWidth = dockWidth / _tabs.length;      

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: const [ChatListPage(), SpacePage(), SquarePage(), ProfilePage()],
      ),
      // 绝对还原你的要求：悬浮流光滑动导航
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  width: dockWidth, height: 68,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.white.withOpacity(0.8), width: 1)),
                  child: Stack(
                    children: [
                      // 滑动的流光白块
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.fastOutSlowIn, // 丝滑过渡
                        top: 6, bottom: 6,
                        left: _currentIndex * tabWidth + 6,
                        width: tabWidth - 12,
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))]),
                        ),
                      ),
                      // 文字层
                      Row(
                        children: List.generate(_tabs.length, (index) {
                          final isActive = _currentIndex == index;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () { HapticFeedback.lightImpact(); setState(() => _currentIndex = index); },
                            child: SizedBox(
                              width: tabWidth,
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
        ),
      ),
    );
  }
}