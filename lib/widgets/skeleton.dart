import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

// ---------------------------------------------------------------------------
// ShimmerWrap — animation engine for shimmer skeletons
// ---------------------------------------------------------------------------

/// Wraps content with a lightweight shimmer sweep. Provide [child] for custom
/// content, or provide [width]+[height] to render a standard shimmer box.
class ShimmerWrap extends StatefulWidget {
  const ShimmerWrap({
    super.key,
    this.child,
    this.width,
    this.height,
    this.borderRadius,
    this.color,
    this.shape = BoxShape.rectangle,
  }) : assert(child != null || height != null, 'Provide child or height');

  final Widget? child;
  final double? width;
  final double? height;
  final BorderRadiusGeometry? borderRadius;
  final Color? color;
  final BoxShape shape;

  @override
  State<ShimmerWrap> createState() => _ShimmerWrapState();
}

class _ShimmerWrapState extends State<ShimmerWrap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AfDurations.shimmer,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;

    final effectiveChild =
        widget.child ??
        Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.color ?? AfColors.surfaceRaised,
            borderRadius: widget.shape == BoxShape.circle
                ? null
                : widget.borderRadius,
            shape: widget.shape,
          ),
        );

    if (reduced) {
      return Semantics(
        liveRegion: true,
        label: 'Loading',
        child: effectiveChild,
      );
    }

    return Semantics(
      liveRegion: true,
      label: 'Loading',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Colors.transparent,
                  AfColors.glassFillStrong,
                  Colors.transparent,
                ],
                stops: [
                  (_controller.value - 0.3).clamp(0.0, 1.0),
                  _controller.value,
                  (_controller.value + 0.3).clamp(0.0, 1.0),
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcATop,
            child: child,
          );
        },
        child: effectiveChild,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SkeletonBar — rectangular bar (for text lines, labels, metadata)
// ---------------------------------------------------------------------------

/// A rectangular skeleton bar with shimmer animation.
///
/// Use for text lines, labels, metadata, and other linear placeholders.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({
    super.key,
    this.width,
    this.height = 14.0,
    this.borderRadius,
    this.color,
  });

  /// Width of the bar. `null` means fill the parent width.
  final double? width;

  /// Height of the bar. Default 14dp.
  final double height;

  /// Border radius. Defaults to [AfRadii.borderSm].
  final BorderRadiusGeometry? borderRadius;

  /// Fill color. Defaults to [AfColors.surfaceRaised].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      width: width,
      height: height,
      borderRadius: borderRadius ?? AfRadii.borderSm,
      color: color,
    );
  }
}

// ---------------------------------------------------------------------------
// SkeletonBlock — larger area (for artwork, hero images, cards)
// ---------------------------------------------------------------------------

/// A rectangular skeleton block with shimmer animation.
///
/// Use for artwork placeholders, hero images, card areas, and full-width
/// sections. Unlike [SkeletonBar], [width] is required.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.color,
  });

  /// Width of the block. Required (unlike [SkeletonBar]).
  final double width;

  /// Height of the block.
  final double height;

  /// Border radius. Defaults to [AfRadii.borderMd].
  final BorderRadiusGeometry? borderRadius;

  /// Fill color. Defaults to [AfColors.surfaceRaised].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      width: width,
      height: height,
      borderRadius: borderRadius ?? AfRadii.borderMd,
      color: color,
    );
  }
}

// ---------------------------------------------------------------------------
// SkeletonCircle — circular (for avatars, icon placeholders)
// ---------------------------------------------------------------------------

/// A circular skeleton shape with shimmer animation.
///
/// Use for artist avatars, user profile pictures, and icon placeholders.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size, this.color});

  /// Diameter of the circle.
  final double size;

  /// Fill color. Defaults to [AfColors.surfaceRaised].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      width: size,
      height: size,
      shape: BoxShape.circle,
      color: color,
    );
  }
}
