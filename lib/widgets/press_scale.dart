import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Replaces Material's default ripple with the Aetherfin press grammar:
/// a brief 0.96 scale-down on press for tactile feedback.
///
/// Every tappable element should wrap its target in [PressScale] so press
/// feedback stays consistent across the app.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.duration = AfDurations.instant,
    this.pressedScale = 0.96,
    this.behavior = HitTestBehavior.opaque,
    this.ensureHitTarget = true,
    this.disabled = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Duration duration;
  final double pressedScale;
  final HitTestBehavior behavior;

  /// Minimum hit-target enforcement. Defaults to true — every tap target
  /// inflates to 48x48 dp via transparent padding.
  final bool ensureHitTarget;

  /// Disables press interaction. Shows muted appearance at [AfOpacity.disabled]
  /// opacity, skips scale animation, and prevents [onTap] from firing.
  final bool disabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: AfDurations.quick,
    lowerBound: 0,
    upperBound: 1,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: widget.pressedScale,
  ).animate(CurvedAnimation(parent: _ctrl, curve: AfCurves.easeStandard));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _press([_]) => _ctrl.forward();
  void _release([_]) => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    if (widget.disabled) {
      final target = Opacity(opacity: AfOpacity.disabled, child: widget.child);
      if (!widget.ensureHitTarget) return target;
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AfSpacing.minHitTarget,
          minHeight: AfSpacing.minHitTarget,
        ),
        child: target,
      );
    }

    final reduced = MediaQuery.of(context).disableAnimations;
    final target = GestureDetector(
      behavior: widget.behavior,
      onTapDown: reduced ? null : _press,
      onTapUp: reduced ? null : _release,
      onTapCancel: reduced ? null : _release,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: reduced
          ? widget.child
          : ScaleTransition(scale: _scale, child: widget.child),
    );

    if (!widget.ensureHitTarget) return target;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AfSpacing.minHitTarget,
        minHeight: AfSpacing.minHitTarget,
      ),
      child: target,
    );
  }
}

/// [PressScale] + keyboard/switch-accessible focus ring.
///
/// Wraps the standard press-scale interaction with a [Focus] widget that
/// renders a 2 dp accent border when the element receives keyboard or
/// switch-access focus. The focus ring uses [AfColors.accentPrimary] at 50%
/// opacity with [AfRadii.borderSm] radius.
///
/// Pass the same arguments you would pass to [PressScale], plus any
/// [FocusNode] you want to externally control.
class FocusPressScale extends StatefulWidget {
  const FocusPressScale({
    super.key,
    this.focusNode,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.duration = AfDurations.instant,
    this.pressedScale = 0.96,
    this.behavior = HitTestBehavior.opaque,
    this.ensureHitTarget = true,
    this.autofocus = false,
    this.disabled = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Duration duration;
  final double pressedScale;
  final HitTestBehavior behavior;
  final bool ensureHitTarget;
  final bool autofocus;
  final bool disabled;
  final FocusNode? focusNode;

  @override
  State<FocusPressScale> createState() => _FocusPressScaleState();
}

class _FocusPressScaleState extends State<FocusPressScale> {
  late final FocusNode _focusNode =
      widget.focusNode ?? FocusNode(debugLabel: 'FocusPressScale');

  bool _ownsFocusNode() => widget.focusNode == null;

  @override
  void dispose() {
    if (_ownsFocusNode()) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AfRadii.borderSm,
              border: focused
                  ? Border.all(
                      color: AfColors.accentPrimary.withValues(alpha: 0.5),
                      width: 2,
                    )
                  : null,
            ),
            child: PressScale(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              duration: widget.duration,
              pressedScale: widget.pressedScale,
              behavior: widget.behavior,
              ensureHitTarget: widget.ensureHitTarget,
              disabled: widget.disabled,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}
