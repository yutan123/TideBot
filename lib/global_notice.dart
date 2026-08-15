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
    // 对齐原生 SnackBar 的紧凑体量：窄内边距、小圆角、单行文案、可横滑 + 关闭。
    final maxWidth = media.size.width > 540 ? 500.0 : media.size.width - 32;
    final targetWidth = (media.size.width * 0.94).clamp(320.0, maxWidth);
    return Positioned(
      bottom: bottomInset,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: targetWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Dismissible(
              key: ValueKey<String>('notice_$message'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => onDismiss(),
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 38,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          right: 52,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 18),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                message,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  color: foreground,
                                  fontFamily: 'TideFont',
                                  fontSize: 14,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          width: 48,
                          height: 38,
                          child: IconButton(
                            tooltip: '关闭提示',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            onPressed: onDismiss,
                            icon: Icon(
                              Icons.close_rounded,
                              color: foreground.withValues(alpha: 0.9),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
