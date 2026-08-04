import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'db.dart'; // 引入真实的本地数据库

// ==========================================
// 全局 SVG 图标引擎
// ==========================================
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

// ----------------------------------------------------------------------
// 彻底复刻图1 (1000036813.jpg): Chats 聊天列表界面
// ----------------------------------------------------------------------
class ChatListPage extends StatefulWidget {
  const ChatListPage({Key? key}) : super(key: key);
  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  // 告别假数据，全部从 SQLite 读取
  List<Map<String, dynamic>> _bots = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRealData();
  }

  Future<void> _loadRealData() async {
    final db = DBManager();
    final data = await db.getAllBots();
    setState(() {
      _bots = data;
      _isLoading = false;
    });
  }

  void _showCreateModal() {
    // 留空待办：创建界面的弹窗，先不干涉列表 UI 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // 透出底层的 #F2F2F7
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部栏：Chats 标题 + 状态点
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 20, left: 24, right: 24, bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Chats',
                  style: TextStyle(
                    fontFamily: 'TideFont', 
                    fontSize: 34, 
                    fontWeight: FontWeight.w600, // 对应图1那种优雅的无衬线/粗体
                    letterSpacing: -0.5,
                  ),
                ),
                Row(
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    const Text('在线', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87)),
                  ],
                )
              ],
            ),
          ),

          // 核心区域：包裹所有列表项的巨大白色圆角卡片
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32), // 图1标志性的超大圆角
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                ),
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: Colors.black))
                  : _bots.isEmpty 
                    ? const Center(child: Text("空空如也，点击右下角创造数字生命", style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                        padding: const EdgeInsets.only(top: 10, bottom: 100),
                        itemCount: _bots.length,
                        separatorBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(left: 76, right: 20),
                          child: Divider(height: 1, color: Colors.grey.shade100), // 图1极浅的分割线
                        ),
                        itemBuilder: (context, index) {
                          final bot = _bots[index];
                          // 临时获取首字母做头像
                          final name = bot['name'] as String;
                          final avatarLabel = name.isNotEmpty ? name.substring(0, 1) : "A";

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              // TODO: 跳转聊天室
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              child: Row(
                                children: [
                                  // 头像
                                  Container(
                                    width: 48, height: 48,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.grey.shade200,
                                      image: bot['avatar_path'] != null 
                                          ? DecorationImage(image: NetworkImage(bot['avatar_path']), fit: BoxFit.cover)
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: bot['avatar_path'] == null 
                                        ? Text(avatarLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87))
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  // 名字与消息截断
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name, 
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          bot['desc'] ?? "暂无消息...", // 这里后续接真实的最近一条消息
                                          maxLines: 1, 
                                          overflow: TextOverflow.ellipsis, 
                                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 时间与箭头
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text("10:05", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade400)), // 24小时制，暂写死
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
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          onPressed: _showCreateModal,
          backgroundColor: Colors.black87, // 配合黑白极简风格
          elevation: 10,
          shape: const CircleBorder(),
          child: buildSvgIcon(TideIcons.createFab, size: 28, color: Colors.white),
        ),
      ),
    );
  }
}
