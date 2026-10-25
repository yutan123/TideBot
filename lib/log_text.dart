import 'package:flutter/material.dart';

import 'native_selectable_text.dart';

/// Bundled fonts keep log text independent of the app and device typefaces.
const logTextStyle = TextStyle(
  inherit: false,
  fontFamily: 'LogMono',
  fontFamilyFallback: ['LogSansSC'],
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
