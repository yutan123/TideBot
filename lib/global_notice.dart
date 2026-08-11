import 'dart:async';
import 'package:flutter/material.dart';

final GlobalKey<OverlayState> globalNoticeOverlayKey =
    GlobalKey<OverlayState>();

class GlobalNotice {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    String message, {
    Color? color,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = globalNoticeOverlayKey.currentState;
    if (overlay == null || !overlay.mounted) return;

    _timer?.cancel();
    _entry?.remove();
    _entry = null;

    final entry = OverlayEntry(
      builder: (context) => _GlobalNoticeView(
        message: message,
        color: color,
        onDismiss: dismiss,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _GlobalNoticeView extends StatelessWidget {
  final String message;
  final Color? color;
  final VoidCallback onDismiss;

  const _GlobalNoticeView({
    required this.message,
    required this.color,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final scheme = theme.colorScheme;
    final surface = color ?? scheme.primary;
    final foreground =
        ThemeData.estimateBrightnessForColor(surface) == Brightness.dark
            ? Colors.white
            : scheme.onPrimary;
    // 根 Overlay 中的通知位于底部栏和系统手势区上方；键盘出现时继续上移。
    final bottomInset = media.padding.bottom + media.viewInsets.bottom + 76;
    return Positioned(
      bottom: bottomInset,
      left: 12,
      right: 12,
      child: Dismissible(
        key: ValueKey<String>('notice_$message'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => onDismiss(),
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontFamily: 'TideFont',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '关闭提示',
                    onPressed: onDismiss,
                    icon: Icon(Icons.close_rounded,
                        color: foreground.withValues(alpha: 0.88), size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
