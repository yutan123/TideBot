import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'db.dart';

class SpaceIcons {
  static String get gear => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSI+PHBhdGggZD0iTTEyIDE1YTMgMyAwIDEwMC02IDMgMyAwIDAwMCA2eiIvPjxwYXRoIGQ9Ik0xOS40IDE1YTEuNjUgMS42NSAwIDAwLjMzIDEuODJsLjA2LjA2YTIgMiAwIDAxMCAyLjgzIDIgMiAwIDAxLTIuODMgMGwtLjA2LS4wNmExLjY1IDEuNjUgMCAwMC0xLjgyLS4zMyAxLjY1IDEuNjUgMCAwMC0xIDEuNTFWMjFhMiAyIDAgMDEtMiAyIDIgMiAwIDAxLTItMnYtLjA5QTEuNjUgMS42NSAwIDAwOSAxOS40YTEuNjUgMS42NSAwIDAwLTEuODIuMzNsLS4wNi4wNmEyIDIgMCAwMS0yLjgzIDAgMiAyIDAgMDEwLTIuODNsLjA2LjA2YTEuNjUgMS42NSAwIDAwLjMzLTEuODIgMS42NSAxLjY1IDAgMDAtMS41MS0xSDNhMiAyIDAgMDEtMi0yIDIgMiAwIDAxMi0yaC4wOUExLjY1IDEuNjUgMCAwMDQuNiA5YTEuNjUgMS42NSAwIDAwLS4zMy0xLjgybC0uMDYtLjA2YTIgMiAwIDAxMC0yLjgzIDIgMiAwIDAxMi44MyAwbC4wNi4wNmExLjY1IDEuNjUgMCAwMDEuODIuMzNIOWExLjY1IDEuNjUgMCAwMDEtMS41MVYzYTIgMiAwIDAxMi0yIDIgMiAwIDAxMiAydi4wOWExLjY1IDEuNjUgMCAwMDEgMS41MSAxLjY1IDEuNjUgMCAwMDEuODItLjMzbC4wNi0uMDZhMiAyIDAgMDEyLjgzIDAgMiAyIDAgMDEwSURJdU9ETnNMUzR3Tmk0d05tRXhMalkxSURFdU5qVWdNQ0F3TUMwdU16TWdNUzQ0TWxZNVlURXVOalVnTVM0Mk5TQXdJREF3TVM0MU1TQXhTREl4WVRJZ01pQXdJREF4TWlBeUlESWdNaUF3SURBeExUSWdNbWd0TGpBNVlURXVOalVnTVM0Mk5TQXdJREF3TFRFdU5URWdNWG9pTHo0OEwzTjJaejQ9'));
}

Widget renderSvg(String svgStr, {double size = 20, Color? color}) {
  return SvgPicture.string(svgStr, width: size, height: size, colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null);
}

// ======================================================================
// 界面二：Space 空间页面 (对照图 2 像素级复刻)
// ======================================================================
class SpacePage extends StatefulWidget {
  const SpacePage({Key? key}) : super(key: key);
  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  String _userName = "创造者";
  String _botName = "未连接";
  bool _isLoading = true;
  
  // 生成图2要求的日期格式
  String get _currentDateEn {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return "{weekdays[now.weekday - 1]}, {months[now.month - 1]} {now.day}";
  }
  
  String get _syncTime {
    final now = DateTime.now();
    return "{now.hour.toString().padLeft(2, '0')}:{now.minute.toString().padLeft(2, '0')}";
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DBManager();
    final bots = await db.getAllBots();
    setState(() {
      if (bots.isNotEmpty) _botName = bots.first['name'];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Colors.black));

    return Scaffold(
      backgroundColor: Colors.transparent, 
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            // 1. 顶部日期与同步栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_currentDateEn, style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Text("sync • $_syncTime", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: renderSvg(SpaceIcons.gear, size: 16, color: Colors.black87),
                    )
                  ],
                )
              ],
            ),
            const SizedBox(height: 20),

            // 2. 超大打招呼文本
            Text("Good evening, $_userName", style: const TextStyle(fontFamily: 'TideFont', fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1)),
            const SizedBox(height: 8),
            Text("阴 27° 28~34° · 降雨 76%, 带伞", style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            const SizedBox(height: 32),

            // 3. 深色卡片 (Today's Whisper)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(32)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade800)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text("这里是机器人每天凌晨自动生成的专属今日一言占位符。", style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.95), height: 1.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text("Today's Whisper >", style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. Us 纪念日白色卡片
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Us", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black54)),
                      Icon(Icons.favorite, color: Colors.grey.shade200, size: 32),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text("Day 35", style: TextStyle(fontFamily: 'TideFont', fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1)),
                  const SizedBox(height: 12),
                  Text("$_userName 和 $_botName, 从 2026.8.1 到每一天", style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. 底部双开信息块 (今日心情 / 专属日记)
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 120, padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("今日心情", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black54)),
                        Spacer(),
                        Text("平静", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 120, padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("专属日记", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black54)),
                        Spacer(),
                        Text("共 2 篇", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 120), // 躲开 Dock
          ],
        ),
      ),
    );
  }
}

// 预留广场页与我的页占位
class SquarePage extends StatelessWidget { const SquarePage({Key? key}) : super(key: key); @override Widget build(BuildContext context) => const Center(child: Text("Square", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))); }
class ProfilePage extends StatelessWidget { const ProfilePage({Key? key}) : super(key: key); @override Widget build(BuildContext context) => const Center(child: Text("Profile (Diary/Settings)", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))); }
