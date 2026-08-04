import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'db.dart';

// 全局 SVG 图标解析
class TideIcons {
  static String get back => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTUgMThsLTYtNiA2LTYiLz48L3N2Zz4='));
  static String get menu => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48cGF0aCBkPSJNMyAxMmgxOE0zIDZoMThNMyAxOGgxOCIvPjwvc3ZnPg=='));
  static String get settings => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIiPjxjaXJjbGUgY3g9IjEyIiBjeT0iMTIiIHI9IjMiLz48cGF0aCBkPSJNMTkuNCAxNWExLjY1IDEuNjUgMCAwMC4zMyAxLjgybC4wNi4wNmEyIDIgMCAwMTAgMi44MyAyIDIgMCAwMS0yLjgzIDBsLS4wNi0uMDZhMS42NSAxLjY1IDAgMDAtMS44Mi0uMzMgMS42NSAxLjY1IDAgMDAtMSAxLjUxVjIxYTIgMiAwIDAxLTIgMiAyIDIgMCAwMS0yLTJ2LS4wOUExLjY1IDEuNjUgMCAwMDkgMTkuNGExLjY1IDEuNjUgMCAwMC0xLjgyLjMzbC0uMDYuMDZhMiAyIDAgMDEtMi44MyAwIDIgMiAwIDAxMC0yLjgzbC4wNi4wNmExLjY1IDEuNjUgMCAwMC4zMy0xLjgyIDEuNjUgMS42NSAwIDAwLTEuNTEtMUgzYTIgMiAwIDAxLTItMiAyIDIgMCAwMTItMmguMDlBMS42NSAxLjY1IDAgMDA0LjYgOWExLjY1IDEuNjUgMCAwMC0uMzMtMS44MmwtLjA2LS4wNmEyIDIgMCAwMTAtMi44MyAyIDIgMCAwMTIuODMgMGwuMDYuMDZhMS42NSAxLjY1IDAgMDAxLjgyLjMzSDlhMS42NSAxLjY1IDAgMDAxLTEuNTFWM2EyIDIgMCAwMTItMiAyIDIgMCAwMTIgMnYuMDlhMS42NSAxLjY1IDAgMDAxIDEuNTEgMS42NSAxLjY1IDAgMDAxLjgyLS4zM2wuMDYtLjA2YTIgMiAwIDAxMi44MyAwIDIgMiAwIDAxMCAyLjgzbC0uMDYuMDZhMS42NSAxLjY1IDAgMDAtLjMzIDEuODJWOWExLjY1IDEuNjUgMCAwMDEuNTEgMUgyMWEyIDIgMCAwMTIgMiAyIDIgMCAwMS0yIDJoLS4wOWExLjY1IDEuNjUgMCAwMC0xLjUxIDF6Ii8+PC9zdmc+'));
  static String get delete => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48cGF0aCBkPSJNMyA2aDE4TTE5IDZ2MTRhMiAyIDAgMDEtMiAySDdhMiAyIDAgMDEtMi0yVjZtMyAwVjRhMiAyIDAgMDEyLTJoNGEyIDIgMCAwMTIgMnYyTTEwIDExdjZNMTQgMTF2NiIvPjwvc3ZnPg=='));
  static String get phone => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMjIgMTYuOTJ2M2EyIDIgMCAwMS0yLjE4IDIgMTkuNzkgMTkuNzkgMCAwMS04LjYzLTMuMDcgMTkuNSAxOS41IDAgMDEtNi02IDE5Ljc5IDE5Ljc5IDAgMDEtMy4wNy04LjY3QTIgMiAwIDAxNC4xMSAyaDNhMiAyIDAgMDEyIDEuNzIgMTIuODQgMTIuODQgMCAwMC43IDIuODEgMiAyIDAgMDEtLjQ1IDIuMTFMOC4wOSA5LjkxYTE2IDE2IDAgMDA2IDZsMS4yNy0xLjI3YTIgMiAwIDAxMi4xMS0uNDUgMTIuODQgMTIuODQgMCAwMDIuODEuN0EyIDIgMCAwMTIyIDE2LjkyeiIvPjwvc3ZnPg=='));
  static String get plus => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48cGF0aCBkPSJNMTIgNXYxNE01IDEyaDE0Ii8+PC9zdmc+'));
  static String get mic => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgMWEzIDMgMCAwMC0zIDN2OGEzIDMgMCAwMDYgMFY0YTMgMyAwIDAwLTMtM3oiLz48cGF0aCBkPSJNMTkgMTB2MmE3IDcgMCAwMS0xNCAwdi0yTTEyIDE5djRNOCAyM2g4Ii8+PC9zdmc+'));
  static String get send => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgMTlWNU01IDEybDctNyA3IDciLz48L3N2Zz4='));
  static String get chevronRight => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNOSAxOGw2LTYtNi02Ii8+PC9zdmc+'));
  static String get createFab => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48bGluZSB4MT0iMTIiIHkxPSI1IiB4Mj0iMTIiIHkyPSIxOSIvPjxsaW5lIHgxPSI1IiB5MT0iMTIiIHgyPSIxOSIgeTI9IjEyIi8+PC9zdmc+'));
}

Widget buildSvgIcon(String svgString, {double size = 24, Color? color}) {
  return SvgPicture.string(svgString, width: size, height: size, colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null);
}

// 自定义 iOS 风动画弹窗基座
class TideDialogs {
  static Future<T?> showCustomDialog<T>({
    required BuildContext context, required Widget child,
  }) {
    HapticFeedback.lightImpact();
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim, secAnim) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, secAnim, _) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15 * curve.value, sigmaY: 15 * curve.value),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(curve),
            child: FadeTransition(
              opacity: curve,
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<T?> showBottomSheet<T>({
    required BuildContext context, required Widget child,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            color: Colors.white.withOpacity(0.9),
            child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(24), child: child)),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// 界面一：Chats 聊天列表 (精确还原大圆角卡片)
// ======================================================================
class ChatListPage extends StatefulWidget {
  const ChatListPage({Key? key}) : super(key: key);
  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  List<Map<String, dynamic>> _bots = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await DBManager().getAllBots();
    setState(() { _bots = data; _isLoading = false; });
  }

  // 悬浮球创建机器人界面
  void _showCreateModal() {
    TideDialogs.showBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("创造新生命", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 24),
          _buildInput("名字", "给它一个称呼..."),
          const SizedBox(height: 16),
          _buildInput("人格设定", "简述它的身世...", maxLines: 3),
          const SizedBox(height: 16),
          _buildInput("说话方式", "设定语气口头禅...", maxLines: 2),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
              alignment: Alignment.center,
              child: const Text("生成", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      )
    );
  }

  Widget _buildInput(String label, String hint, {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)),
      child: TextField(
        maxLines: maxLines, minLines: 1,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          border: InputBorder.none, labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade500), hintText: hint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：极简标题
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 20, left: 24, right: 24, bottom: 20),
            child: const Text('TideBot', style: TextStyle(fontFamily: 'TideFont', fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
          ),

          // 核心区：包裹整个列表的大圆角白底卡片
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(36), // 极致大圆角
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: Colors.black))
                  : _bots.isEmpty 
                    ? const Center(child: Text("暂无连接，点击右下角创造", style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                        padding: const EdgeInsets.only(top: 10, bottom: 100),
                        itemCount: _bots.length,
                        separatorBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(left: 76, right: 20),
                          child: Divider(height: 1, color: Colors.grey.shade100),
                        ),
                        itemBuilder: (context, index) {
                          final bot = _bots[index];
                          final name = bot['name'] ?? "未知";
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              // 丝滑路由推入聊天室
                              Navigator.push(context, PageRouteBuilder(
                                pageBuilder: (context, anim, secAnim) => ChatRoomPage(botData: bot),
                                transitionsBuilder: (context, anim, secAnim, child) {
                                  var curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
                                  return SlideTransition(position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curve), child: child);
                                },
                              ));
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52, height: 52,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade200),
                                    alignment: Alignment.center,
                                    child: Text(name.substring(0, 1), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87, letterSpacing: -0.3)),
                                        const SizedBox(height: 4),
                                        Text("这是最新的消息...", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text("18:40", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade400)), // 24小时制
                                      const SizedBox(height: 8),
                                      buildSvgIcon(TideIcons.chevronRight, size: 14, color: Colors.grey.shade400),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
      // 悬浮创建球
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 85),
        child: FloatingActionButton(
          onPressed: _showCreateModal,
          backgroundColor: Colors.black, 
          elevation: 12,
          shape: const CircleBorder(),
          child: buildSvgIcon(TideIcons.createFab, size: 28, color: Colors.white),
        ),
      ),
    );
  }
}

// ======================================================================
// 界面二：沉浸式聊天室 (ChatRoomPage) 完整 UI 框架落地
// ======================================================================
class ChatRoomPage extends StatefulWidget {
  final Map<String, dynamic> botData;
  const ChatRoomPage({Key? key, required this.botData}) : super(key: key);
  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final TextEditingController _textController = TextEditingController();
  bool _isTyping = false;
  bool _isRecording = false;

  void _openSettings() {
    TideDialogs.showBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("引擎设置", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          _buildSetRow("默认聊天模型", "DeepSeek-deepseek-v4"),
          _buildSetRow("备用聊天模型", "未配置"),
          _buildSetRow("默认识图模型", "未配置"),
          _buildSetRow("默认 STT 模型", "未配置"),
          _buildSetRow("默认 TTS 模型", "未配置"),
          _buildSetRow("最大上下文 Token", "10000token"),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSetRow(String title, String val) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          Text(val, style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  void _openClearData() {
    TideDialogs.showCustomDialog(
      context: context,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, size: 40, color: Colors.red),
            const SizedBox(height: 16),
            const Text("抹除记忆", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text("请选择需要抹除的数据层级：
[ ] 表面聊天记录
[ ] 潜意识长期记忆", style: TextStyle(height: 1.5, color: Colors.grey)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消", style: TextStyle(color: Colors.black)))),
                Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context), child: const Text("执行抹除", style: TextStyle(color: Colors.white)))),
              ],
            )
          ],
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final botName = widget.botData['name'] ?? "未知";

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // 纯灰底色，若用户设置背景则需要额外挂载 Image
      body: SafeArea(
        child: Column(
          children: [
            // 1. 顶部栏 (四大金刚)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(padding: const EdgeInsets.all(8), child: buildSvgIcon(TideIcons.back, size: 28, color: Colors.black)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(botName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        if (_isTyping) const Text('正在输入中...', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(onTap: () {}, child: Padding(padding: const EdgeInsets.all(8.0), child: buildSvgIcon(TideIcons.phone, size: 22, color: Colors.black))),
                      GestureDetector(onTap: _openClearData, child: Padding(padding: const EdgeInsets.all(8.0), child: buildSvgIcon(TideIcons.delete, size: 22, color: Colors.black))),
                      GestureDetector(onTap: _openSettings, child: Padding(padding: const EdgeInsets.all(8.0), child: buildSvgIcon(TideIcons.settings, size: 22, color: Colors.black))),
                      GestureDetector(onTap: () {}, child: Padding(padding: const EdgeInsets.all(8.0), child: buildSvgIcon(TideIcons.menu, size: 24, color: Colors.black))),
                    ],
                  )
                ],
              ),
            ),
            
            // 2. 消息流占位
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(child: Text("Today 10:00", style: TextStyle(fontSize: 12, color: Colors.grey.shade400))),
                  const SizedBox(height: 20),
                  // Bot 消息示例
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomRight: Radius.circular(20), bottomLeft: Radius.circular(4))),
                      child: const Text("这里是聊天室骨架，等待后续与大模型及数据库直连。"),
                    ),
                  )
                ],
              ),
            ),

            // 3. 底部输入区 (含 +、录音、发送)
            Container(
              padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 24),
              decoration: BoxDecoration(color: const Color(0xFFF2F2F7), border: Border(top: BorderSide(color: Colors.black.withOpacity(0.03)))),
              child: Row(
                children: [
                  GestureDetector(child: Container(padding: const EdgeInsets.all(8), child: buildSvgIcon(TideIcons.plus, size: 26, color: Colors.grey.shade600))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.black.withOpacity(0.04))),
                      child: TextField(
                        controller: _textController, maxLines: 4, minLines: 1,
                        decoration: const InputDecoration(border: InputBorder.none, hintText: '发送新消息...', hintStyle: TextStyle(fontSize: 15, color: Colors.grey)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      setState(() { _isRecording = !_isRecording; });
                    },
                    child: Container(padding: const EdgeInsets.all(8), child: _isRecording ? Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)) : buildSvgIcon(TideIcons.mic, size: 26, color: Colors.grey.shade700)),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 36, height: 36,
                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20), // ↑ 箭头
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
