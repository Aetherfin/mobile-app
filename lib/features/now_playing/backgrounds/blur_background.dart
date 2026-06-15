import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../design_tokens/tokens.dart';
import '../../../utils/oklch.dart';

/// Blur (frosted glass) background style for Now Playing.
///
/// Renders a semi-transparent spectral-tinted overlay with a [BackdropFilter]
/// that creates a frosted glass effect. The blur intensity is fixed at
/// sigma 20 for a smooth, premium feel.
///
/// Uses [RepaintBoundary] to isolate the blur computation from the rest
/// of the widget tree for performance.
class BlurBackground extends StatelessWidget {
  const BlurBackground({super.key, required this.energy, required this.child});

  /// The spectral energy color extracted from the current artwork.
  final Color energy;

  /// Child widget to render on top of the background.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final oklch = srgbToOklch(energy);
    final tint = OklchColor(0.12, oklch.c * 0.25, oklch.h).toColor();

    return RepaintBoundary(
      child: ClipRect(
        child: Stack(
          children: [
            // Base dark surface
            Container(color: AfColors.surfaceCanvas),
            // Frosted blur overlay
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: tint.withValues(alpha: 0.4)),
            ),
            // Content
            child,
          ],
        ),
      ),
    );
  }
}
