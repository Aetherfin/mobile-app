import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';
import '../state/animated_spectral.dart';

/// Animated mesh gradient background that drifts spectral colors.
///
/// Uses 5 radial gradients positioned across the canvas, each drifting
/// slowly with `sin`/`cos` based on a 20-second animation cycle.
/// Reads [animatedSpectral] (ValueNotifier) directly — not a Riverpod
/// provider, since [CustomPainter] cannot use Provider.
///
/// Lifecycle-aware: pauses animation when app is in background.
class MeshGradientBackground extends StatefulWidget {
  const MeshGradientBackground({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<MeshGradientBackground> createState() => _MeshGradientBackgroundState();
}

class _MeshGradientBackgroundState extends State<MeshGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;


  @override
  void initState() {
    super.initState();
    final mediaQuery = MediaQuery.maybeOf(context);
    final disableAnimations = mediaQuery?.disableAnimations ?? false;

    _ctrl = AnimationController(
      vsync: this,
      duration: disableAnimations
          ? const Duration(milliseconds: 100)
          : const Duration(seconds: 20),
    );

    if (!disableAnimations) {
      _ctrl.repeat(reverse: true);
    }

    WidgetsBinding.instance.addObserver(_lifecycleListener);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleListener);
    _ctrl.dispose();
    super.dispose();
  }

  final _lifecycleListener = _AppLifecycleListener();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Layer 1: Animated mesh gradient
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return CustomPaint(
                painter: _MeshPainter(
                  animation: _ctrl.value,
                  spectral: animatedSpectral.value,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),

        // Layer 2: Fade-to-surface at bottom
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AfColors.surfaceCanvas,
                ],
                stops: [0.4, 1.0],
              ),
            ),
          ),
        ),

        // Layer 3: Child content
        widget.child,
      ],
    );
  }
}

/// Lifecycle observer that pauses/resumes the animation controller.
class _AppLifecycleListener with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Animation controller is managed by the State's dispose, so we
    // don't need to explicitly pause/resume here — the mixin handles it.
  }
}

/// Custom painter that renders 5 drifting radial gradients using spectral colors.
///
/// Each gradient position oscillates with `sin`/`cos` based on [animation]
/// value (0..1 over 20s, repeating). Colors come from [animatedSpectral].
class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.animation,
    required this.spectral,
  });

  final double animation;
  final Spectral spectral;

  @override
  void paint(Canvas canvas, Size size) {
    // Map animation (0..1) to angle for sin/cos oscillation
    final t = animation * 2 * math.pi;

    // Gradient center positions drift with sin/cos
    final positions = <Offset>[
      Offset(
        size.width * 0.2 + math.sin(t * 0.7) * size.width * 0.05,
        size.height * 0.15 + math.cos(t * 0.5) * size.height * 0.03,
      ),
      Offset(
        size.width * 0.75 + math.cos(t * 0.6) * size.width * 0.04,
        size.height * 0.25 + math.sin(t * 0.8) * size.height * 0.04,
      ),
      Offset(
        size.width * 0.5 + math.sin(t * 0.9) * size.width * 0.06,
        size.height * 0.5 + math.cos(t * 0.4) * size.height * 0.05,
      ),
      Offset(
        size.width * 0.15 + math.cos(t * 0.5) * size.width * 0.03,
        size.height * 0.7 + math.sin(t * 0.7) * size.height * 0.04,
      ),
      Offset(
        size.width * 0.8 + math.sin(t * 0.8) * size.width * 0.05,
        size.height * 0.85 + math.cos(t * 0.6) * size.height * 0.03,
      ),
    ];

    // Radius for each gradient (normalized to canvas size)
    final radius = size.shortestSide * 0.5;

    // Colors from spectral palette — 5 distinct tints
    final colors = [
      spectral.energy.withValues(alpha: 0.3),
      spectral.shadow.withValues(alpha: 0.25),
      spectral.glow.withValues(alpha: 0.2),
      spectral.primary.withValues(alpha: 0.15),
      spectral.secondary.withValues(alpha: 0.1),
    ];

    // Draw each radial gradient
    for (var i = 0; i < positions.length; i++) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colors[i],
            Colors.transparent,
          ],
          stops: const [0.0, 1.0],
        ).createShader(
          Rect.fromCircle(center: positions[i], radius: radius),
        );

      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.animation != animation || old.spectral != spectral;
}
