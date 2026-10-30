import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keep Flutter's text, selection and editing; only the toolbar is native.
Widget androidTextContextMenu(BuildContext context, EditableTextState state) =>
    _selectionMenu(state.contextMenuAnchors, state.contextMenuButtonItems);

Widget androidSelectionContextMenu(
        BuildContext context, SelectableRegionState state) =>
    _selectionMenu(state.contextMenuAnchors, state.contextMenuButtonItems);

Widget _selectionMenu(
    TextSelectionToolbarAnchors anchors, List<ContextMenuButtonItem> items) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: anchors, buttonItems: items);
  }
  return _AndroidSelectionMenu(anchors: anchors, items: items);
}

class _AndroidSelectionMenu extends StatefulWidget {
  const _AndroidSelectionMenu({required this.anchors, required this.items});
  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> items;

  @override
  State<_AndroidSelectionMenu> createState() => _AndroidSelectionMenuState();
}

class _AndroidSelectionMenuState extends State<_AndroidSelectionMenu> {
  static const _channel = MethodChannel('tidebot/selection_menu');
  static int _nextId = 0;
  static int? _activeId;
  final int _id = ++_nextId;
  bool _fallback = false;
  final _pointers = <int>{};
  bool _suspended = false;
  Duration? _lastSuspend;

  // Handles live in an Overlay, outside the selected text's render subtree.
  // Observe their pointers without joining or consuming their gesture arena.
  void _onPointer(PointerEvent event) {
    if (_fallback || _activeId != _id) return;
    if (event is PointerDownEvent) {
      _pointers.add(event.pointer);
      _suspend(event.timeStamp);
    } else if (event is PointerMoveEvent && _pointers.contains(event.pointer)) {
      if (_lastSuspend == null ||
          event.timeStamp - _lastSuspend! >=
              const Duration(milliseconds: 500)) {
        _suspend(event.timeStamp);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_pointers.remove(event.pointer) && _pointers.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _show());
      }
    }
  }

  void _suspend(Duration timestamp) {
    _suspended = true;
    _lastSuspend = timestamp;
    unawaited(_channel
        .invokeMethod<void>('suspend', {'id': _id}).catchError((Object _) {}));
  }

  @override
  void initState() {
    super.initState();
    _activeId = _id;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      if (args['id'] != _id) return;
      if (call.method == 'action') {
        final index = args['index'] as int;
        if (index >= 0 && index < widget.items.length) {
          widget.items[index].onPressed?.call();
        }
      } else if (call.method == 'dismissed' && !_suspended) {
        ContextMenuController.removeAny();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  void didUpdateWidget(covariant _AndroidSelectionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    if (!mounted || _pointers.isNotEmpty || _activeId != _id) return;
    try {
      final shown = await _channel.invokeMethod<bool>('show', {
        'id': _id,
        'x': widget.anchors.primaryAnchor.dx,
        'y': widget.anchors.primaryAnchor.dy,
        'items': widget.items
            .map((item) => {
                  'type': item.type.name,
                  // Only provider/custom actions supply their own label.
                  'label': item.label,
                  'enabled': item.onPressed != null,
                })
            .toList(),
      });
      _suspended = _pointers.isNotEmpty;
      if (_suspended) _suspend(_lastSuspend ?? Duration.zero);
      if (mounted && shown != true) setState(() => _fallback = true);
    } on PlatformException {
      if (mounted) setState(() => _fallback = true);
    } on MissingPluginException {
      if (mounted) setState(() => _fallback = true);
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    // A delayed dismissal must not close the next field's menu.
    unawaited(_channel
        .invokeMethod<void>('hide', {'id': _id}).catchError((Object _) {}));
    if (_activeId == _id) {
      _activeId = null;
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _fallback
      ? AdaptiveTextSelectionToolbar.buttonItems(
          anchors: widget.anchors, buttonItems: widget.items)
      : const SizedBox.shrink();
}
