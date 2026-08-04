import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'db.dart';
import 'ui_chat_core.dart'; // 修复点：引入 TideDialogs 所在的包

class SpaceIcons {
  static String get gear => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSI+PHBhdGggZD0iTTEyIDE1YTMgMyAwIDEwMC02IDMgMyAwIDAwMCA2eiIvPjxwYXRoIGQ9Ik0xOS40IDE1YTEuNjUgMS42NSAwIDAwLjMzIDEuODJsLjA2LjA2YTIgMiAwIDAxMCAyLjgzIDIgMiAwIDAxLTIuODMgMGwtLjA2LS4wNmExLjY1IDEuNjUgMCAwMC0xLjgyLS4zMyAxLjY1IDEuNjUgMCAwMC0xIDEuNTFWMjFhMiAyIDAgMDEtMiAyIDIgMiAwIDAxLTItMnYtLjA5QTEuNjUgMS42NSAwIDAwOSAxOS40YTEuNjUgMS42NSAwIDAwLTEuODIuMzNsLS4wNi4wNmEyIDIgMCAwMS0yLjgzIDAgMiAyIDAgMDEwLTIuODNsLjA2LjA2YTEuNjUgMS42NSAwIDAwLjMzLTEuODIgMS42NSAxLjY1IDAgMDAtMS41MS0xSDNhMiAyIDAgMDEtMi0yIDIgMiAwIDAxMi0yaC4wOUExLjY1IDEuNjUgMCAwMDQuNiA5YTEuNjUgMS42NSAwIDAwLS4zMy0xLjgybC0uMDYtLjA2YTIgMiAwIDAxMC0yLjgzIDIgMiAwIDAxMi44MyAwbC4wNi4wNmExLjY1IDEuNjUgMCAwMDEuODIuMzNIOWExLjY1IDEuNjUgMCAwMDEtMS41MVYzYTIgMiAwIDAxMi0yIDIgMiAwIDAxMiAydi4wOWExLjY1IDEuNjUgMCAwMDEgMS41MSAxLjY1IDEuNjUgMCAwMDEuODItLjMzbC4wNi0uMDZhMiAyIDAgMDEyLjgzIDAgMiAyIDAgMDEwSURJdU9ETnNMUzR3Tmk0d05tRXhMalkxSURFdU5qVWdNQ0F3TUMwdU16TWdNUzQ0TWxZNVlURXVOalVnTVM0Mk5TQXdJREF3TVM0MU1TQXhTREl4WVRJZ01pQXdJREF4TWlBeUlESWdNaUF3SURBeExUSWdNbWd0TGpBNVlURXVOalVnTVM0Mk5TQXdJREF3TFRFdU5URWdNWG9pTHo0OEwzTjJaejQ9'));
  static String get switchDynamic => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSI+PHBhdGggZD0iTTIxIDExLjVhOC4zOCA4LjM4IDAgMDEtLjkgMy44IDguNSA4LjUgMCAwMS03LjYgNC43IDguMzggOC4zOCAwIDAxLTMuOC0uOUwzIDIxbDEuOS01LjdhOC4zOCA4LjM4IDAgMDEtLjktMy44IDguNSA4LjUgMCAwMTQuNy03LjYgOC4zOCA4LjM4IDAgMDEzLjgtLjloLjVhOC40OCA4LjQ4IDAgMDE4IDh2LjV6Ii8+PC9zdmc+'));
}

Widget renderSvg(String svgStr, {double size = 20, Color? color}) {
  return SvgPicture.string(svgStr, width: size, height: size, colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null);
}

// ======================================================================
// 空间页面 SpacePage
// ======================================================================
class SpacePage extends StatefulWidget {
  const SpacePage({Key? key}) : super(key: key);
  @override State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  String _userName = "创造者";
  String _botName = "未连接";
  bool _isLoading = true;
  
  // 日期：8月1日 星期六
  String get _currentDate {
    final now = DateTime.now();
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return "{now.month}月{now.day}日 {weekdays[now.weekday - 1]}";
  }
  
  // 时间：18:00
  String get _syncTime {
    final now = DateTime.now();
    return "{now.hour.toString().padLeft(2, '0')}:{now.minute.toString().padLeft(2, '0')}";
  }

  @override
  void initState() { super.initState(); _loadData(); }

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
            // 1. 顶部栏 (日期 + 时间 + 选机器人)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_currentDate, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                Row(
                  children: [
                    Text(_syncTime, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                         // TODO: 弹出机器人选择
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          children: [
                            Text(_botName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down, size: 16)
                          ],
                        )
                      ),
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 32),

            // 2. 今日一言卡片 (包含头像和简短文本)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))]),
              child: Row(
                children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade200), alignment: Alignment.center, child: Text(_botName.isNotEmpty ? _botName.substring(0,1) : "A", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 16),
                  Expanded(child: Text("这是一句由机器人凌晨自动生成的占位今日一言。", style: TextStyle(fontSize: 15, color: Colors.black87, height: 1.5, fontWeight: FontWeight.w500))),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. 相遇天数卡片
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("与$_userName的第 1 天", style: const TextStyle(fontFamily: 'TideFont', fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  Text("${DateTime.now().year}.${DateTime.now().month}.${DateTime.now().day} 这一天你们相遇了", style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. 今日心情 & 日程
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text("今日心情:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)), child: const Text("😊 开心", style: TextStyle(fontSize: 14, color: Colors.orange, fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text("今日日程", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  // 日程占位
                  Row(children: [Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)), const SizedBox(width: 8), const Text("下午 14:00 - 喝下午茶", style: TextStyle(fontSize: 15))]),
                  const SizedBox(height: 8),
                  Row(children: [Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)), const SizedBox(width: 8), const Text("晚上 20:00 - 睡前故事", style: TextStyle(fontSize: 15))]),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. 专属日记
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("专属日记", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey)
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("8月1日: 今天主人跟我说了一个很好笑的笑话...", style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5)),
                  const SizedBox(height: 8),
                  Text("7月31日: 陪他熬夜加班，感觉他很累。", style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5)),
                ],
              ),
            ),

            const SizedBox(height: 120), // 躲开 Dock
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// 广场页面 SquarePage (包含切换动画)
// ======================================================================
class SquarePage extends StatefulWidget {
  const SquarePage({Key? key}) : super(key: key);
  @override State<SquarePage> createState() => _SquarePageState();
}
class _SquarePageState extends State<SquarePage> {
  bool isGameMode = false;
  void _toggleMode() {
    HapticFeedback.mediumImpact();
    setState(() { isGameMode = !isGameMode; });
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isGameMode ? "小游戏" : "动态", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  GestureDetector(
                    onTap: _toggleMode,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: RotationTransition(turns: anim, child: child)),
                      child: Container(
                        key: ValueKey<bool>(isGameMode),
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                        child: renderSvg(SpaceIcons.switchDynamic, color: Colors.white, size: 20),
                      ),
                    ),
                  )
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(animation), child: child)),
                child: isGameMode 
                  ? ListView(
                      key: const ValueKey("game"), padding: const EdgeInsets.all(16),
                      children: [
                        _buildGameCard("五子棋", "经典双人对弈", Colors.blue.shade50),
                        _buildGameCard("井字棋", "轻松休闲AI随时奉陪", Colors.orange.shade50),
                        _buildGameCard("20问猜物", "互猜谜底看谁知识广", Colors.purple.shade50),
                        _buildGameCard("32张棋牌", "无大小王真实算力决胜", Colors.teal.shade50),
                      ],
                    ) 
                  : ListView(
                      key: const ValueKey("dynamic"), padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
                          child: const Text("动态流占位符：用户发布图片和文字，机器人随机评论、点赞。具体实现见后续。"),
                        )
                      ],
                    ),
              ),
            )
          ],
        ),
      ),
      floatingActionButton: isGameMode ? null : Padding(
        padding: const EdgeInsets.only(bottom: 85),
        child: FloatingActionButton(
          onPressed: () {}, backgroundColor: Colors.black, child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildGameCard(String title, String desc, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(32)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text(desc, style: TextStyle(fontSize: 15, color: Colors.black.withOpacity(0.6))),
      ]),
    );
  }
}

// ======================================================================
// 我的页面 ProfilePage (API 设置等)
// ======================================================================
class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  void _openAPI(BuildContext context) {
    TideDialogs.showBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("API 配置", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          const Text("文本/识图/生图/STT 模型池", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)), child: const Text("支持 DeepSeek, siliconflow, Kimi, 自定义 OpenAI 等 (点击新增)")),
          const SizedBox(height: 24),
          const Text("TTS 模型池", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)), child: const Text("支持 siliconflow, 阿里云百炼, MiniMax, 自定义等")),
          const SizedBox(height: 32),
        ],
      )
    );
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            // 1. 头像名片
            Container(
              padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
              child: Row(
                children: [
                  Container(width: 64, height: 64, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade200), child: const Icon(Icons.person, size: 32, color: Colors.grey)),
                  const SizedBox(width: 16),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("创造者", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)), Text("点击编辑资料", style: TextStyle(color: Colors.grey))])
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // 2. 设置列表
            _buildSettingRow("API 设置", onTap: () => _openAPI(context)),
            _buildSettingRow("本地模型", onTap: (){}),
            _buildSettingRow("主题设置", onTap: (){}),
            _buildSettingRow("聊天背景", onTap: (){}),
            _buildSettingRow("绑定微信", onTap: (){}),
            const SizedBox(height: 24),
            _buildSettingRow("普通设置", onTap: (){}),
            _buildSettingRow("高级设置", onTap: (){}),
            _buildSettingRow("插件市场", onTap: (){}),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow(String title, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey)]),
      ),
    );
  }
}
