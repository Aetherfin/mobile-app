import 'package:flutter/material.dart';

import '../../../design_tokens/tokens.dart';
import '../../../utils/oklch.dart';

/// Gradient background style — the default Now Playing background.
///
/// Renders a vertical gradient from dark surface at top to a spectral-derived
/// shadow color at bottom, using the artwork's dominant hue.
class GradientBackground extends StatelessWidget {
  const GradientBackground({
    super.key,
    required this.energy,
    required this.child,
  });

  /// The spectral energy color extracted from the current artwork.
  final Color energy;

  /// Child widget to render on top of the background.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final oklch = srgbToOklch(energy);
    // ponytail: brighter shadow — L 0.22, chroma ×0.45 for more visible gradient
    final shadowColor = OklchColor(0.22, oklch.c * 0.45, oklch.h).toColor();
    const darkSurface = AfColors.surfaceCanvas;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [darkSurface, shadowColor],
          stops: const [0.0, 1.0],
        ),
      ),
      child: child,
    );
  }
}
