import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

/// Android owns selection and its action menu; Flutter owns the scroll layout.
class NativeSelectableText extends StatefulWidget {
  const NativeSelectableText(
    this.data, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.nativeInteraction = false,
  });

  final String data;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Use a real Android view and immediately deliver touches for native selection.
  final bool nativeInteraction;

  @override
  State<NativeSelectableText> createState() => _NativeSelectableTextState();
}

class _NativeSelectableTextState extends State<NativeSelectableText> {
  MethodChannel? _channel;
  Map<String, Object?> _params = const {};
  double? _nativeHeight;
  double _width = 0;
  int _revision = 0;
  Drag? _scrollDrag;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'scrollDrag') {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      switch (args['phase']) {
        case 'start':
          _scrollDrag?.cancel();
          _scrollDrag = Scrollable.maybeOf(context)?.position.drag(
                DragStartDetails(kind: PointerDeviceKind.touch),
                () => _scrollDrag = null,
              );
          break;
        case 'update':
          final delta = (args['delta'] as num).toDouble();
          _scrollDrag?.update(DragUpdateDetails(
            globalPosition: Offset.zero,
            delta: Offset(0, delta),
            primaryDelta: delta,
          ));
          break;
        case 'end':
          final velocity = (args['velocity'] as num).toDouble();
          _scrollDrag?.end(DragEndDetails(
            primaryVelocity: velocity,
            velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
          ));
          _scrollDrag = null;
          break;
        case 'cancel':
          _scrollDrag?.cancel();
          _scrollDrag = null;
          break;
      }
      return;
    }
    if (call.method != 'heightChanged') return;
    final args = Map<Object?, Object?>.from(call.arguments as Map);
    final width = (args['width'] as num).toDouble();
    final height = (args['height'] as num).toDouble();
    if (args['revision'] != _revision ||
        (width - _width).abs() > 1 ||
        !height.isFinite ||
        height <= 0 ||
        _nativeHeight == height) {
      return;
    }
    setState(() => _nativeHeight = height);
  }

  void _onCreated(int id) {
    _channel = MethodChannel('tidebot/native_selectable_text/$id')
      ..setMethodCallHandler(_onNativeCall);
    unawaited(_updateNative());
  }

  Future<void> _updateNative() async {
    final channel = _channel;
    if (!mounted || channel == null) return;
    await channel.invokeMethod<void>('update', {
      ..._params,
      'revision': _revision,
    });
  }

  @override
  void dispose() {
    _scrollDrag?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  double _estimatedHeight(
      TextStyle style, double width, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: widget.data, style: style),
      textAlign: widget.textAlign,
      textDirection: direction,
    )..layout(maxWidth: width);
    final height = painter.height.ceilToDouble().clamp(1.0, double.infinity);
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedStyle =
        DefaultTextStyle.of(context).style.merge(widget.style);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return SelectableText(widget.data,
          style: resolvedStyle, textAlign: widget.textAlign);
    }

    final direction = Directionality.of(context);
    final nativeStyle = resolvedStyle.copyWith(
      fontSize:
          MediaQuery.textScalerOf(context).scale(resolvedStyle.fontSize ?? 14),
    );
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      if (width <= 0) return const SizedBox.shrink();
      final params = <String, Object?>{
        'nativeInteraction': widget.nativeInteraction,
        'text': widget.data,
        'fontSize': nativeStyle.fontSize ?? 14,
        'fontFamily': nativeStyle.fontFamily ?? 'TideFont',
        'fontWeight': nativeStyle.fontWeight?.value ?? 400,
        'italic': nativeStyle.fontStyle == FontStyle.italic,
        'color': (nativeStyle.color ?? Colors.black).toARGB32(),
        'lineHeight': nativeStyle.height ?? 1.2,
        'letterSpacing': nativeStyle.letterSpacing ?? 0,
        'textAlign': widget.textAlign.name,
        'textDirection': direction.name,
        'width': width,
      };
      if (!mapEquals(params, _params)) {
        _params = params;
        _width = width;
        _nativeHeight = null;
        _revision++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_updateNative());
        });
      }
      if (widget.nativeInteraction) {
        // Hybrid composition gives Android's selection toolbar a real window.
        // Touches reach TextView immediately; native scroll drags are forwarded
        // to the enclosing Flutter scroll position through the method channel.
        return SizedBox(
          width: width,
          height:
              _nativeHeight ?? _estimatedHeight(nativeStyle, width, direction),
          child: PlatformViewLink(
            viewType: 'tidebot/native_selectable_text',
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              gestureRecognizers: const {
                Factory<OneSequenceGestureRecognizer>(
                    EagerGestureRecognizer.new),
              },
            ),
            onCreatePlatformView: (params) {
              final controller = PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: 'tidebot/native_selectable_text',
                layoutDirection: direction,
                creationParams: {..._params, 'revision': _revision},
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              );
              controller.addOnPlatformViewCreatedListener(
                  params.onPlatformViewCreated);
              controller.addOnPlatformViewCreatedListener(_onCreated);
              unawaited(controller.create());
              return controller;
            },
          ),
        );
      }
      // Android reports the actual TextView height after the initial estimate.
      // Native font metrics and wrapping must determine each list item's height.
      final painter = TextPainter(
        text: TextSpan(text: widget.data, style: nativeStyle),
        textAlign: widget.textAlign,
        textDirection: direction,
      )..layout(maxWidth: width);
      final estimatedHeight = painter.height;
      painter.dispose();
      return SizedBox(
        width: width,
        height: _nativeHeight ??
            estimatedHeight.ceilToDouble().clamp(1, double.infinity),
        // Texture composition follows Flutter scrolling, clipping and transforms.
        child: AndroidView(
          viewType: 'tidebot/native_selectable_text',
          layoutDirection: direction,
          creationParams: {...params, 'revision': _revision},
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onCreated,
          hitTestBehavior: PlatformViewHitTestBehavior.translucent,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
            Factory<LongPressGestureRecognizer>(LongPressGestureRecognizer.new),
            Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
            Factory<VerticalDragGestureRecognizer>(
                VerticalDragGestureRecognizer.new),
          },
        ),
      );
    });
  }
}
