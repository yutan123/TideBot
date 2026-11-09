import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'ui_components.dart';

/// Uses the standard button's focus, semantics and gesture cancellation,
/// with a held press and a spring release instead of a flash overlay.
class FutureTaskButton extends StatefulWidget {
  const FutureTaskButton(
      {super.key,
      required this.child,
      this.onPressed,
      this.color,
      this.foregroundColor,
      this.tooltip});
  final Widget child;
  final VoidCallback? onPressed;
  final Color? color, foregroundColor;
  final String? tooltip;

  @override
  State<FutureTaskButton> createState() => _FutureTaskButtonState();
}

class _FutureTaskButtonState extends State<FutureTaskButton>
    with SingleTickerProviderStateMixin {
  late final _scale = AnimationController.unbounded(vsync: this, value: 1);
  bool get _animate => !MediaQuery.disableAnimationsOf(context);

  void _release() {
    if (!_animate) return;
    _scale.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 420, damping: 23),
      _scale.value,
      1,
      _scale.velocity,
    ));
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Widget button = Listener(
      onPointerDown: enabled
          ? (_) {
              if (_animate)
                _scale.animateTo(.95,
                    duration: const Duration(milliseconds: 80),
                    curve: Curves.easeOut);
            }
          : null,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _animate ? _scale.value : 1, child: child),
        child: TextButton(
          onPressed: enabled
              ? () {
                  TideHaptics.tap();
                  // Keyboard activation and very quick taps also get a visible pulse.
                  if (_animate && _scale.value >= .999) {
                    _scale.animateWith(SpringSimulation(
                      const SpringDescription(
                          mass: 1, stiffness: 420, damping: 23),
                      1,
                      1,
                      -2,
                    ));
                  }
                  widget.onPressed!();
                }
              : null,
          style: TextButton.styleFrom(
            foregroundColor: widget.foregroundColor,
            backgroundColor: widget.color,
            disabledBackgroundColor: widget.color?.withValues(alpha: .35),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ).copyWith(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent)),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
