part of 'parametric_eq_screen.dart';

// ─── Curve Painter ──────────────────────────────────────────────────────────

class _ParametricEqPainter extends CustomPainter {
  _ParametricEqPainter({required this.bands, required this.selectedBand});

  final List<ParametricEqBand> bands;
  final int? selectedBand;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final response = _calculateResponse(bands, size.width.toInt());
    _drawResponseCurve(canvas, size, response);

    // Draw individual band curves (thin, faded)
    for (var i = 0; i < bands.length; i++) {
      if (bands[i].enabled && i != selectedBand) {
        _drawBandCurve(canvas, size, bands[i], i, 0.2);
      }
    }

    // Draw selected band curve (brighter)
    if (selectedBand != null &&
        selectedBand! < bands.length &&
        bands[selectedBand!].enabled) {
      _drawBandCurve(canvas, size, bands[selectedBand!], selectedBand!, 0.6);
    }

    // Draw handles for enabled bands
    for (var i = 0; i < bands.length; i++) {
      if (bands[i].enabled) {
        _drawHandle(canvas, size, bands[i], i, i == selectedBand);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AfColors.textTertiary.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    // Horizontal grid lines (dB)
    for (var db = -24; db <= 24; db += 6) {
      final y = _dbToY(db.toDouble(), size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical grid lines (frequency)
    final gridFreqs = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
    for (final freq in gridFreqs) {
      final x = _freqToX(freq.toDouble(), size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Zero line (0 dB)
    final zeroPaint = Paint()
      ..color = AfColors.textTertiary.withValues(alpha: 0.25)
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

    // Fill gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AfColors.accentPrimary.withValues(alpha: 0.18),
          AfColors.accentPrimary.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..color = AfColors.accentPrimary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, strokePaint);
  }

  void _drawBandCurve(
    Canvas canvas,
    Size size,
    ParametricEqBand band,
    int index,
    double opacity,
  ) {
    final color = _bandColor(index);
    final path = Path();
    var started = false;
    for (var x = 0; x < size.width.toInt(); x++) {
      final freq = _xToFreq(x.toDouble(), size.width);
      final gain = _bandGainAtFreq(freq, band);
      final y = _dbToY(gain, size.height);
      if (!started) {
        path.moveTo(x.toDouble(), y);
        started = true;
      } else {
        path.lineTo(x.toDouble(), y);
      }
    }

    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
  }

  void _drawHandle(
    Canvas canvas,
    Size size,
    ParametricEqBand band,
    int index,
    bool isSel,
  ) {
    final x = _freqToX(band.frequency, size.width);
    // For cut filters, show handle at -6dB point for visibility
    final handleGain =
        (band.type == BandType.lowCut || band.type == BandType.highCut)
        ? -6.0
        : band.gain;
    final y = _dbToY(handleGain, size.height);

    final color = _bandColor(index);
    final radius = isSel ? 8.0 : 6.0;

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
    canvas.drawCircle(Offset(x, y), radius, handlePaint);

    // Handle border — paint context (glow/highlight), not semantic
    final borderPaint = Paint()
      ..color = AfColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(x, y), radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ParametricEqPainter oldDelegate) =>
      oldDelegate.bands != bands || oldDelegate.selectedBand != selectedBand;
}
