import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../design_tokens/tokens.dart';

/// A chip with spring physics animation.
///
/// Shrinks to 0.92× on press for tactile feedback, expands to 1.05× on
/// select for a bouncy "pop" effect. Uses [SpringDescription] with
/// mass=1, stiffness=200, damping=12 for a lively spring feel.
///
/// Color transitions use [AnimatedContainer] between [unselectedColor]
/// and [selectedColor] at [AfDurations.quick] timing.
class SpringChip extends StatefulWidget {
  const SpringChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.selectedColor,
    this.unselectedColor,
    this.selectedTextColor,
    this.unselectedTextColor,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// Background color when selected. Defaults to [AfColors.accentPrimary].
  final Color? selectedColor;

  /// Background color when unselected. Defaults to [AfColors.surfaceRaised].
  final Color? unselectedColor;

  /// Text color when selected. Defaults to [AfColors.textOnPrimary].
  final Color? selectedTextColor;

  /// Text color when unselected. Defaults to [AfColors.textSecondary].
  final Color? unselectedTextColor;

  @override
  State<SpringChip> createState() => _SpringChipState();
}

class _SpringChipState extends State<SpringChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _isPressed = false;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 200,
    damping: 12,
  );

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      value: widget.isSelected ? 1.05 : 1.0,
      lowerBound: 0.85,
      upperBound: 1.15,
    );
  }

  @override
  void didUpdateWidget(SpringChip old) {
    super.didUpdateWidget(old);
    if (old.isSelected != widget.isSelected) {
      _animateToTarget();
    }
  }

  double get _targetScale {
    if (_isPressed) return 0.92;
    if (widget.isSelected) return 1.05;
    return 1.0;
  }

  void _animateToTarget() {
    final sim = SpringSimulation(_spring, _ctrl.value, _targetScale, 0);
    _ctrl.animateWith(sim);
  }

  void _onTapDown(TapDownDetails _) {
    _isPressed = true;
    _animateToTarget();
  }

  void _onTapUp(TapUpDetails _) {
    _isPressed = false;
    _animateToTarget();
  }

  void _onTapCancel() {
    _isPressed = false;
    _animateToTarget();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSelectedColor =
        widget.selectedColor ?? AfColors.accentPrimary;
    final effectiveUnselectedColor =
        widget.unselectedColor ?? AfColors.surfaceRaised;
    final effectiveSelectedTextColor =
        widget.selectedTextColor ?? AfColors.textOnPrimary;
    final effectiveUnselectedTextColor =
        widget.unselectedTextColor ?? AfColors.textSecondary;

    final reduced = MediaQuery.of(context).disableAnimations;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: reduced ? null : _onTapDown,
      onTapUp: reduced ? null : _onTapUp,
      onTapCancel: reduced ? null : _onTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Transform.scale(
            scale: reduced ? 1.0 : _ctrl.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: AfDurations.quick,
          curve: AfCurves.easeStandard,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? effectiveSelectedColor
                : effectiveUnselectedColor,
            borderRadius: AfRadii.borderPill,
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: AfTypography.bodyMedium.copyWith(
              color: widget.isSelected
                  ? effectiveSelectedTextColor
                  : effectiveUnselectedTextColor,
              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
