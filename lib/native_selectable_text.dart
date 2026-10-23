import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeSelectableText extends StatelessWidget {
  const NativeSelectableText(
    this.data, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String data;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = DefaultTextStyle.of(context).style.merge(style);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return SelectableText(data, style: resolvedStyle, textAlign: textAlign);
    }

    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final nativeStyle = resolvedStyle.copyWith(
      fontSize: textScaler.scale(resolvedStyle.fontSize ?? 14),
    );
    final painter = TextPainter(
      text: TextSpan(text: data, style: nativeStyle),
      textAlign: textAlign,
      textDirection: direction,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        painter.layout(maxWidth: width);
        final params = <String, Object?>{
          'text': data,
          'fontSize': nativeStyle.fontSize ?? 14,
          'fontFamily': nativeStyle.fontFamily ?? '',
          'fontWeight': nativeStyle.fontWeight?.value ?? 400,
          'italic': nativeStyle.fontStyle == FontStyle.italic,
          'color': (nativeStyle.color ?? Colors.black).toARGB32(),
          'lineHeight': nativeStyle.height ?? 1.2,
          'textAlign': textAlign.name,
          'textDirection': direction.name,
        };
        return SizedBox(
          width: width,
          height: painter.height,
          child: PlatformViewLink(
            viewType: 'tidebot/native_selectable_text',
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
                Factory<LongPressGestureRecognizer>(
                    LongPressGestureRecognizer.new),
              },
            ),
            onCreatePlatformView: (paramsView) =>
                PlatformViewsService.initExpensiveAndroidView(
              id: paramsView.id,
              viewType: paramsView.viewType,
              layoutDirection: direction,
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => paramsView.onFocusChanged(true),
            )
                  ..addOnPlatformViewCreatedListener(
                    paramsView.onPlatformViewCreated,
                  )
                  ..create(),
          ),
        );
      },
    );
  }
}
