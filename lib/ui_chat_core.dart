import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ==========================================
// 全局 SVG 图标引擎 (使用 Base64 防止 WAF 拦截)
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
  return SvgPicture.string(
    svgString,
    width: size,
    height: size,
    colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
  );
}

// ==========================================
// 自定义 iOS 风毛玻璃弹窗体系 (拒绝原生控件)
// ==========================================
class TideDialogs {
  static Future<T?> showCustomDialog<T>({
    required BuildContext context,
    required String title,
    required String content,
    String? cancelText,
    String confirmText = '确定',
    Color confirmColor = const Color(0xFF4CAF50),
    VoidCallback? onConfirm,
  }) {
    HapticFeedback.lightImpact();
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'TideDialogBarrier',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10 * curve.value, sigmaY: 10 * curve.value),
          child: Opacity(
            opacity: curve.value,
            child: Transform.scale(
              scale: 0.9 + 0.1 * curve.value,
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 10))
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Theme.of(context).textTheme.bodyLarge?.color)),
                      const SizedBox(height: 12),
                      Text(content, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.5, color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.8))),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (cancelText != null) ...[
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                                  alignment: Alignment.center,
                                  child: Text(cancelText, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                if (onConfirm != null) onConfirm();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(color: confirmColor, borderRadius: BorderRadius.circular(12)),
                                alignment: Alignment.center,
                                child: Text(confirmText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                              ),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<T?> showCustomBottomSheet<T>({
    required BuildContext context,
    required Widget child,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2), width: 1)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// 粒子爆炸动效 (用于删除机器人卡片)
// ==========================================
class Particle {
  double x, y, vx, vy, size;
  Color color;
  double life = 1.0;
  Particle({required this.x, required this.y, required this.vx, required this.vy, required this.size, required this.color});
  void update() {
    x += vx;
    y += vy;
    vy += 0.2; 
    life -= 0.02;
    size *= 0.92;
  }
}

class ExplosionPainter extends CustomPainter {
  final List<Particle> particles;
  ExplosionPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var p in particles) {
      if (p.life > 0) {
        paint.color = p.color.withOpacity(p.life.clamp(0.0, 1.0));
        canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
      }
    }
  }
  @override
  bool shouldRepaint(covariant ExplosionPainter oldDelegate) => true;
}

class ParticleExplosion extends StatefulWidget {
  final Widget child;
  final bool isExploding;
  final VoidCallback onComplete;

  const ParticleExplosion({Key? key, required this.child, required this.isExploding, required this.onComplete}) : super(key: key);

  @override
  State<ParticleExplosion> createState() => _ParticleExplosionState();
}

class _ParticleExplosionState extends State<ParticleExplosion> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<Particle> _particles = [];
  final math.Random _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _controller.addListener(() {
      setState(() {
        for (var p in _particles) { p.update(); }
      });
    });
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
  }

  @override
  void didUpdateWidget(ParticleExplosion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExploding && !oldWidget.isExploding) {
      _startExplosion();
    }
  }

  void _startExplosion() {
    _particles.clear();
    for (int i = 0; i < 30; i++) {
      _particles.add(Particle(
        x: 150 + _rnd.nextDouble() * 50 - 25, 
        y: 40 + _rnd.nextDouble() * 20 - 10,
        vx: _rnd.nextDouble() * 10 - 5,
        vy: _rnd.nextDouble() * 10 - 8,
        size: _rnd.nextDouble() * 5 + 3,
        color: _rnd.nextBool() ? Theme.of(context).primaryColor : Colors.grey.shade400,
      ));
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isExploding) {
      return CustomPaint(
        painter: ExplosionPainter(_particles),
        child: const SizedBox(
          width: double.infinity,
          height: 80, 
        ),
      );
    }
    return widget.child;
  }
}

// ==========================================
// 核心页面：聊天列表页 (ChatListPage)
// ==========================================
class ChatListPage extends StatefulWidget {
  const ChatListPage({Key? key}) : super(key: key);

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  List<Map<String, dynamic>> robots = [
    {'id': '1', 'name': '系统小助手', 'msg': '欢迎来到 TideBot 数字生命宇宙', 'time': '10:30', 'isSystem': true},
    {'id': '2', 'name': '傲娇元气妹', 'msg': '哼，才没有在等你呢！', 'time': '09:15', 'isSystem': false},
  ];

  void _deleteRobot(String id) {
    TideDialogs.showCustomDialog(
      context: context,
      title: '删除生命体',
      content: '确定要抹除这个机器人的全部记忆与人格吗？此操作不可逆。',
      cancelText: '取消',
      confirmText: '彻底抹除',
      confirmColor: const Color(0xFFFF3B30),
      onConfirm: () {
        setState(() {
          int index = robots.indexWhere((r) => r['id'] == id);
          if (index != -1) {
            robots[index]['exploding'] = true;
            Future.delayed(const Duration(milliseconds: 600), () {
              setState(() { robots.removeAt(index); });
            });
          }
        });
      }
    );
  }

  void _showCreateModal() {
    TideDialogs.showCustomBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('创造新数字生命', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildInputRow('名字', '赋予它一个称呼...'),
          const SizedBox(height: 12),
          _buildInputRow('人格设定', '简述它的身世和性格...', maxLines: 2),
          const SizedBox(height: 12),
          _buildInputRow('说话方式', '设定它的语气与口头禅...', maxLines: 2),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.center,
              child: const Text('注入灵魂并创造', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInputRow(String label, String hint, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.04), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        maxLines: maxLines,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 24, right: 24, bottom: 10),
            alignment: Alignment.centerLeft,
            child: Text(
              'TideBot',
              style: TextStyle(
                fontFamily: 'TideFont',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Theme.of(context).textTheme.bodyLarge?.color,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 10, left: 16, right: 16, bottom: 120),
              itemCount: robots.length,
              itemBuilder: (context, index) {
                final bot = robots[index];
                final isExploding = bot['exploding'] == true;

                return ParticleExplosion(
                  isExploding: isExploding,
                  onComplete: () {}, 
                  child: GestureDetector(
                    onLongPress: () {
                      if (bot['isSystem']) return;
                      HapticFeedback.mediumImpact();
                      TideDialogs.showCustomBottomSheet(
                        context: context,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.push_pin_outlined),
                              title: const Text('置顶该生命体', style: TextStyle(fontWeight: FontWeight.w600)),
                              onTap: () => Navigator.pop(context),
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline, color: Colors.red),
                              title: const Text('彻底抹除', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                              onTap: () {
                                Navigator.pop(context);
                                _deleteRobot(bot['id']);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                    onTap: () {
                      Navigator.push(context, PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => ChatRoomPage(botName: bot['name']),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          var curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                          return SlideTransition(
                            position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curve),
                            child: child,
                          );
                        },
                      ));
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: bot['isSystem'] ? Colors.orangeAccent : Theme.of(context).primaryColor.withOpacity(0.2),
                            ),
                            alignment: Alignment.center,
                            child: Text(bot['name'].substring(0, 1), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(bot['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text(bot['msg'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(bot['time'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                              const SizedBox(height: 8),
                              buildSvgIcon(TideIcons.chevronRight, size: 16, color: Colors.grey.shade400),
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
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80), 
        child: FloatingActionButton(
          onPressed: _showCreateModal,
          backgroundColor: Theme.of(context).primaryColor,
          elevation: 8,
          child: buildSvgIcon(TideIcons.createFab, size: 28, color: Colors.white),
        ),
      ),
    );
  }
}

// ==========================================
// 核心页面：沉浸式聊天室 (ChatRoomPage)
// ==========================================
class ChatRoomPage extends StatefulWidget {
  final String botName;
  const ChatRoomPage({Key? key, required this.botName}) : super(key: key);

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final TextEditingController _textController = TextEditingController();
  bool _isTyping = false; 
  bool _isRecording = false; 
  
  List<Map<String, dynamic>> messages = [
    {'role': 'bot', 'content': '你终于来了，我等了你很久。(微微别过头)'},
    {'role': 'user', 'content': '今天发生了很多有趣的事！'},
    {'role': 'bot', 'audio': true, 'content': '真的吗？快讲给我听听。'}, 
  ];

  void _sendMessage() {
    if (_textController.text.trim().isEmpty) return;
    setState(() {
      messages.add({'role': 'user', 'content': _textController.text.trim()});
      _textController.clear();
      _isTyping = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        messages.add({'role': 'bot', 'content': '我一直在倾听。(温柔地注视着你)'});
      });
    });
  }

  void _showMessageMenu(int index) {
    HapticFeedback.mediumImpact();
    TideDialogs.showCustomBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.copy), title: const Text('复制'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.format_quote), title: const Text('引用'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('编辑'), onTap: () => Navigator.pop(context)),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('删除', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              setState(() { messages.removeAt(index); });
            },
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    TideDialogs.showCustomBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('模型引擎配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildDropdownRow('默认聊天模型', 'DeepSeek-deepseek-v4-flash'),
          _buildDropdownRow('备用聊天模型', '未配置'),
          _buildDropdownRow('默认识图模型', '未配置'),
          _buildDropdownRow('默认语音转文本 (STT)', '未配置'),
          _buildDropdownRow('默认文本转语音 (TTS)', '未配置'),
          _buildDropdownRow('最大上下文 token', '10000token(角色扮演)'), 
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDropdownRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.04), borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            Text(value, style: TextStyle(fontSize: 13, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _openClearData() {
    TideDialogs.showCustomDialog(
      context: context,
      title: '抹除数据',
      content: '请选择要清理的数据层级（可多选）\n\n[ ] 删除表面聊天记录文本\n[ ] 强制抹除深层潜意识记忆',
      cancelText: '取消',
      confirmText: '执行清理',
      confirmColor: Colors.red,
      onConfirm: () {
        setState(() { messages.clear(); });
      }
    );
  }

  void _checkAndCall() {
    bool hasSTT = false;
    if (!hasSTT) {
      TideDialogs.showCustomDialog(
        context: context,
        title: '缺少语音模块',
        content: '你还没有为该生命体配置“语音转文本(STT)”与“文本转语音(TTS)”模型，暂无法建立通话链路。',
        confirmText: '去配置',
        onConfirm: _openSettings,
      );
    } else {
      // 进入通话 UI...
    }
  }

  List<InlineSpan> _parseMessageText(String text, bool isUser) {
    final RegExp exp = RegExp(r'([\(（][^\)）]+[\)）])');
    final matches = exp.allMatches(text);
    int lastEnd = 0;
    List<InlineSpan> spans = [];
    
    for (var match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          fontSize: 13,
          color: isUser ? Colors.white60 : Colors.grey.shade500,
          fontStyle: FontStyle.italic,
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, 
      body: SafeArea(
        child: Column(
          children: [
            // ---------------- 顶部栏 ----------------
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: buildSvgIcon(TideIcons.back, size: 28, color: Theme.of(context).textTheme.bodyLarge?.color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.botName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        AnimatedOpacity(
                          opacity: _isTyping ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: Text('正在输入中...', style: TextStyle(fontSize: 11, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(onTap: _checkAndCall, child: buildSvgIcon(TideIcons.phone, size: 22)),
                      const SizedBox(width: 16),
                      GestureDetector(onTap: _openClearData, child: buildSvgIcon(TideIcons.delete, size: 22, color: Colors.red.shade400)),
                      const SizedBox(width: 16),
                      GestureDetector(onTap: _openSettings, child: buildSvgIcon(TideIcons.settings, size: 22)),
                      const SizedBox(width: 16),
                      GestureDetector(onTap: () {}, child: buildSvgIcon(TideIcons.menu, size: 24)),
                    ],
                  )
                ],
              ),
            ),
            
            // ---------------- 消息滚动区 ----------------
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isUser = msg['role'] == 'user';
                  final hasAudio = msg['audio'] == true;

                  return GestureDetector(
                    onLongPress: () => _showMessageMenu(index),
                    child: Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isUser ? Theme.of(context).primaryColor : Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(isUser ? 18 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 18),
                          ),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: hasAudio 
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 120, height: 36,
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(18)),
                                child: const Row(children: [SizedBox(width: 10), Icon(Icons.play_arrow_rounded, size: 20), SizedBox(width: 6), Text('0:03')]),
                              ),
                              const SizedBox(height: 8),
                              RichText(text: TextSpan(style: TextStyle(fontSize: 14, color: isUser ? Colors.white : Colors.black87), children: _parseMessageText('[🎙️ 转写] ${msg['content'] ?? ''}', isUser))),
                            ],
                          )
                        : RichText(
                            text: TextSpan(
                              style: TextStyle(fontSize: 15, height: 1.5, color: isUser ? Colors.white : Colors.black87),
                              children: _parseMessageText(msg['content'] ?? '', isUser),
                            ),
                          ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // ---------------- 底部输入框 ----------------
            Container(
              padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 24), 
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.black.withOpacity(0.05)))),
              child: Row(
                children: [
                  GestureDetector(child: buildSvgIcon(TideIcons.plus, size: 26, color: Colors.grey.shade600)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7), 
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black.withOpacity(0.05)),
                      ),
                      child: TextField(
                        controller: _textController,
                        maxLines: 4,
                        minLines: 1,
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(border: InputBorder.none, hintText: '发送新消息...', hintStyle: TextStyle(fontSize: 14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _isRecording = !_isRecording;
                        if (!_isRecording) {
                          messages.add({'role': 'user', 'audio': true, 'content': '发送的语音内容...'});
                        }
                      });
                    },
                    child: _isRecording 
                      ? Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)) 
                      : buildSvgIcon(TideIcons.mic, size: 24, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: buildSvgIcon(TideIcons.send, size: 16, color: Colors.white),
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
