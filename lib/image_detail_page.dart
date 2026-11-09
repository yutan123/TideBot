import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'photo_image_provider.dart';

/// Full-screen image canvas. Only the controls respect the safe area, so the
/// image can move beneath them and use the entire display at every scale.
class ImageDetailPage extends StatefulWidget {
  const ImageDetailPage({
    super.key,
    required this.path,
    required this.onSave,
  }) : immersive = false;

  const ImageDetailPage._immersive({required this.path})
      : immersive = true,
        onSave = null;

  final String path;
  final Future<void> Function()? onSave;
  final bool immersive;

  @override
  State<ImageDetailPage> createState() => _ImageDetailPageState();
}

class _ImageDetailPageState extends State<ImageDetailPage> {
  final _transformation = TransformationController();
  final _pointers = <int>{};
  bool _interacting = false;
  bool _saving = false;
  bool _opening = false;

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  void _setInteracting(bool value) {
    if (!widget.immersive && mounted && _interacting != value) {
      setState(() => _interacting = value);
    }
  }

  void _releasePointer(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) _setInteracting(false);
  }

  Future<void> _save() async {
    if (_saving || widget.onSave == null) return;
    setState(() => _saving = true);
    try {
      await widget.onSave!();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openImmersive() async {
    if (widget.immersive || _opening) return;
    _opening = true;
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, secondaryAnimation) =>
              ImageDetailPage._immersive(path: widget.path),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final immersive = widget.immersive;
    final visible = immersive || !_interacting;
    final foreground = immersive ? Colors.white : Colors.black87;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (immersive ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: immersive ? Colors.black : Colors.white,
        systemNavigationBarIconBrightness:
            immersive ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: immersive ? Colors.black : Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, viewport) => Listener(
                onPointerDown: (event) => _pointers.add(event.pointer),
                onPointerUp: _releasePointer,
                onPointerCancel: _releasePointer,
                child: InteractiveViewer(
                  transformationController: _transformation,
                  minScale: 0.5,
                  maxScale: 8,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  onInteractionStart: (_) => _setInteracting(true),
                  onInteractionEnd: (_) {
                    // Changing from two fingers to one may end a scale phase;
                    // keep controls hidden until the final finger is released.
                    if (_pointers.isEmpty) _setInteracting(false);
                  },
                  // Both the hit area and transformed child fill the viewport;
                  // a short image never becomes the clipping boundary.
                  child: SizedBox(
                    width: viewport.maxWidth,
                    height: viewport.maxHeight,
                    child: Center(
                      child: GestureDetector(
                        onTap: immersive ? null : _openImmersive,
                        child: Image(
                          image: photoImageProvider(widget.path),
                          fit: BoxFit.contain,
                          semanticLabel: immersive ? '全屏图片' : '图片，点击进入全屏浏览',
                          errorBuilder: (_, error, stackTrace) => Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              '图片暂时无法显示，请返回重试',
                              style: TextStyle(color: foreground),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: ExcludeSemantics(
                      excluding: !visible,
                      child: AnimatedOpacity(
                        opacity: visible ? 1 : 0,
                        // Hide immediately once the pan/scale gesture wins.
                        duration: Duration(milliseconds: visible ? 140 : 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _ImageIslandButton(
                              icon: immersive
                                  ? Icons.arrow_back_ios_new_rounded
                                  : Icons.close_rounded,
                              label: immersive ? '返回图片详情' : '关闭图片详情',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            if (!immersive)
                              _ImageIslandButton(
                                icon: Icons.download_rounded,
                                label: _saving ? '正在保存' : '保存到相册',
                                busy: _saving,
                                onPressed: _saving ? null : _save,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageIslandButton extends StatelessWidget {
  const _ImageIslandButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: IconButton(
                onPressed: onPressed,
                tooltip: label,
                color: Colors.black87,
                iconSize: 27,
                icon: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black87,
                        ),
                      )
                    : Icon(icon),
              ),
            ),
          ),
        ),
      );
}
