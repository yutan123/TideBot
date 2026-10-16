import 'package:flutter/material.dart';
import 'theme.dart';
import 'ui_components.dart';

/// A content-sized rolling window: text, timestamp and separator never share a fixed row height.
class WorldBookPreviewWindow extends StatelessWidget {
  const WorldBookPreviewWindow(
      {super.key,
      required this.memories,
      required this.startIndex,
      required this.onSelect,
      required this.formatTimestamp});
  final List<Map<String, dynamic>> memories;
  final int startIndex;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final String Function(dynamic) formatTimestamp;
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final count = memories.length;
    if (count == 0) return const SizedBox.shrink();
    final window = <Map<String, dynamic>>[];
    final visible = count < 3 ? count : 3;
    for (var i = 0; i < visible; i++) {
      window.add(memories[(startIndex + i) % count]);
    }
    return AnimatedSize(
        duration: const Duration(milliseconds: 320),
        alignment: Alignment.topCenter,
        curve: Curves.easeInOutCubic,
        child: AnimatedSwitcher(
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [
              for (final child in previous)
                Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(child: child)),
              if (current != null) current
            ],
          ),
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            key: ValueKey<int>(startIndex),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < window.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 0.5, color: theme.divider),
                BouncyTap(
                  onTap: () => onSelect(window[i]),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          window[i]['content'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: theme.textStrong,
                            fontFamily: 'TideFont',
                          ),
                        ),
                        if (window[i]['timestamp'] != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            formatTimestamp(window[i]['timestamp']),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textFaint,
                              fontFamily: 'TideFont',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ));
  }
}
