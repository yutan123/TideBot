import 'dart:async';

import 'package:flutter/foundation.dart';
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

  @override
  void initState() {
    super.initState();
    _activeId = _id;
    _channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      if (args['id'] != _id) return;
      if (call.method == 'action') {
        final index = args['index'] as int;
        if (index >= 0 && index < widget.items.length) {
          widget.items[index].onPressed?.call();
        }
      } else if (call.method == 'dismissed') {
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
    if (!mounted) return;
    final localizations = MaterialLocalizations.of(context);
    String label(ContextMenuButtonItem item) =>
        item.label ??
        switch (item.type) {
          ContextMenuButtonType.cut => localizations.cutButtonLabel,
          ContextMenuButtonType.copy => localizations.copyButtonLabel,
          ContextMenuButtonType.paste => localizations.pasteButtonLabel,
          ContextMenuButtonType.selectAll => localizations.selectAllButtonLabel,
          ContextMenuButtonType.share => localizations.shareButtonLabel,
          _ => item.type.name,
        };
    try {
      final shown = await _channel.invokeMethod<bool>('show', {
        'id': _id,
        'x': widget.anchors.primaryAnchor.dx,
        'y': widget.anchors.primaryAnchor.dy,
        'items': widget.items
            .map((item) => {
                  'label': label(item),
                  'enabled': item.onPressed != null,
                })
            .toList(),
      });
      if (mounted && shown != true) setState(() => _fallback = true);
    } on PlatformException {
      if (mounted) setState(() => _fallback = true);
    } on MissingPluginException {
      if (mounted) setState(() => _fallback = true);
    }
  }

  @override
  void dispose() {
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
