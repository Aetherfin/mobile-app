import 'package:flutter/material.dart';

import '../../../design_tokens/tokens.dart';
import '../../../utils/oklch.dart';

/// Glow background style for Now Playing.
///
/// Renders a dark surface with an animated radial glow emanating from the
/// center, using the artwork's spectral colors. The glow is implemented
/// as a [RadialGradient] on a [DecoratedBox] — GPU-friendly, no per-frame blur.
class GlowBackground extends StatefulWidget {
  const GlowBackground({super.key, required this.energy, required this.child});

  /// The spectral energy color extracted from the current artwork.
  final Color energy;

  /// Child widget to render on top of the background.
  final Widget child;

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: AfDurations.ambient,
    );
    _glowAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: AfCurves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oklch = srgbToOklch(widget.energy);
    final glowColor = OklchColor(0.45, oklch.c * 0.8, oklch.h).toColor();
    final deepGlow = OklchColor(0.25, oklch.c * 0.5, oklch.h).toColor();

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        final opacity = _glowAnimation.value;
        return Container(
          color: AfColors.surfaceCanvas,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.8,
                colors: [
                  glowColor.withValues(alpha: 0.35 * opacity),
                  deepGlow.withValues(alpha: 0.18 * opacity),
                  AfColors.surfaceCanvas.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
