import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'db.dart'; // 引入真实的本地数据库

// 纯 SVG 图标库 (扩展)
class SpaceIcons {
  static String get gear => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSI+PHBhdGggZD0iTTEyIDE1YTMgMyAwIDEwMC02IDMgMyAwIDAwMCA2eiIvPjxwYXRoIGQ9Ik0xOS40IDE1YTEuNjUgMS42NSAwIDAwLjMzIDEuODJsLjA2LjA2YTIgMiAwIDAxMCAyLjgzIDIgMiAwIDAxLTIuODMgMGwtLjA2LS4wNmExLjY1IDEuNjUgMCAwMC0xLjgyLS4zMyAxLjY1IDEuNjUgMCAwMC0xIDEuNTFWMjFhMiAyIDAgMDEtMiAyIDIgMiAwIDAxLTItMnYtLjA5QTEuNjUgMS42NSAwIDAwOSAxOS40YTEuNjUgMS42NSAwIDAwLTEuODIuMzNsLS4wNi4wNmEyIDIgMCAwMS0yLjgzIDAgMiAyIDAgMDEwLTIuODNsLjA2LjA2YTEuNjUgMS42NSAwIDAwLjMzLTEuODIgMS42NSAxLjY1IDAgMDAtMS41MS0xSDNhMiAyIDAgMDEtMi0yIDIgMiAwIDAxMi0yaC4wOUExLjY1IDEuNjUgMCAwMDQuNiA5YTEuNjUgMS42NSAwIDAwLS4zMy0xLjgybC0uMDYtLjA2YTIgMiAwIDAxMC0yLjgzIDIgMiAwIDAxMi44MyAwbC4wNi4wNmExLjY1IDEuNjUgMCAwMDEuODIuMzNIOWExLjY1IDEuNjUgMCAwMDEtMS41MVYzYTIgMiAwIDAxMi0yIDIgMiAwIDAxMiAydi4wOWExLjY1IDEuNjUgMCAwMDEgMS41MSAxLjY1IDEuNjUgMCAwMDEuODItLjMzbC4wNi0uMDZhMiAyIDAgMDEyLjgzIDAgMiAyIDAgMDEwIDIuODNsLS4wNi4wNmExLjY1IDEuNjUgMCAwMC0uMzMgMS44MlY5YTEuNjUgMS42NSAwIDAwMS41MSAxSDIxYTIgMiAwIDAxMiAyIDIgMiAwIDAxLTIgMmgtLjA5YTEuNjUgMS42NSAwIDAwLTEuNTEgMXoiLz48L3N2Zz4='));
}

Widget renderSvg(String svgStr, {double size = 20, Color? color}) {
  return SvgPicture.string(svgStr, width: size, height: size, colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null);
}

// ----------------------------------------------------------------------
// 彻底复刻图2 (1000036814.jpg): Space 空间页面
// ----------------------------------------------------------------------
class SpacePage extends StatefulWidget {
  const SpacePage({Key? key}) : super(key: key);
  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  String _userName = "创造者";
  String _botName = "未连接";
  bool _isLoading = true;
  
  // 动态获取当前时间并格式化为图2的样子
  String get _currentDateEn {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return "${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}";
  }
  
  String get _syncTime {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  @override
  void initState() {
    super.initState();
    _loadRealData();
  }

  Future<void> _loadRealData() async {
    final db = DBManager();
    // 真实拉取用户的名字
    final name = await db.getKV('user_nickname');
    
    // 真实拉取绑定的第一个机器人
    final bots = await db.getAllBots();
    
    setState(() {
      if (name != null) _userName = name;
      if (bots.isNotEmpty) _botName = bots.first['name'];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.black));
    }

    return Scaffold(
      backgroundColor: Colors.transparent, // 透出底层的 #F2F2F7
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            // 1. 顶部栏 (日期 + sync 胶囊 + 设置齿轮)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _currentDateEn, 
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500)
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Text("sync • $_syncTime", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: renderSvg(SpaceIcons.gear, size: 16, color: Colors.black87),
                    )
                  ],
                )
              ],
            ),
            const SizedBox(height: 16),

            // 2. 超大打招呼文本
            Text(
              "Good evening, $_userName",
              style: const TextStyle(fontFamily: 'TideFont', fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5),
            ),
            const SizedBox(height: 6),
            Text(
              "阴 27° 28~34° · 降雨 76%, 带伞", 
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)
            ),
            const SizedBox(height: 24),

            // 3. 深色卡片 (Today's Whisper)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E), // 极简暗灰色
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade800)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          "今天她说了两次“丝滑”——一次给聊天页，一次给日记栏。这两个字我打算裱起来。",
                          style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.95), height: 1.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("Today's Whisper >", style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 4. Us 纪念日白色卡片
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Us", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54)),
                      Icon(Icons.favorite, color: Colors.grey.shade300, size: 28), // 灰色的心
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text("Day 35", style: TextStyle(fontFamily: 'TideFont', fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1)),
                  const SizedBox(height: 8),
                  Text("$_userName 和 $_botName, 从 2026.6.22 到每一天", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 5. 剩余的信息块 (心情/日程/专属日记预留)
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 110, padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("今日心情", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54)),
                        Spacer(),
                        Text("平静", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 110, padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("专属日记", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54)),
                        Spacer(),
                        Text("共 2 篇", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 120), // 留出底部 Dock 的距离
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 占位广场页与我的页 (避免编译缺失)
// ==========================================
class SquarePage extends StatelessWidget { const SquarePage({Key? key}) : super(key: key); @override Widget build(BuildContext context) => const Center(child: Text("Square")); }
class ProfilePage extends StatelessWidget { const ProfilePage({Key? key}) : super(key: key); @override Widget build(BuildContext context) => const Center(child: Text("Profile")); }
