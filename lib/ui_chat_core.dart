import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'db.dart';

class TideIcons {
  static String get back => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTUgMThsLTYtNiA2LTYiLz48L3N2Zz4='));
  static String get menu => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48cGF0aCBkPSJNMyAxMmgxOE0zIDZoMThNMyAxOGgxOCIvPjwvc3ZnPg=='));
  static String get settings => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSI+PGNpcmNsZSBjeD0iMTIiIGN5PSIxMiIgcj0iMyIvPjxwYXRoIGQ9Ik0xOS40IDE1YTEuNjUgMS42NSAwIDAwLjMzIDEuODJsLjA2LjA2YTIgMiAwIDAxMCAyLjgzIDIgMiAwIDAxLTIuODMgMGwtLjA2LS4wNmExLjY1IDEuNjUgMCAwMC0xLjgyLS4zMyAxLjY1IDEuNjUgMCAwMC0xIDEuNTFWMjFhMiAyIDAgMDEtMiAyIDIgMiAwIDAxLTItMnYtLjA5QTEuNjUgMS42NSAwIDAwOSAxOS40YTEuNjUgMS42NSAwIDAwLTEuODIuMzNsLS4wNi4wNmEyIDIgMCAwMS0yLjgzIDAgMiAyIDAgMDEwLTIuODNsLjA2LjA2YTEuNjUgMS42NSAwIDAwLjMzLTEuODIgMS42NSAxLjY1IDAgMDAtMS41MS0xSDNhMiAyIDAgMDEtMi0yIDIgMiAwIDAxMi0yaC4wOUExLjY1IDEuNjUgMCAwMDQuNiA5YTEuNjUgMS42NSAwIDAwLS4zMy0xLjgybC0uMDYtLjA2YTIgMiAwIDAxMC0yLjgzIDIgMiAwIDAxMi44MyAwbC4wNi4wNmExLjY1IDEuNjUgMCAwMDEuODIuMzNIOWExLjY1IDEuNjUgMCAwMDEtMS41MVYzYTIgMiAwIDAxMi0yIDIgMiAwIDAxMiAydi4wOWExLjY1IDEuNjUgMCAwMDEgMS41MSAxLjY1IDEuNjUgMCAwMDEuODItLjMzbC4wNi0uMDZhMiAyIDAgMDEyLjgzIDAgMiAyIDAgMDEwIDIuODNsLS4wNi4wNmExLjY1IDEuNjUgMCAwMC0uMzMgMS44MlY5YTEuNjUgMS42NSAwIDAwMS41MSAxSDIxYTIgMiAwIDAxMiAyIDIgMiAwIDAxLTIgMmgtLjA5YTEuNjUgMS42NSAwIDAwLTEuNTEgMXoiLz48L3N2Zz4='));
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

// 独家弹窗体系，丝滑阻尼
class TideDialogs {
  static Future<T?> showCustomDialog<T>({
    required BuildContext context, required Widget child,
  }) {
    HapticFeedback.lightImpact();
    return showGeneralDialog<T>(
      context: context, barrierDismissible: true, barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim, secAnim) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, secAnim, _) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10 * curve.value, sigmaY: 10 * curve.value),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(curve),
            child: FadeTransition(opacity: curve, child: Dialog(backgroundColor: Colors.transparent, elevation: 0, child: child)),
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
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            color: Colors.white.withOpacity(0.95),
            child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(24), child: child)),
          ),
        ),
      ),
    );
  }
}

// 粒子爆炸效果器
class Particle {
  double x, y, vx, vy, size; Color color; double life = 1.0;
  Particle(this.x, this.y, this.vx, this.vy, this.size, this.color);
  void update() { x += vx; y += vy; vy += 0.3; life -= 0.03; size *= 0.9; }
}
class ExplosionPainter extends CustomPainter {
  final List<Particle> particles;
  ExplosionPainter(this.particles);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var p in particles) {
      if (p.life > 0) { paint.color = p.color.withOpacity(p.life.clamp(0.0, 1.0)); canvas.drawCircle(Offset(p.x, p.y), p.size, paint); }
    }
  }
  @override
  bool shouldRepaint(covariant ExplosionPainter oldDelegate) => true;
}
class ParticleExplosion extends StatefulWidget {
  final Widget child; final bool isExploding; final VoidCallback onComplete;
  const ParticleExplosion({Key? key, required this.child, required this.isExploding, required this.onComplete}) : super(key: key);
  @override State<ParticleExplosion> createState() => _ParticleExplosionState();
}
class _ParticleExplosionState extends State<ParticleExplosion> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<Particle> _particles = [];
  final math.Random _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _controller.addListener(() { setState(() { for (var p in _particles) p.update(); }); });
    _controller.addStatusListener((status) { if (status == AnimationStatus.completed) widget.onComplete(); });
  }

  @override
  void didUpdateWidget(ParticleExplosion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExploding && !oldWidget.isExploding) {
      _particles.clear();
      for (int i = 0; i < 20; i++) { // 限制粒子数量防卡顿
        _particles.add(Particle(150 + _rnd.nextDouble() * 50 - 25, 40 + _rnd.nextDouble() * 20 - 10, _rnd.nextDouble() * 10 - 5, _rnd.nextDouble() * 10 - 8, _rnd.nextDouble() * 4 + 2, Colors.grey.shade400));
      }
      _controller.forward(from: 0);
    }
  }

  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) { return widget.isExploding ? CustomPaint(painter: ExplosionPainter(_particles), child: const SizedBox(width: double.infinity, height: 80)) : widget.child; }
}


// ======================================================================
// 聊天列表页 
// ======================================================================
class ChatListPage extends StatefulWidget {
  const ChatListPage({Key? key}) : super(key: key);
  @override State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  List<Map<String, dynamic>> _bots = [];
  bool _isLoading = true;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _promptCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final data = await DBManager().getAllBots();
    setState(() { _bots = data.map((e) => Map<String, dynamic>.from(e)..putIfAbsent('exploding', () => false)).toList(); _isLoading = false; });
  }

  // ★ 真实打通数据库的创建逻辑 ★
  void _createBot() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final botId = 'bot_${DateTime.now().millisecondsSinceEpoch}';
    await DBManager().insertBot({
      'id': botId,
      'name': _nameCtrl.text.trim(),
      'desc': _descCtrl.text.trim(),
      'prompt': _promptCtrl.text.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    _nameCtrl.clear(); _descCtrl.clear(); _promptCtrl.clear();
    Navigator.pop(context);
    _loadData(); // 刷新列表
  }

  void _showCreateModal() {
    TideDialogs.showBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("创造新生命", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 24),
          _buildInput("名字", "给它一个称呼...", _nameCtrl),
          const SizedBox(height: 16),
          _buildInput("人格设定", "简述它的身世...", _descCtrl, maxLines: 3),
          const SizedBox(height: 16),
          _buildInput("说话方式", "设定语气口头禅...", _promptCtrl, maxLines: 2),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: _createBot, // 绑定真实创建函数
            child: Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(24)),
              alignment: Alignment.center,
              child: const Text("生成", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      )
    );
  }

  Widget _buildInput(String label, String hint, TextEditingController ctrl, {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: ctrl, maxLines: maxLines, minLines: 1,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(border: InputBorder.none, labelText: label, labelStyle: TextStyle(color: Colors.grey.shade500), hintText: hint),
      ),
    );
  }

  void _deleteBot(int index, String botId) {
    TideDialogs.showCustomDialog(
      context: context,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("彻底抹除", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text("此操作不可逆，确定删除该数字生命吗？", style: TextStyle(height: 1.5, color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消", style: TextStyle(color: Colors.black)))),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () async {
                    Navigator.pop(context);
                    setState(() { _bots[index]['exploding'] = true; }); // 触发爆炸
                  },
                  child: const Text("确认删除", style: TextStyle(color: Colors.white))
                )),
              ],
            )
          ],
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 极简顶部栏
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 20, left: 24, right: 24, bottom: 20),
            child: const Text('TideBot', style: TextStyle(fontFamily: 'TideFont', fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
          ),

          // 核心区：圆角大白卡片，包含列表
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(36), 
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))],
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
                          final isExploding = bot['exploding'] == true;
                          final name = bot['name'] ?? "未知";

                          return ParticleExplosion(
                            isExploding: isExploding,
                            onComplete: () async {
                              await DBManager().deleteBot(bot['id']);
                              _loadData();
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () {
                                HapticFeedback.mediumImpact();
                                TideDialogs.showBottomSheet(
                                  context: context,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(leading: const Icon(Icons.push_pin_outlined), title: const Text('置顶该生命体', style: TextStyle(fontWeight: FontWeight.w600)), onTap: () => Navigator.pop(context)),
                                      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('彻底删除', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)), onTap: () {
                                        Navigator.pop(context);
                                        _deleteBot(index, bot['id']);
                                      }),
                                    ],
                                  ),
                                );
                              },
                              onTap: () {
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
                                          Text("最新的消息占位...", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text("18:40", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade400)), 
                                        const SizedBox(height: 8),
                                        buildSvgIcon(TideIcons.chevronRight, size: 14, color: Colors.grey.shade400),
                                      ],
                                    )
                                  ],
                                ),
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
// 聊天室 (ChatRoomPage) 
// ======================================================================
class ChatRoomPage extends StatefulWidget {
  final Map<String, dynamic> botData;
  const ChatRoomPage({Key? key, required this.botData}) : super(key: key);
  @override State<ChatRoomPage> createState() => _ChatRoomPageState();
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
            const Text("请选择需要抹除的数据层级：\n[ ] 表面聊天记录\n[ ] 潜意识长期记忆", style: TextStyle(height: 1.5, color: Colors.grey)),
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

  void _openMenu() {
    TideDialogs.showBottomSheet(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade200), alignment: Alignment.center, child: Text(widget.botData['name']?.substring(0,1) ?? "A", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold))),
          const SizedBox(height: 16),
          Text(widget.botData['name'] ?? "未知", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          _buildMenuInfo("人格设定", widget.botData['desc'] ?? "无"),
          _buildMenuInfo("说话方式", widget.botData['prompt'] ?? "无"),
          const SizedBox(height: 40),
        ],
      )
    );
  }

  Widget _buildMenuInfo(String title, String val) {
    return Container(
      width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(val, style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final botName = widget.botData['name'] ?? "未知";

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), 
      body: SafeArea(
        child: Column(
          children: [
            // 1. 顶部栏 (四大金刚) - 纯平无阴影
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
                      GestureDetector(onTap: () {
                         TideDialogs.showCustomDialog(context: context, child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: const Text("未配置 STT/TTS，无法通话", textAlign: TextAlign.center)));
                      }, child: Padding(padding: const EdgeInsets.all(8.0), child: buildSvgIcon(TideIcons.phone, size: 22, color: Colors.black))),
                      GestureDetector(onTap: _openClearData, child: Padding(padding: const EdgeInsets.all(8.0), child: buildSvgIcon(TideIcons.delete, size: 22, color: Colors.black))),
                      GestureDetector(onTap: _openSettings, child: Padding(padding: const EdgeInsets.all(8.0), child: buildSvgIcon(TideIcons.settings, size: 22, color: Colors.black))),
                      GestureDetector(onTap: _openMenu, child: Padding(padding: const EdgeInsets.all(8.0), child: buildSvgIcon(TideIcons.menu, size: 24, color: Colors.black))),
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24), bottomRight: Radius.circular(24), bottomLeft: Radius.circular(4))),
                      child: const Text("这里是聊天室骨架，等待后续与大模型及数据库直连。"),
                    ),
                  )
                ],
              ),
            ),

            // 3. 底部输入区 (左侧+，右侧麦克风和发送，严格遵循要求)
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
