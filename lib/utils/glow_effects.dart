import 'dart:math';

import 'package:flutter/material.dart';

/// Glow effect utilities for the pro EQ screen.
///
/// Three-layer glow: outer (blur 8px, 20%), inner (blur 3px, 40%), core (2.5px, 100%).
/// Band nodes: halo + circle + specular highlight + border stroke.
abstract final class GlowEffects {
  // ── Curve glow layers ─────────────────────────────────────────────────────

  /// Returns 3 paint objects for the three-layer glow effect on a curve.
  ///
  /// [baseStrokeWidth] controls the core line width (default 2.5).
  static List<Paint> glowPaints(Color color, {double baseStrokeWidth = 2.5}) {
    return [
      // Layer 1: Outer glow — blurred, transparent
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseStrokeWidth * 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..strokeCap = StrokeCap.round,
      // Layer 2: Inner glow — less blurred, more opaque
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseStrokeWidth * 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..strokeCap = StrokeCap.round,
      // Layer 3: Core line — sharp, full brightness
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseStrokeWidth
        ..strokeCap = StrokeCap.round
        ..filterQuality = FilterQuality.high,
    ];
  }

  /// Draws a three-layer glowing curve path on the canvas.
  static void drawGlowingCurve(
    Canvas canvas,
    Path path,
    Color color, {
    double baseStrokeWidth = 2.5,
  }) {
    final paints = glowPaints(color, baseStrokeWidth: baseStrokeWidth);
    for (final paint in paints) {
      canvas.drawPath(path, paint);
    }
  }

  // ── Band node glow layers ─────────────────────────────────────────────────

  /// Returns paint objects for a band node.
  ///
  /// Order: [halo, mainCircle, specular, border].
  static List<Paint> bandNodePaints(
    Color color, {
    bool isActive = false,
    bool isHovered = false,
  }) {
    return [
      // Halo/glow
      Paint()..color = color.withValues(alpha: 0.27),
      // Main circle
      Paint()..color = color,
      // Border stroke
      Paint()
        ..color =
            const Color(
              0xEBFFFFFF,
            ) // 92% white // glow/paint context — not semantic
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 1.6 : 1.0,
      // Specular highlight
      Paint()
        ..color = Colors.white.withValues(
          alpha: 0.4,
        ), // glow/paint context — not semantic
    ];
  }

  /// Draws a band node at the given center.
  static void drawBandNode(
    Canvas canvas,
    Offset center,
    Color color, {
    double radius = 7.0,
    bool isActive = false,
    bool isHovered = false,
  }) {
    final actualRadius = isActive
        ? 9.0
        : isHovered
        ? 8.0
        : radius;

    // Halo/glow effect
    canvas.drawCircle(
      center,
      actualRadius + 4,
      Paint()..color = color.withValues(alpha: 0.27),
    );

    // Main circle
    canvas.drawCircle(center, actualRadius, Paint()..color = color);

    // Inner highlight (specular)
    canvas.drawCircle(
      center - Offset(actualRadius * 0.2, actualRadius * 0.2),
      actualRadius * 0.4,
      Paint()
        ..color = Colors.white.withValues(
          alpha: 0.4,
        ), // glow/paint context — not semantic
    );

    // Border stroke
    canvas.drawCircle(
      center,
      actualRadius,
      Paint()
        ..color =
            const Color(
              0xEBFFFFFF,
            ) // 92% white — glow/paint context, not semantic
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 1.6 : 1.0,
    );
  }
}

/// Biquad EQ filter frequency response calculation.
///
/// Implements RBJ Cookbook peaking EQ magnitude response.
abstract final class BiquadEQ {
  /// Calculates magnitude response (in dB) at a given frequency
  /// for a biquad peaking EQ filter.
  static double peakingEqMagnitude({
    required double freq,
    required double f0,
    required double gainDb,
    required double q,
    double sampleRate = 44100.0,
  }) {
    if (gainDb == 0) return 0;

    final w0 = 2 * pi * f0 / sampleRate;
    final w = 2 * pi * freq / sampleRate;
    final A = pow(10, gainDb / 40.0).toDouble();
    final alpha = sin(w0) / (2 * q);

    // RBJ coefficients for peaking EQ
    final b0 = 1 + alpha * A;
    final b1 = -2 * cos(w0);
    final b2 = 1 - alpha * A;
    final a0 = 1 + alpha / A;
    final a1 = -2 * cos(w0);
    final a2 = 1 - alpha / A;

    // Normalize
    final b0n = b0 / a0;
    final b1n = b1 / a0;
    final b2n = b2 / a0;
    final a1n = a1 / a0;
    final a2n = a2 / a0;

    // Complex frequency response
    final cosw1 = cos(w);
    final cosw2 = cos(2 * w);
    final sinw1 = sin(w);
    final sinw2 = sin(2 * w);

    final numReal = b0n + b1n * cosw1 + b2n * cosw2;
    final numImag = -(b1n * sinw1 + b2n * sinw2);
    final denReal = 1 + a1n * cosw1 + a2n * cosw2;
    final denImag = -(a1n * sinw1 + a2n * sinw2);

    final magSq =
        (numReal * numReal + numImag * numImag) /
        (denReal * denReal + denImag * denImag);

    return 20 * log(sqrt(magSq)) / ln10;
  }

  /// Calculates the combined frequency response across a logarithmic range.
  ///
  /// Returns a list of dB values at [numPoints] evenly spaced in log-frequency.
  static List<double> combinedResponse({
    required List<BiquadBand> bands,
    required double startFreq,
    required double endFreq,
    required int numPoints,
  }) {
    final response = List<double>.filled(numPoints, 0.0);
    final logStart = log(startFreq);
    final logEnd = log(endFreq);
    final logStep = (logEnd - logStart) / (numPoints - 1);

    for (var i = 0; i < numPoints; i++) {
      final freq = exp(logStart + i * logStep);
      var totalGain = 0.0;
      for (final band in bands) {
        totalGain += peakingEqMagnitude(
          freq: freq,
          f0: band.frequency,
          gainDb: band.gainDb,
          q: band.q,
        );
      }
      response[i] = totalGain.clamp(-24.0, 24.0);
    }
    return response;
  }
}

/// A single biquad band for combined response calculation.
class BiquadBand {
  const BiquadBand({
    required this.frequency,
    required this.gainDb,
    this.q = 1.0,
  });

  final double frequency;
  final double gainDb;
  final double q;
}
