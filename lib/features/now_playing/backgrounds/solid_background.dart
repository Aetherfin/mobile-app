import 'package:flutter/material.dart';

import '../../../utils/oklch.dart';

/// Solid background style for Now Playing.
///
/// Renders a single solid color extracted from the artwork's spectral energy.
/// The color is darkened to serve as a background — vibrant enough to feel
/// alive, muted enough for content readability.
class SolidBackground extends StatelessWidget {
  const SolidBackground({super.key, required this.energy, required this.child});

  /// The spectral energy color extracted from the current artwork.
  final Color energy;

  /// Child widget to render on top of the background.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final oklch = srgbToOklch(energy);
    // Darken the energy color for use as a background.
    // Target lightness ~0.12 — dark enough for white text, tinted enough
    // to feel connected to the artwork.
    final bgColor = OklchColor(0.12, oklch.c * 0.3, oklch.h).toColor();

    return Container(color: bgColor, child: child);
  }
}
