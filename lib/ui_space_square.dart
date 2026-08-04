import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'db.dart';
import 'ui_chat_core.dart'; // 引入极简弹窗

class SpaceIcons {
  static String get gear => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSI+PHBhdGggZD0iTTEyIDE1YTMgMyAwIDEwMC02IDMgMyAwIDAwMCA2eiIvPjxwYXRoIGQ9Ik0xOS40IDE1YTEuNjUgMS42NSAwIDAwLjMzIDEuODJsLjA2LjA2YTIgMiAwIDAxMCAyLjgzIDIgMiAwIDAxLTIuODMgMGwtLjA2LS4wNmExLjY1IDEuNjUgMCAwMC0xLjgyLS4zMyAxLjY1IDEuNjUgMCAwMC0xIDEuNTFWMjFhMiAyIDAgMDEtMiAyIDIgMiAwIDAxLTItMnYtLjA5QTEuNjUgMS42NSAwIDAwOSAxOS40YTEuNjUgMS42NSAwIDAwLTEuODIuMzNsLS4wNi4wNmEyIDIgMCAwMS0yLjgzIDAgMiAyIDAgMDEwLTIuODNsLjA2LjA2YTEuNjUgMS42NSAwIDAwLjMzLTEuODIgMS42NSAxLjY1IDAgMDAtMS41MS0xSDNhMiAyIDAgMDEtMi0yIDIgMiAwIDAxMi0yaC4wOUExLjY1IDEuNjUgMCAwMDQuNiA5YTEuNjUgMS42NSAwIDAwLS4zMy0xLjgybC0uMDYtLjA2YTIgMiAwIDAxMC0yLjgzIDIgMiAwIDAxMi44MyAwbC4wNi4wNmExLjY1IDEuNjUgMCAwMDEuODIuMzNIOWExLjY1IDEuNjUgMCAwMDEtMS41MVYzYTIgMiAwIDAxMi0yIDIgMiAwIDAxMiAydi4wOWExLjY1IDEuNjUgMCAwMDEgMS41MSAxLjY1IDEuNjUgMCAwMDEuODItLjMzbC4wNi0uMDZhMiAyIDAgMDEyLjgzIDAgMiAyIDAgMDEwSURJdU9ETnNMUzR3Tmk0d05tRXhMalkxSURFdU5qVWdNQ0F3TUMwdU16TWdNUzQ0TWxZNVlURXVOalVnTVM0Mk5TQXdJREF3TVM0MU1TQXhTREl4WVRJZ01pQXdJREF4TWlBeUlESWdNaUF3SURBeExUSWdNbWd0TGpBNVlURXVOalVnTVM0Mk5TQXdJREF3TFRFdU5URWdNWG9pTHo0OEwzTjJaejQ9'));
  static String get switchDynamic => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSI+PHBhdGggZD0iTTIxIDExLjVhOC4zOCA4LjM4IDAgMDEtLjkgMy44IDguNSA4LjUgMCAwMS03LjYgNC43IDguMzggOC4zOCAwIDAxLTMuOC0uOUwzIDIxbDEuOS01LjdhOC4zOCA4LjM4IDAgMDEtLjktMy44IDguNSA4LjUgMCAwMTQuNy03LjYgOC4zOCA4LjM4IDAgMDEzLjgtLjloLjVhOC40OCA4LjQ4IDAgMDE4IDh2LjV6Ii8+PC9zdmc+'));
}

Widget renderSvg(String svgStr, {double size = 20, Color? color}) {
  return SvgPicture.string(svgStr, width: size, height: size, colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null);
}

// ======================================================================
// 空间页面 SpacePage (尺寸调小)
// ======================================================================
class SpacePage extends StatefulWidget {
  const SpacePage({Key? key}) : super(key: key);
  @override State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  String _userName = "创造者";
  String _botName = "未连接";
  bool _isLoading = true;
  
  String get _currentDate {
    final now = DateTime.now();
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return "${now.month}月${now.day}日 ${weekdays[now.weekday - 1]}";
  }
  
  String get _syncTime {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_currentDate, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                Row(
                  children: [
                    Text(_syncTime, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          Text(_botName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 2),
                          const Icon(Icons.keyboard_arrow_down, size: 14)
                        ],
                      )
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 24),

            // 今日一言
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 16, offset: const Offset(0, 8))]),
              child: Row(
                children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade200), alignment: Alignment.center, child: Text(_botName.isNotEmpty ? _botName.substring(0,1) : "A", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 12),
                  const Expanded(child: Text("这是一句由机器人凌晨自动生成的占位今日一言。", style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5, fontWeight: FontWeight.w500))),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 相遇天数
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 16, offset: const Offset(0, 8))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("与$_userName的第 1 天", style: const TextStyle(fontFamily: 'TideFont', fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text("${DateTime.now().year}.${DateTime.now().month}.${DateTime.now().day} 这一天你们相遇了", style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 心情日程
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 16, offset: const Offset(0, 8))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text("今日心情:", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)), child: const Text("😊 开心", style: TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text("今日日程", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Row(children: [Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)), const SizedBox(width: 8), const Text("下午 14:00 - 喝下午茶", style: TextStyle(fontSize: 14))]),
                  const SizedBox(height: 6),
                  Row(children: [Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)), const SizedBox(width: 8), const Text("晚上 20:00 - 睡前故事", style: TextStyle(fontSize: 14))]),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 专属日记
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 16, offset: const Offset(0, 8))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("专属日记", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text("8月1日: 今天主人跟我说了一个很好笑的笑话...", style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5)),
                  const SizedBox(height: 6),
                  Text("7月31日: 陪他熬夜加班，感觉他很累。", style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// 广场页面 SquarePage 
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isGameMode ? "小游戏" : "动态", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  GestureDetector(
                    onTap: _toggleMode,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: RotationTransition(turns: anim, child: child)),
                      child: Container(
                        key: ValueKey<bool>(isGameMode),
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                        child: renderSvg(SpaceIcons.switchDynamic, color: Colors.white, size: 18),
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
                          padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                          child: const Text("动态流占位符：用户发布图片和文字，机器人随机评论、点赞。具体实现见后续。", style: TextStyle(fontSize: 14)),
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
          onPressed: () {}, backgroundColor: Colors.black, elevation: 8, child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildGameCard(String title, String desc, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text(desc, style: TextStyle(fontSize: 14, color: Colors.black.withOpacity(0.6))),
      ]),
    );
  }
}

// ======================================================================
// 我的页面 ProfilePage (API 设置真实连通)
// ======================================================================
class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  void _openAPI(BuildContext context) {
    TideDialogs.showBottomSheet(
      context: context,
      child: const APIConfigSheet(),
    );
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Container(
              padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
              child: Row(
                children: [
                  Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade200), child: const Icon(Icons.person, size: 28, color: Colors.grey)),
                  const SizedBox(width: 16),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("创造者", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), SizedBox(height:4), Text("点击编辑资料", style: TextStyle(color: Colors.grey, fontSize: 13))])
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSettingRow("API 设置", onTap: () => _openAPI(context)),
            _buildSettingRow("本地模型", onTap: (){}),
            _buildSettingRow("主题设置", onTap: (){}),
            _buildSettingRow("聊天背景", onTap: (){}),
            _buildSettingRow("绑定微信", onTap: (){}),
            const SizedBox(height: 20),
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
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)), const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)]),
      ),
    );
  }
}

// ======================================================================
// API 真实配置弹窗 (打通真实存取和测速)
// ======================================================================
class APIConfigSheet extends StatefulWidget {
  const APIConfigSheet({Key? key}) : super(key: key);
  @override State<APIConfigSheet> createState() => _APIConfigSheetState();
}

class _APIConfigSheetState extends State<APIConfigSheet> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();
  String _provider = "DeepSeek";
  String _testStatus = "";

  void _testConnection() async {
    setState(() { _testStatus = "测试中..."; });
    try {
      final url = _urlCtrl.text.trim();
      final key = _keyCtrl.text.trim();
      if (url.isEmpty || key.isEmpty) { setState(() { _testStatus = "请填写完整"; }); return; }

      final res = await http.post(
        Uri.parse("$url/chat/completions"),
        headers: {"Content-Type": "application/json", "Authorization": "Bearer $key"},
        body: jsonEncode({"model": "deepseek-chat", "messages": [{"role": "user", "content": "1"}], "max_tokens": 5}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) { setState(() { _testStatus = "连接成功！"; }); } 
      else { setState(() { _testStatus = "失败: ${res.statusCode}"; }); }
    } catch (e) {
      setState(() { _testStatus = "连接超时/异常"; });
    }
  }

  void _save() async {
    await DBManager().setKV('api_provider_$_provider', jsonEncode({'url': _urlCtrl.text, 'key': _keyCtrl.text}));
    Navigator.pop(context);
  }

  @override Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("大模型 API 配置", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _provider, isExpanded: true,
              items: ["DeepSeek", "Siliconflow", "Kimi", "自定义"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
              onChanged: (v) { setState(() { _provider = v!; }); },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)),
          child: TextField(controller: _urlCtrl, decoration: const InputDecoration(border: InputBorder.none, labelText: "Base URL", hintText: "https://api.deepseek.com")),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)),
          child: TextField(controller: _keyCtrl, obscureText: true, decoration: const InputDecoration(border: InputBorder.none, labelText: "API Key", hintText: "sk-...")),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_testStatus, style: TextStyle(color: _testStatus.contains("成功") ? Colors.green : Colors.red, fontWeight: FontWeight.w600, fontSize: 13)),
            Row(
              children: [
                TextButton(onPressed: _testConnection, child: const Text("测试连通性", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black), onPressed: _save, child: const Text("保存并使用", style: TextStyle(color: Colors.white))),
              ],
            )
          ],
        )
      ],
    );
  }
}
