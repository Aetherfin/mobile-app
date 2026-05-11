import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Now Playing scrubber + audio visualiser.
///
/// Replaces the previous "single-canvas waveform with built-in playhead"
/// (which was rendering only a vertical playhead line — bars never showed
/// once it was wired to live Jellyfin tracks because of paint-ordering
/// issues). The new design is two stacked elements:
///
///   • [_Visualiser] — animated equaliser-style bars driven by [peaks].
///     When [isPlaying] is true each bar oscillates around its peak so
///     the band looks alive. When paused the bars freeze.
///   • [_ProgressBar] — a clean horizontal track + thumb scrubber that
///     handles drag / tap. Played portion is the spectral accent; the
///     unplayed portion is a faint white track. The thumb has a soft
///     glow that matches `spectral.glow`.
///
/// The widget is otherwise drop-in compatible with the previous
/// `Waveform` API — same constructor params, same callbacks.
class Waveform extends StatelessWidget {
  /// Per-bar peak amplitudes in [0, 100]. Server-provided when possible;
  /// otherwise a deterministic pattern seeded by the track ID.
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double height;
  final double playheadWidth;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;
  final bool isPlaying;

  const Waveform({
    super.key,
    required this.peaks,
    required this.progress,
    this.playedColor = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.height = 64,
    this.playheadWidth = 1.5,
    this.onScrub,
    this.onScrubEnd,
    this.isPlaying = true,
  });

  @override
  Widget build(BuildContext context) {
    final visualiserHeight = (height - 16).clamp(24.0, height);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Visualiser(
          peaks: peaks,
          progress: progress.clamp(0.0, 1.0),
          playedColor: playedColor,
          unplayedColor: unplayedColor,
          height: visualiserHeight,
          isPlaying: isPlaying,
        ),
        const SizedBox(height: AfSpacing.s8),
        _ProgressBar(
          progress: progress.clamp(0.0, 1.0),
          playedColor: playedColor,
          unplayedColor: unplayedColor,
          onScrub: onScrub,
          onScrubEnd: onScrubEnd,
        ),
      ],
    );
  }
}

/// Animated equaliser bars. Each bar's drawn amplitude is
/// `peakAmp * (1 - jitter * sin(t + i))` so the bars wave around their
/// static peak without losing the song's overall shape. When paused
/// the AnimationController is held still so the bars freeze in place.
class _Visualiser extends StatefulWidget {
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double height;
  final bool isPlaying;

  const _Visualiser({
    required this.peaks,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.height,
    required this.isPlaying,
  });

  @override
  State<_Visualiser> createState() => _VisualiserState();
}

class _VisualiserState extends State<_Visualiser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isPlaying) _ctl.repeat();
  }

  @override
  void didUpdateWidget(covariant _Visualiser old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!widget.isPlaying && _ctl.isAnimating) {
      _ctl.stop();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If the track has zero peaks (server gave us nothing AND demo
    // fallback failed), draw a neutral flat band instead of an empty
    // sliver so the layout doesn't collapse.
    final peaks = widget.peaks.isEmpty
        ? List<int>.filled(64, 30)
        : widget.peaks;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (context, _) {
          return CustomPaint(
            painter: _VisualiserPainter(
              peaks: peaks,
              progress: widget.progress,
              playedColor: widget.playedColor,
              unplayedColor: widget.unplayedColor,
              t: _ctl.value,
              animate: widget.isPlaying,
            ),
          );
        },
      ),
    );
  }
}

class _VisualiserPainter extends CustomPainter {
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double t; // 0..1, repeating
  final bool animate;

  _VisualiserPainter({
    required this.peaks,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.t,
    required this.animate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final barCount = peaks.length;
    // Bar+gap ratio of 1:0.6 reads better than the previous 1:0.5 — the
    // bars feel more like an EQ band, less like a barcode.
    final barWidth = size.width / (barCount + (barCount - 1) * 0.6);
    final gap = barWidth * 0.6;

    final playedBars = (progress * barCount).floor();
    final played = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;
    final unplayed = Paint()
      ..color = unplayedColor.withValues(alpha: 0.32)
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;
    final twoPi = 2 * math.pi;

    for (var i = 0; i < barCount; i++) {
      // Static peak amplitude in [0..1] — comes from the seeded peaks.
      final peakAmp = (peaks[i] / 100.0).clamp(0.06, 1.0);
      // Animated oscillation. The bars near the playhead pulse more
      // strongly than the ones far away, giving a focal "now-playing"
      // emphasis without needing real spectrum data.
      final distToHead = (i - progress * barCount).abs();
      final focus = math.exp(-distToHead / 12);
      final phase = (t * twoPi + i * 0.7);
      final jitter = animate ? 0.18 * focus * math.sin(phase) : 0.0;
      final amp = (peakAmp + jitter).clamp(0.08, 1.0);

      final h = (size.height * amp).clamp(2.0, size.height);
      final x = i * (barWidth + gap);
      final paint = i < playedBars ? played : unplayed;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x,
          centerY - h / 2,
          barWidth,
          h,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_VisualiserPainter old) =>
      old.t != t ||
      old.progress != progress ||
      // `peaks` is a fresh list on every parent rebuild; compare values,
      // not the reference, or we repaint on every frame for no reason.
      !listEquals(old.peaks, peaks) ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor ||
      old.animate != animate;
}

/// Horizontal track + thumb scrubber. 3 dp tall track, 12 dp thumb.
/// Filled portion uses [playedColor]; unfilled is a faint white track.
/// The thumb has a soft glow halo that matches the spectral colour.
class _ProgressBar extends StatelessWidget {
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;

  const _ProgressBar({
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.onScrub,
    required this.onScrubEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: onScrub == null
          ? null
          : (d) => _emit(d.localPosition.dx, context, onScrub!),
      onHorizontalDragUpdate: onScrub == null
          ? null
          : (d) => _emit(d.localPosition.dx, context, onScrub!),
      onHorizontalDragEnd: onScrubEnd == null
          ? null
          : (_) => onScrubEnd!.call(progress),
      onTapDown: onScrub == null
          ? null
          : (d) => _emit(d.localPosition.dx, context, onScrub!),
      child: SizedBox(
        height: 16,
        width: double.infinity,
        child: CustomPaint(
          painter: _ProgressPainter(
            progress: progress,
            playedColor: playedColor,
            unplayedColor: unplayedColor,
          ),
        ),
      ),
    );
  }

  void _emit(double dx, BuildContext context, ValueChanged<double> sink) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    if (width <= 0) return;
    sink((dx / width).clamp(0.0, 1.0));
  }
}

class _ProgressPainter extends CustomPainter {
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  _ProgressPainter({
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const trackHeight = 3.0;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, centerY - trackHeight / 2, size.width, trackHeight),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      trackRect,
      Paint()
        ..color = unplayedColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill,
    );

    final headX = (progress * size.width).clamp(0.0, size.width);
    final playedRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, centerY - trackHeight / 2, headX, trackHeight),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      playedRect,
      Paint()
        ..color = playedColor
        ..style = PaintingStyle.fill,
    );

    // Soft glow halo behind the thumb so the played colour reads even
    // on busy artwork-tinted gradients.
    canvas.drawCircle(
      Offset(headX, centerY),
      10,
      Paint()
        ..color = playedColor.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Thumb.
    canvas.drawCircle(
      Offset(headX, centerY),
      6,
      Paint()
        ..color = AfColors.textPrimary
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}
