import 'dart:math';

import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../../state/animated_spectral.dart';
import '../../state/providers.dart';

/// Canvas overlay for the Now Playing artwork.
///
/// Renders particles or wave effects on top of the album art, driven by
/// the current spectral palette. Lifecycle-aware: pauses animation when
/// the app goes to background, resumes on foreground.
///
/// Place this widget inside a [Stack] above the artwork card.
class CanvasArtworkOverlay extends StatefulWidget {
  const CanvasArtworkOverlay({required this.effect, super.key});

  /// The active canvas effect to render.
  final CanvasEffect effect;

  @override
  State<CanvasArtworkOverlay> createState() => _CanvasArtworkOverlayState();
}

class _CanvasArtworkOverlayState extends State<CanvasArtworkOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _lifecycle = AppLifecycleListener(
      onPause: () => _ctrl.stop(),
      onResume: () => _ctrl.repeat(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fast exit: no effect or animations disabled.
    if (widget.effect == CanvasEffect.none ||
        MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return ValueListenableBuilder<Spectral>(
            valueListenable: animatedSpectral,
            builder: (context, spectral, _) {
              return CustomPaint(
                painter: widget.effect == CanvasEffect.particles
                    ? _ParticlePainter(
                        progress: _ctrl.value,
                        spectral: spectral,
                      )
                    : _WavePainter(
                        progress: _ctrl.value,
                        spectral: spectral,
                      ),
                size: Size.infinite,
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Particle Painter
// ---------------------------------------------------------------------------

/// 25 particles floating upward with soft spectral glow.
class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.progress, required this.spectral})
      : super(repaint: ValueNotifier<double>(progress));

  final double progress;
  final Spectral spectral;

  static final _rng = Random(42);
  static const _count = 25;
  static late final List<_Particle> _particles;

  static bool _initialized = false;

  void _initParticles() {
    if (_initialized) return;
    _particles = List.generate(_count, (_) {
      return _Particle(
        x: _rng.nextDouble(),
        startY: _rng.nextDouble(),
        speed: 0.15 + _rng.nextDouble() * 0.25,
        radius: 1.5 + _rng.nextDouble() * 2.5,
        colorIndex: _rng.nextInt(3), // 0=primary, 1=secondary, 2=muted
      );
    });
    _initialized = true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _initParticles();

    for (final p in _particles) {
      // Wrap Y upward: goes from bottom (1.0) to top (0.0), then wraps.
      final y =
          ((p.startY - progress * p.speed) % 1.0 + 1.0) % 1.0;
      final screenY = size.height * (1 - y); // bottom-anchored
      final screenX = size.width * p.x;

      // Fade alpha: full in the middle, fades at top/bottom 20%.
      final edgeFade = y < 0.2
          ? y / 0.2
          : y > 0.8
              ? (1 - y) / 0.2
              : 1.0;
      final alpha = (edgeFade * 180).clamp(0, 255).toInt();

      final color = _colorForIndex(p.colorIndex).withValues(alpha: alpha / 255);

      final paint = Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(screenX, screenY), p.radius, paint);
    }
  }

  Color _colorForIndex(int index) {
    switch (index) {
      case 0:
        return spectral.primary;
      case 1:
        return spectral.secondary;
      default:
        return spectral.muted;
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}

class _Particle {
  const _Particle({
    required this.x,
    required this.startY,
    required this.speed,
    required this.radius,
    required this.colorIndex,
  });

  /// Horizontal position (0..1).
  final double x;

  /// Initial vertical position (0..1).
  final double startY;

  /// Speed multiplier (higher = faster upward drift).
  final double speed;

  /// Circle radius in logical pixels.
  final double radius;

  /// Index into spectral palette (0=primary, 1=secondary, 2=muted).
  final int colorIndex;
}

// ---------------------------------------------------------------------------
// Wave Painter
// ---------------------------------------------------------------------------

/// 3 layered sine waves drifting horizontally across the artwork.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.progress, required this.spectral})
      : super(repaint: ValueNotifier<double>(progress));

  final double progress;
  final Spectral spectral;

  @override
  void paint(Canvas canvas, Size size) {
    const layers = 3;
    final colors = [spectral.primary, spectral.secondary, spectral.muted];
    final yBases = [size.height * 0.4, size.height * 0.55, size.height * 0.7];

    for (var layer = 0; layer < layers; layer++) {
      final color = colors[layer].withValues(alpha: 0.12);

      final path = Path();
      path.moveTo(0, yBases[layer]);
      for (var x = 0.0; x <= size.width; x += 1) {
        final y = yBases[layer] +
            sin(x * 0.02 + progress * 2 * pi + layer) * 12;
        path.lineTo(x, y);
      }

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress;
}
