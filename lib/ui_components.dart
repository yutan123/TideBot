import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'theme.dart';

// ========== 全局弹性点击包装器 ==========
class BouncyTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleAmount;
  const BouncyTap({Key? key, required this.child, this.onTap, this.scaleAmount = 0.05}) : super(key: key);
  @override State<BouncyTap> createState() => _BouncyTapState();
}
class _BouncyTapState extends State<BouncyTap> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _scale;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 1.0 - widget.scaleAmount).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _c.addStatusListener((s) { if (s == AnimationStatus.completed) _c.reverse(); });
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { _c.forward(); HapticFeedback.lightImpact(); },
      onTapUp: (_) { _c.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(animation: _scale, builder: (c, child) => Transform.scale(scale: _scale.value, child: child), child: widget.child),
    );
  }
}

// ========== 自定义弹窗系统 ==========
Future<T?> showTideDialog<T>({required BuildContext context, required WidgetBuilder builder, bool barrierDismissible = true}) {
  return TideDialogs.show<T>(context: context, builder: builder, barrierDismissible: barrierDismissible);
}

class TideDialogs {
  static Future<T?> show<T>({required BuildContext context, required WidgetBuilder builder, bool barrierDismissible = true}) {
    return showGeneralDialog<T>(
      context: context, barrierDismissible: barrierDismissible, barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => builder(context),
      transitionBuilder: (context, anim, secAnim, child) =>
          ScaleTransition(scale: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic), child: FadeTransition(opacity: anim, child: child)),
    );
  }

  static Widget glassContent({required BuildContext context, required List<Widget> children, double maxWidth = 0.92}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: MediaQuery.of(context).size.width * maxWidth,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withOpacity(0.6), width: 0.5)),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children)),
        ),
      ),
    );
  }

  static Widget glassButton(String label, {required VoidCallback onTap, Color? color, Color textColor = Colors.white}) {
    return BouncyTap(
      onTap: onTap,
      child: Builder(builder: (ctx) {
        final c = color ?? TideTheme.of(ctx).primary;
        return Container(
          height: 44, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14)),
          child: Center(child: Text(label, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'TideFont'))),
        );
      }),
    );
  }
}

// ========== 底部弹窗（半屏） ==========
Future<T?> showTideSheet<T>({required BuildContext context, required Widget child, double? height}) {
  final screenH = MediaQuery.of(context).size.height;
  final sheetH = height ?? screenH * 0.55;
  return showModalBottomSheet<T>(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (ctx) => GestureDetector(
      onTap: () => Navigator.pop(ctx),
      child: Container(height: screenH, color: Colors.transparent, alignment: Alignment.bottomCenter,
        child: GestureDetector(onTap: () {}, child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(height: sheetH, width: double.infinity, decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(children: [
                const SizedBox(height: 8),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                Expanded(child: child),
              ]),
            ),
          ),
        )),
      ),
    ),
  );
}

// ========== 粒子系统 ==========
class Particle {
  double x, y, vx, vy, size; Color color; double life = 1.0;
  Particle(this.x, this.y, this.vx, this.vy, this.size, this.color);
  void update() { x += vx; y += vy; vy += 0.3; life -= 0.025; size *= 0.94; }
}
class ExplosionPainter extends CustomPainter {
  final List<Particle> ps;
  ExplosionPainter(this.ps);
  @override void paint(Canvas c, Size s) {
    final pt = Paint()..style = PaintingStyle.fill;
    for (var p in ps) { if (p.life > 0) { pt.color = p.color.withOpacity(p.life.clamp(0.0, 1.0)); c.drawCircle(Offset(p.x, p.y), p.size, pt); } }
  }
  @override bool shouldRepaint(covariant ExplosionPainter o) => true;
}
class ParticleOverlay extends StatefulWidget {
  final Widget child; final List<Offset> origins; final VoidCallback? onDone;
  const ParticleOverlay({Key? key, required this.child, required this.origins, this.onDone}) : super(key: key);
  @override State<ParticleOverlay> createState() => _ParticleOverlayState();
}
class _ParticleOverlayState extends State<ParticleOverlay> with SingleTickerProviderStateMixin {
  final List<Particle> _ps = []; late AnimationController _c;
  final _r = Random();
  bool _initialized = false;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _c.addListener(() => setState(() { for (var p in _ps) p.update(); }));
    _c.addStatusListener((s) { if (s == AnimationStatus.completed) widget.onDone?.call(); });
    _c.forward();
  }
  void _initParticles() {
    if (_initialized) return;
    _initialized = true;
    final theme = TideTheme.of(context);
    final colors = [
      theme.primary,
      theme.primaryLight,
      theme.primary.withOpacity(0.7),
      theme.primaryLight.withOpacity(0.5),
    ];
    for (var o in widget.origins) {
      for (int i = 0; i < 30; i++) { // 保持30个粒子
        final angle = _r.nextDouble() * 6.2832;
        final spd = 1.0 + _r.nextDouble() * 6;
        final sx = 1.5 + _r.nextDouble() * 5;
        final ox = (_r.nextDouble() - 0.5) * 80;
        final oy = (_r.nextDouble() - 0.5) * 50;
        _ps.add(Particle(o.dx + ox, o.dy + oy, cos(angle) * spd, sin(angle) * spd - 3, sx, colors[_r.nextInt(colors.length)]));
      }
    }
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _initParticles());
    return Stack(children: [widget.child, Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: ExplosionPainter(_ps))))]);
  }
}

// ========== 毛玻璃卡片 ==========
class GlassCard extends StatelessWidget {
  final Widget child; final EdgeInsetsGeometry padding; final double radius; final VoidCallback? onTap; final VoidCallback? onLongPress;
  const GlassCard({Key? key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 20, this.onTap, this.onLongPress}) : super(key: key);
  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, onLongPress: onLongPress,
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(padding: padding, decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(radius), border: Border.all(color: Colors.white.withOpacity(0.4), width: 0.5), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2))]), child: child),
      )),
    );
  }
}
class FrostCard extends StatelessWidget {
final Widget child; final EdgeInsetsGeometry padding; final EdgeInsetsGeometry margin; final double radius; final VoidCallback? onTap; final VoidCallback? onLongPress;
const FrostCard({Key? key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = EdgeInsets.zero, this.radius = 20, this.onTap, this.onLongPress}) : super(key: key);
@override Widget build(BuildContext context) {
return Padding(
padding: margin,
child: GestureDetector(
onTap: onTap, onLongPress: onLongPress,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: Colors.white.withOpacity(0.5), width: 0.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ========== 时间格式化 ==========
String fmtTime(dynamic ts) {
  if (ts == null) return '';
  if (ts is String) {
    final dt = DateTime.tryParse(ts);
    if (dt != null) return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return ts;
  }
  if (ts is int) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  return ts.toString();
}
String formatTime(dynamic ts) => fmtTime(ts);
String fmtDate(dynamic ts) {
  if (ts == null) return '';
  if (ts is String) {
    final dt = DateTime.tryParse(ts);
    if (dt != null) return '${dt.year}.${dt.month}.${dt.day}';
    return ts;
  }
  if (ts is int) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.year}.${dt.month}.${dt.day}';
  }
  return ts.toString();
}
