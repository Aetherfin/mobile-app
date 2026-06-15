import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';

/// Combined blur + gradient overlay background style for Now Playing.
///
/// Renders the current artwork scaled up and blurred, then overlays a
/// spectral-tinted gradient for a depth effect that marries the frosted
/// glass of [BlurBackground] with the colour richness of
/// [GradientBackground].
///
/// Uses [RepaintBoundary] to isolate the expensive [BackdropFilter] from
/// the rest of the widget tree.
class BlurGradientBackground extends ConsumerWidget {
  const BlurGradientBackground({
    required this.energy,
    required this.child,
    super.key,
  });

  /// The spectral energy color extracted from the current artwork.
  final Color energy;

  /// Child widget to render on top of the background.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(currentSpectralProvider);
    final artworkUri = ref.watch(currentArtworkUriProvider);

    return RepaintBoundary(
      child: ClipRect(
        child: Stack(
          children: [
            // Layer 1: Blurred artwork (scaled 1.2× to bleed past edges)
            if (artworkUri != null)
              Positioned.fill(
                child: Transform.scale(
                  scale: 1.2,
                  child: Image.network(
                    artworkUri.toString(),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
            // Blur filter
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: const SizedBox.expand(),
              ),
            ),
            // Layer 2: Gradient overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      spectral.primary.withValues(alpha: 0.3),
                      spectral.energy.withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
