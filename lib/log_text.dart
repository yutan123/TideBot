import 'package:flutter/material.dart';

import 'native_selectable_text.dart';

/// Keep the same monospace face used by the original log viewer. The native
/// Android TextView resolves this family just like the old SelectableText did.
const logTextStyle = TextStyle(
  inherit: false,
  fontFamily: 'monospace',
  fontSize: 12,
  height: 1.5,
  fontWeight: FontWeight.w400,
);

/// Android owns log selection, handles and the standard contextual action menu.
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
    return NativeSelectableText(
      data,
      nativeInteraction: true,
      style: logTextStyle.copyWith(color: color, fontSize: fontSize),
    );
  }
}
