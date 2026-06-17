import 'dart:math';

import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import 'parametric_band.dart';

/// CustomPainter that draws the combined parametric EQ frequency response.
///
/// X-axis: Frequency (logarithmic scale, 20 Hz – 20 kHz)
/// Y-axis: Gain in dB (linear, ±24 dB range)
class ParametricEqCurvePainter extends CustomPainter {
  ParametricEqCurvePainter({
    required this.bands,
    required this.selectedBand,
    required this.accentColor,
  });

  final List<ParametricBand> bands;
  final int? selectedBand;
  final Color accentColor;

  // ── Static helpers (testable without paint context) ──────────────────────

  /// Map x pixel to frequency (logarithmic).
  static double xToFrequency(double x, double width) {
    final t = x / width;
    return (20 * pow(1000, t)).toDouble();
  }

  /// Map frequency to x pixel (logarithmic).
  static double frequencyToX(double freq, double width) {
    return (log(freq / 20) / log(1000)) * width;
  }

  /// Peaking EQ gain approximation at a given frequency.
  static double peakingEqGain(double f, double f0, double gainDb, double q) {
    if (gainDb == 0) return 0;
    final ratio = f / f0;
    final bw = 1 / q;
    final normalizedDist = (ratio - 1 / ratio) * bw;
    final magnitude = 1 / (1 + normalizedDist * normalizedDist);
    return gainDb * magnitude;
  }

  /// Calculate frequency response across pixel width.
  static List<double> calculateResponse(List<ParametricBand> bands, int width) {
    final response = List<double>.filled(width, 0.0);
    for (var x = 0; x < width; x++) {
      final freq = xToFrequency(x.toDouble(), width.toDouble());
      var totalGain = 0.0;
      for (final band in bands) {
        if (!band.enabled) continue;
        totalGain += peakingEqGain(freq, band.frequency, band.gain, band.q);
      }
      response[x] = totalGain.clamp(-24.0, 24.0);
    }
    return response;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw frequency grid
    _drawGrid(canvas, size);

    // 2. Calculate and draw combined response
    final response = calculateResponse(bands, size.width.toInt());
    _drawResponseCurve(canvas, size, response);

    // 3. Draw individual band curves
    for (var i = 0; i < bands.length; i++) {
      if (bands[i].enabled) {
        _drawBandCurve(canvas, size, bands[i], i);
      }
    }

    // 4. Draw band handles
    for (var i = 0; i < bands.length; i++) {
      if (bands[i].enabled) {
        _drawHandle(canvas, size, bands[i], i, i == selectedBand);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AfColors.textPrimary
          .withValues(alpha: 0.08) // grid line — paint context, not semantic
      ..strokeWidth = 0.5;

    // Horizontal grid lines (dB)
    for (var db = -24; db <= 24; db += 6) {
      final y = _dbToY(db.toDouble(), size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical grid lines (frequency)
    final gridFreqs = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
    for (final freq in gridFreqs) {
      final x = frequencyToX(freq.toDouble(), size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Zero line (0 dB)
    final zeroPaint = Paint()
      ..color = AfColors.textPrimary
          .withValues(alpha: 0.2) // zero line — paint context, not semantic
      ..strokeWidth = 1;
    final zeroY = _dbToY(0, size.height);
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);
  }

  void _drawResponseCurve(Canvas canvas, Size size, List<double> response) {
    if (response.isEmpty) return;

    final path = Path();
    final fillPath = Path();
    final zeroY = _dbToY(0, size.height);

    path.moveTo(0, _dbToY(response[0], size.height));
    fillPath.moveTo(0, zeroY);
    fillPath.lineTo(0, _dbToY(response[0], size.height));

    for (var x = 1; x < response.length; x++) {
      final y = _dbToY(response[x], size.height);
      path.lineTo(x.toDouble(), y);
      fillPath.lineTo(x.toDouble(), y);
    }

    fillPath.lineTo(response.length - 1.0, zeroY);
    fillPath.close();

    // Fill area
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

    // Stroke line
    final strokePaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, strokePaint);
  }

  void _drawBandCurve(
    Canvas canvas,
    Size size,
    ParametricBand band,
    int index,
  ) {
    final bandColors = [
      AfColors.eqBand1,
      AfColors.eqBand2,
      AfColors.eqBand3,
      AfColors.eqBand4,
      AfColors.eqBand5,
    ];
    final color = bandColors[index % bandColors.length];

    final path = Path();
    var started = false;
    for (var x = 0; x < size.width.toInt(); x++) {
      final freq = xToFrequency(x.toDouble(), size.width);
      final gain = peakingEqGain(freq, band.frequency, band.gain, band.q);
      final y = _dbToY(gain, size.height);
      if (!started) {
        path.moveTo(x.toDouble(), y);
        started = true;
      } else {
        path.lineTo(x.toDouble(), y);
      }
    }

    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
  }

  void _drawHandle(
    Canvas canvas,
    Size size,
    ParametricBand band,
    int index,
    bool isSel,
  ) {
    final x = frequencyToX(band.frequency, size.width);
    final y = _dbToY(band.gain, size.height);

    final bandColors = [
      AfColors.eqBand1,
      AfColors.eqBand2,
      AfColors.eqBand3,
      AfColors.eqBand4,
      AfColors.eqBand5,
    ];
    final color = bandColors[index % bandColors.length];

    // Outer glow if selected
    if (isSel) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(x, y), 12, glowPaint);
    }

    // Handle circle
    final handlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), isSel ? 8 : 6, handlePaint);

    // Handle border — paint context (glow/highlight), not semantic
    final borderPaint = Paint()
      ..color = AfColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(x, y), isSel ? 8 : 6, borderPaint);

    final label = _formatBandFreq(band.frequency);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: AfTypography.monoXSmall.copyWith(
          color: AfColors.textTertiary.withValues(
            alpha: 0.45,
          ), // paint context — canvas label
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelY = (y + 16 + tp.height > size.height - 14)
        ? y - tp.height - 4
        : y + 16;
    tp.paint(canvas, Offset(x - tp.width / 2, labelY));
  }

  static String _formatBandFreq(double freq) {
    if (freq >= 1000) {
      final khz = freq / 1000;
      if (khz == khz.roundToDouble()) return '${khz.toInt()}k';
      return '${khz.toStringAsFixed(1)}k';
    }
    return '${freq.round()}Hz';
  }

  /// Map dB value to y pixel coordinate.
  double _dbToY(double db, double height) {
    // +24 dB at top, -24 dB at bottom, 0 dB at center
    final normalized = (24 - db) / 48;
    return normalized * height;
  }

  @override
  bool shouldRepaint(covariant ParametricEqCurvePainter oldDelegate) =>
      oldDelegate.bands != bands ||
      oldDelegate.selectedBand != selectedBand ||
      oldDelegate.accentColor != accentColor;
}

/// Interactive wrapper around the curve painter.
class ParametricEqCurveView extends StatefulWidget {
  const ParametricEqCurveView({
    super.key,
    required this.bands,
    required this.onBandChanged,
    required this.onBandSelected,
    required this.accentColor,
    this.onPanEnd,
  });

  final List<ParametricBand> bands;
  final void Function(int index, ParametricBand band) onBandChanged;
  final void Function(int? index) onBandSelected;
  final Color accentColor;
  final VoidCallback? onPanEnd;

  @override
  State<ParametricEqCurveView> createState() => _ParametricEqCurveViewState();
}

class _ParametricEqCurveViewState extends State<ParametricEqCurveView> {
  int? _draggingBand;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: (_) {
        setState(() => _draggingBand = null);
        widget.onPanEnd?.call();
      },
      child: RepaintBoundary(
        child: CustomPaint(
          painter: ParametricEqCurvePainter(
            bands: widget.bands,
            selectedBand: _draggingBand,
            accentColor: widget.accentColor,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  void _handlePanStart(DragStartDetails details) {
    _draggingBand = _bandAtPosition(details.localPosition);
    if (_draggingBand != null) {
      widget.onBandSelected(_draggingBand);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_draggingBand == null) return;
    final band = widget.bands[_draggingBand!];
    // Vertical drag = gain
    final newGain = (band.gain - details.delta.dy * 0.5).clamp(-24.0, 24.0);
    // Horizontal drag = frequency
    final newFreq = ParametricEqCurvePainter.xToFrequency(
      details.localPosition.dx,
      context.size?.width ?? 400,
    ).clamp(20.0, 20000.0);
    widget.onBandChanged(
      _draggingBand!,
      ParametricBand(
        frequency: newFreq,
        gain: newGain,
        q: band.q,
        enabled: band.enabled,
      ),
    );
  }

  int? _bandAtPosition(Offset pos) {
    // Find closest band handle to tap position
    final width = context.size?.width ?? 400;
    final height = context.size?.height ?? 200;
    for (var i = 0; i < widget.bands.length; i++) {
      if (!widget.bands[i].enabled) continue;
      final handleX = ParametricEqCurvePainter.frequencyToX(
        widget.bands[i].frequency,
        width,
      );
      final handleY = _dbToY(widget.bands[i].gain, height);
      final handlePos = Offset(handleX, handleY);
      if ((handlePos - pos).distance < 20) return i;
    }
    return null;
  }

  double _dbToY(double db, double height) {
    final normalized = (24 - db) / 48;
    return normalized * height;
  }
}
