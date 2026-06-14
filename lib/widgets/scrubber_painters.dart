import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';
import 'scrubber_notifiers.dart';

class ScrubCombinedBarPainter extends CustomPainter {
  ScrubCombinedBarPainter({
    required this.fftNotifier,
    required this.scrubNotifier,
    required this.playedColor,
    required this.unplayedColor,
  }) : super(repaint: Listenable.merge([fftNotifier, scrubNotifier]));
  final ScrubBlockNotifier fftNotifier;
  final ScrubProgressNotifier scrubNotifier;
  final Color playedColor;
  final Color unplayedColor;

  /// Hoisted paint — mutated per frame, never re-allocated.
  final Paint _paint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double midY = size.height / 2;
    final double slotW = size.width / ScrubBlockNotifier.bins;
    final double barW = (slotW * 0.7).clamp(1.0, 8.0);
    final double rawFillX = scrubNotifier.displayProgress * size.width;
    // When FFT bars are active (music is playing), ensure at least the
    // first bar slot is colored so the visualizer doesn't go fully grey
    // when position briefly resets to 0 during track transitions.
    final double fillX = fftNotifier.hasEnergy
        ? math.max(rawFillX, slotW * 0.75)
        : (fftNotifier.totalEnergy > 0 ? rawFillX : 0.0);
    final double maxBarH = midY;
    final barRadius = Radius.circular(barW / 2);

    final paint = _paint;

    // Path batching: 4 distinct paint states to prevent breaking the
    // Skia pipeline batch. Grouping by color avoids ~128 individual
    // drawRRect calls that thrash the GPU state.
    final topPlayedPath = ui.Path();
    final topUnplayedPath = ui.Path();
    final refPlayedPath = ui.Path();
    final refUnplayedPath = ui.Path();

    for (var i = 0; i < ScrubBlockNotifier.bins; i++) {
      final level = fftNotifier.smoothed[i];
      if (level < 0.01) continue;

      final cx = (i + 0.5) * slotW;
      final x = cx - barW / 2;
      final barH = (level * maxBarH).clamp(2.0, maxBarH);

      // Fix: Calculates play state natively by comparing bar center to scrub position
      final isPlayed = cx <= fillX;

      final topRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, midY - barH, barW, barH),
        barRadius,
      );
      final refRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, midY + 2.0, barW, barH * 0.4),
        barRadius,
      );

      if (isPlayed) {
        topPlayedPath.addRRect(topRect);
        refPlayedPath.addRRect(refRect);
      } else {
        topUnplayedPath.addRRect(topRect);
        refUnplayedPath.addRRect(refRect);
      }
    }

    // Render 4 batched draw calls instead of ~128 individual ones.
    canvas.drawPath(topPlayedPath, paint..color = playedColor);
    canvas.drawPath(topUnplayedPath, paint..color = unplayedColor);
    canvas.drawPath(
      refPlayedPath,
      paint..color = playedColor.withValues(alpha: 0.35),
    );
    canvas.drawPath(
      refUnplayedPath,
      paint..color = unplayedColor.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant ScrubCombinedBarPainter old) =>
      old.playedColor != playedColor || old.unplayedColor != unplayedColor;
}

class ScrubOverlayPainter extends CustomPainter {
  ScrubOverlayPainter({
    required this.notifier,
    required this.playedColor,
    required this.unplayedColor,
  }) : super(repaint: notifier);
  final ScrubProgressNotifier notifier;
  final Color playedColor;
  final Color unplayedColor;

  double? _cachedFillW;
  Color? _cachedPlayedColor;
  ui.Shader? _cachedShader;

  // ── Hoisted paint objects — mutated per frame, never re-allocated. ──
  final Paint _trackBgPaint = Paint();
  final Paint _tailPaint = Paint();
  final Paint _glowPaint = Paint();
  final Paint _hStreakPaint = Paint();
  final Paint _vStreakPaint = Paint();
  final Paint _corePaint = Paint()..color = AfColors.textPrimary;

  // ── Hoisted MaskFilters — only 2 distinct blur radii used. ──
  static const _blur2 = MaskFilter.blur(BlurStyle.normal, 2.0);
  MaskFilter _blurOuter = const MaskFilter.blur(BlurStyle.normal, 10.0);
  bool _lastDrag = false;

  // ── Cached track background geometry (only changes with size). ──
  Size? _cachedTrackSize;
  late RRect _cachedTrackRRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final midY = size.height / 2;
    final fillW = (notifier.displayProgress * size.width).clamp(
      0.0,
      size.width,
    );

    // 1. Track background.
    if (_cachedTrackSize != size) {
      _cachedTrackSize = size;
      _cachedTrackRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, midY - 1.5, size.width, 3),
        const Radius.circular(1.5),
      );
    }
    _trackBgPaint.color = unplayedColor.withValues(alpha: 0.20);
    canvas.drawRRect(_cachedTrackRRect, _trackBgPaint);

    // 2. Tail — fading gradient from transparent to playedColor.
    // Only draw if there's actually a filled portion (fillW > 1 px).
    if (fillW > 1) {
      if (_cachedShader == null ||
          _cachedFillW != fillW ||
          _cachedPlayedColor != playedColor) {
        _cachedFillW = fillW;
        _cachedPlayedColor = playedColor;
        _cachedShader = LinearGradient(
          colors: [playedColor.withValues(alpha: 0.0), playedColor],
        ).createShader(Rect.fromLTWH(0, midY - 1.5, fillW, 3));
      }

      _tailPaint.shader = _cachedShader;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, midY - 1.5, fillW, 3),
          const Radius.circular(1.5),
        ),
        _tailPaint,
      );
    }

    // 3. Playhead shine — bright star-like point that reads as "shining"
    // rather than just a soft glow. Layers: outer glow → horizontal
    // streak → vertical cross-streak → white-hot core.
    {
      // Ensure the playhead center is at least the core radius from the
      // left edge so glow effects aren't clipped by Stack.hardEdge.
      final cx = math.max(fillW, 2.5);
      final isDrag = notifier.dragging;

      // Recompute the outer blur only when drag state changes.
      if (isDrag != _lastDrag) {
        _lastDrag = isDrag;
        _blurOuter = MaskFilter.blur(BlurStyle.normal, isDrag ? 14.0 : 10.0);
      }

      // Outer ambient glow (soft, wide).
      _glowPaint
        ..color = playedColor.withValues(alpha: isDrag ? 0.35 : 0.20)
        ..maskFilter = _blurOuter
        ..shader = null;
      canvas.drawCircle(Offset(cx, midY), isDrag ? 28.0 : 16.0, _glowPaint);

      // Horizontal light streak — the main "shine" ray.
      _hStreakPaint
        ..color = AfColors.textPrimary.withValues(alpha: 0.85)
        ..maskFilter = _blur2
        ..shader = null;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, midY),
          width: isDrag ? 56.0 : 28.0,
          height: 2.5,
        ),
        _hStreakPaint,
      );

      // Vertical cross-streak — gives the star/diamond shape.
      _vStreakPaint
        ..color = AfColors.textPrimary.withValues(alpha: 0.6)
        ..maskFilter = _blur2
        ..shader = null;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, midY),
          width: 2.5,
          height: isDrag ? 24.0 : 14.0,
        ),
        _vStreakPaint,
      );

      // White-hot core — always visible, brighter during drag.
      canvas.drawCircle(Offset(cx, midY), isDrag ? 4.0 : 2.5, _corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ScrubOverlayPainter old) =>
      old.playedColor != playedColor || old.unplayedColor != unplayedColor;
}
