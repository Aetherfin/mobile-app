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

  /// Pre-computed colors from the spectral energy — recomputed only when
  /// [widget.energy] changes, not every animation tick.
  late Color _glowColor;
  late Color _deepGlow;

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
    _computeColors(widget.energy);
  }

  @override
  void didUpdateWidget(GlowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.energy != widget.energy) {
      _computeColors(widget.energy);
    }
  }

  void _computeColors(Color energy) {
    final oklch = srgbToOklch(energy);
    // Keep L moderate (high L washes out saturation against near-black base).
    // Boost chroma aggressively for vivid color that reads through the dark bg.
    _glowColor = OklchColor(0.65, oklch.c * 1.5, oklch.h).toColor();
    _deepGlow = OklchColor(0.45, oklch.c * 1.0, oklch.h).toColor();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                radius: 1.2,
                colors: [
                  _glowColor.withValues(alpha: opacity),
                  _deepGlow.withValues(alpha: 0.75 * opacity),
                  AfColors.surfaceCanvas.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.35, 1.0],
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
