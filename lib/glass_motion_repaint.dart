import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// The public API does not expose shape-transform invalidation. Keep this
// adapter tied to the locked renderer version until an upstream API exists.
// ignore: implementation_imports
import 'package:liquid_glass_widgets/src/renderer/liquid_glass.dart'
    show RenderLiquidGlass;

/// Glass shaders cache geometry inside their own repaint boundaries. Scrolling
/// and route transforms must invalidate those boundaries as well as the parent.
class GlassMotionRepaint extends SingleChildRenderObjectWidget {
  const GlassMotionRepaint(
      {super.key, required this.motion, required super.child});
  final Listenable motion;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _GlassMotionRenderObject(motion);

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderProxyBox renderObject) {
    (renderObject as _GlassMotionRenderObject).motion = motion;
  }
}

class _GlassMotionRenderObject extends RenderProxyBox {
  _GlassMotionRenderObject(this._motion);
  Listenable _motion;

  set motion(Listenable value) {
    if (identical(value, _motion)) return;
    if (attached) _motion.removeListener(_invalidate);
    _motion = value;
    if (attached) _motion.addListener(_invalidate);
  }

  void _invalidate() {
    void invalidate(RenderObject object) {
      // Painting alone leaves the renderer's shape-to-layer transform cached.
      // Notify the owning glass group before the next paint, not after scene
      // composition (the package's default transform tracker is a frame late).
      if (object is RenderLiquidGlass) object.onTransformChanged();
      object.markNeedsPaint();
      object.visitChildren(invalidate);
    }

    invalidate(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _motion.addListener(_invalidate);
  }

  @override
  void detach() {
    _motion.removeListener(_invalidate);
    super.detach();
  }
}
