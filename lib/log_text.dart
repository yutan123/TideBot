import 'package:flutter/material.dart';

import 'android_selection_menu.dart';

/// Use the same bundled fonts and line metrics while reading and during routes.
const logTextStyle = TextStyle(
  inherit: false,
  fontFamily: 'LogMono',
  fontFamilyFallback: ['LogSansSC'],
  fontSize: 12,
  height: 1.5,
  fontWeight: FontWeight.w400,
  textBaseline: TextBaseline.alphabetic,
);

/// Flutter owns layout and scrolling; Android provides the selection menu.
/// Native asynchronous height reports must not resize long, lazy log rows.
class LogText extends StatelessWidget {
  const LogText(
    this.data, {
    super.key,
    required this.color,
    this.fontSize = 12,
  });

  final String data;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      contextMenuBuilder: androidSelectionContextMenu,
      child: Text(
        data,
        style: logTextStyle.copyWith(color: color, fontSize: fontSize),
      ),
    );
  }
}
