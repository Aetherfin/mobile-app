import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';

/// Animated squiggly-line progress bar with drag-to-seek.
///
/// The sine wave scrolls continuously (2 s phase cycle) and splits into
/// played (spectral energy) and unplayed (muted) colours at the current
/// position fraction.
class SquigglyProgressBar extends ConsumerStatefulWidget {
  const SquigglyProgressBar({super.key, required this.track});
  final AfTrack track;

  @override
  ConsumerState<SquigglyProgressBar> createState() =>
      _SquigglyProgressBarState();
}

class _SquigglyProgressBarState extends ConsumerState<SquigglyProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phaseCtrl;
  bool _isDragging = false;
  double _dragFraction = 0.0;

  @override
  void initState() {
    super.initState();
    _phaseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _phaseCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SquigglyProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _isDragging = false;
    }
  }

  void _onDragStart(DragStartDetails details, double fraction) {
    _isDragging = true;
    _dragFraction = fraction;
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    final fraction = (details.localPosition.dx / width).clamp(0.0, 1.0);
    _dragFraction = fraction;
  }

  void _onDragEnd(Duration duration) {
    final pos = Duration(
      milliseconds: (_dragFraction * duration.inMilliseconds).round(),
    );
    ref.read(playerServiceProvider).seek(pos);
    _isDragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionStreamProvider);
    final spectral = ref.watch(currentSpectralProvider);
    final mpvDuration = ref.watch(durationStreamProvider);
    final loadedTrackId = ref.watch(mpvLoadedTrackIdProvider);
    final isTransitioning = widget.track.id != loadedTrackId;
    final duration = mpvDuration > Duration.zero
        ? mpvDuration
        : widget.track.duration;

    final effectivePosition = isTransitioning ? Duration.zero : position;

    final engineFraction = duration.inMilliseconds == 0
        ? 0.0
        : (effectivePosition.inMilliseconds / duration.inMilliseconds).clamp(
            0.0,
            1.0,
          );

    final displayFraction = _isDragging ? _dragFraction : engineFraction;

    return Semantics(
      label: 'Progress',
      value: '${(displayFraction * 100).round()}%',
      child: GestureDetector(
        onHorizontalDragStart: (d) => _onDragStart(d, displayFraction),
        onHorizontalDragUpdate: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) _onDragUpdate(d, box.size.width);
        },
        onHorizontalDragEnd: (_) => _onDragEnd(duration),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _phaseCtrl,
            builder: (context, _) {
              return CustomPaint(
                size: const Size(double.infinity, 24),
                painter: _SquigglyPainter(
                  fraction: displayFraction,
                  phase: _phaseCtrl.value * 2 * pi,
                  playedColor: spectral.energy,
                  unplayedColor: AfColors.textTertiary,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _SquigglyPainter extends CustomPainter {
  _SquigglyPainter({
    required this.fraction,
    required this.phase,
    required this.playedColor,
    required this.unplayedColor,
  });

  final double fraction;
  final double phase;
  final Color playedColor;
  final Color unplayedColor;

  static const _amplitude = 2.5;
  static const _strokeWidth = 2.5;
  static const _frequency = 0.12; // radians per pixel

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final w = size.width;

    final unplayedPaint = Paint()
      ..color = unplayedColor.withValues(alpha: 0.3)
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final playedPaint = Paint()
      ..color = playedColor
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw unplayed first (full width), then played on top up to fraction.
    final unplayedPath = Path();
    final playedPath = Path();
    final splitX = w * fraction;

    for (var x = 0; x <= w; x++) {
      final y = midY + sin(x * _frequency + phase) * _amplitude;
      if (x == 0) {
        unplayedPath.moveTo(x.toDouble(), y);
        playedPath.moveTo(x.toDouble(), y);
      } else {
        unplayedPath.lineTo(x.toDouble(), y);
        if (x <= splitX) {
          playedPath.lineTo(x.toDouble(), y);
        }
      }
    }

    canvas.drawPath(unplayedPath, unplayedPaint);
    if (fraction > 0) {
      canvas.drawPath(playedPath, playedPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SquigglyPainter old) =>
      old.fraction != fraction ||
      old.phase != phase ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}
