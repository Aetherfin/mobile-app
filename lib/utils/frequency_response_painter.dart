import 'dart:math';

import 'package:flutter/material.dart';

import '../features/now_playing/parametric_band.dart';
import '../design_tokens/pro_audio.dart';
import 'glow_effects.dart';

/// CustomPainter that draws the professional frequency response curve.
///
/// Features:
/// - Logarithmic frequency X-axis (20 Hz – 20 kHz)
/// - dB Y-axis with grid lines at ±3/6/12
/// - Combined EQ curve with 3-layer glow effect
/// - Draggable band nodes with color coding
/// - Frequency labels below the grid
class FrequencyResponsePainter extends CustomPainter {
  FrequencyResponsePainter({
    required this.bands,
    required this.selectedBand,
    required this.accentColor,
  });

  final List<ParametricBand> bands;
  final int? selectedBand;
  final Color accentColor;

  // ── Static helpers (testable without paint context) ──────────────────────

  /// Map frequency (Hz) to normalized 0.0–1.0 position (logarithmic).
  static double freqToNormalized(double freq) {
    const minFreq = 20.0;
    const maxFreq = 20000.0;
    return (log(freq / minFreq) / log(maxFreq / minFreq)).clamp(0.0, 1.0);
  }

  /// Map normalized position back to frequency (Hz).
  static double normalizedToFreq(double normalized) {
    const minFreq = 20.0;
    const maxFreq = 20000.0;
    return minFreq *
        pow(maxFreq / minFreq, normalized.clamp(0.0, 1.0)).toDouble();
  }

  /// Map dB gain to Y coordinate. 0 dB = center.
  static double dbToY(double db, double height, {double dbRange = 12.0}) {
    final center = height / 2;
    return center - (db / dbRange) * center;
  }

  /// Standard grid frequency labels for the X-axis.
  static const List<String> gridFrequencyLabels = [
    '20',
    '50',
    '100',
    '200',
    '500',
    '1k',
    '2k',
    '5k',
    '10k',
    '20k',
  ];

  /// Standard grid dB labels for the Y-axis.
  static const List<String> gridDbLabels = ['+12', '+6', '0', '-6', '-12'];

  // ── Painting ──────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = ProAudioColors.bgPanel,
    );

    // 2. dB grid lines
    _drawDbGrid(canvas, size);

    // 3. Frequency grid lines + labels
    _drawFreqGrid(canvas, size);

    // 4. Combined response curve with glow
    _drawCombinedCurve(canvas, size);

    // 5. Individual band curves (subtle)
    _drawBandCurves(canvas, size);

    // 6. Band handles
    _drawBandHandles(canvas, size);
  }

  void _drawDbGrid(Canvas canvas, Size size) {
    const dbValues = [-12.0, -6.0, 0.0, 6.0, 12.0];

    for (final db in dbValues) {
      final y = dbToY(db, size.height);
      final isCenter = db == 0.0;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = isCenter
              ? ProAudioColors.gridLineCenter
              : ProAudioColors.gridLine
          ..strokeWidth = isCenter ? 1.0 : 0.5,
      );

      // dB label on left edge
      final label = db > 0 ? '+${db.toInt()}' : '${db.toInt()}';
      final tp = TextPainter(
        text: TextSpan(text: label, style: ProAudioTypography.dbLabel),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - 6));
    }
  }

  void _drawFreqGrid(Canvas canvas, Size size) {
    final gridFreqs = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
    const labels = gridFrequencyLabels;

    for (var i = 0; i < gridFreqs.length; i++) {
      final freq = gridFreqs[i].toDouble();
      final x = freqToNormalized(freq) * size.width;

      // Vertical grid line
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = ProAudioColors.gridLine
          ..strokeWidth = 0.5,
      );

      // Frequency label below
      if (i < labels.length) {
        final tp = TextPainter(
          text: TextSpan(text: labels[i], style: ProAudioTypography.freqLabel),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, size.height - tp.height - 2));
      }
    }
  }

  void _drawCombinedCurve(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    // Calculate combined response at each pixel
    final response = _calculateResponse(bands, size.width.toInt(), size.height);

    // Build path
    final path = Path();
    final fillPath = Path();
    final zeroY = dbToY(0, size.height);

    path.moveTo(0, response[0]);
    fillPath.moveTo(0, zeroY);
    fillPath.lineTo(0, response[0]);

    for (var x = 1; x < response.length; x++) {
      path.lineTo(x.toDouble(), response[x]);
      fillPath.lineTo(x.toDouble(), response[x]);
    }

    fillPath.lineTo(response.length - 1.0, zeroY);
    fillPath.close();

    // Fill area under curve
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withValues(alpha: 0.15),
          accentColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Draw glowing curve
    GlowEffects.drawGlowingCurve(canvas, path, accentColor);
  }

  void _drawBandCurves(Canvas canvas, Size size) {
    final bandColors = [
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.pink,
    ];

    for (var i = 0; i < bands.length; i++) {
      if (!bands[i].enabled || bands[i].gain == 0) continue;
      final band = bands[i];
      final color = bandColors[i % bandColors.length];

      final path = Path();
      var started = false;
      for (var x = 0; x < size.width.toInt(); x++) {
        final freq = normalizedToFreq(x / size.width);
        final gain = _peakingEqGain(freq, band.frequency, band.gain, band.q);
        final y = dbToY(gain, size.height);
        if (!started) {
          path.moveTo(x.toDouble(), y);
          started = true;
        } else {
          path.lineTo(x.toDouble(), y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawBandHandles(Canvas canvas, Size size) {
    final bandColors = [
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.pink,
    ];

    for (var i = 0; i < bands.length; i++) {
      if (!bands[i].enabled) continue;
      final band = bands[i];
      final color = bandColors[i % bandColors.length];
      final x = freqToNormalized(band.frequency) * size.width;
      final y = dbToY(band.gain, size.height);
      final isSel = i == selectedBand;

      GlowEffects.drawBandNode(canvas, Offset(x, y), color, isActive: isSel);

      final label = _formatBandFreq(band.frequency);
      final tp = TextPainter(
        text: TextSpan(text: label, style: ProAudioTypography.freqLabel),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelY = (y + 14 + tp.height > size.height - 14)
          ? y - tp.height - 4
          : y + 14;
      tp.paint(canvas, Offset(x - tp.width / 2, labelY));
    }
  }

  static String _formatBandFreq(double freq) {
    if (freq >= 1000) {
      final khz = freq / 1000;
      if (khz == khz.roundToDouble()) return '${khz.toInt()}k';
      return '${khz.toStringAsFixed(1)}k';
    }
    return '${freq.round()}Hz';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<double> _calculateResponse(
    List<ParametricBand> bands,
    int width,
    double height,
  ) {
    final response = List<double>.filled(width, dbToY(0, height));
    for (var x = 0; x < width; x++) {
      final freq = normalizedToFreq(x / width);
      var totalGain = 0.0;
      for (final band in bands) {
        if (!band.enabled) continue;
        totalGain += _peakingEqGain(freq, band.frequency, band.gain, band.q);
      }
      totalGain = totalGain.clamp(-24.0, 24.0);
      response[x] = dbToY(totalGain, height);
    }
    return response;
  }

  static double _peakingEqGain(double f, double f0, double gainDb, double q) {
    if (gainDb == 0) return 0;
    final ratio = f / f0;
    final bw = 1 / q;
    final normalizedDist = (ratio - 1 / ratio) * bw;
    final magnitude = 1 / (1 + normalizedDist * normalizedDist);
    return gainDb * magnitude;
  }

  @override
  bool shouldRepaint(covariant FrequencyResponsePainter oldDelegate) =>
      oldDelegate.bands != bands ||
      oldDelegate.selectedBand != selectedBand ||
      oldDelegate.accentColor != accentColor;
}
