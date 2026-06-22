part of 'parametric_eq_screen.dart';

// ─── Band Color ─────────────────────────────────────────────────────────────

Color _bandColor(int index) =>
    ProAudioColors.bandColors[index % ProAudioColors.bandColors.length];

// ─── Frequency Response Helpers ─────────────────────────────────────────────

double _freqToX(double freq, double width) {
  if (freq <= 0) return 0;
  return (math.log(freq / 20) / math.log(1000)) * width;
}

double _xToFreq(double x, double width) {
  final t = (x / width).clamp(0.0, 1.0);
  return 20 * math.pow(1000, t).toDouble();
}

double _dbToY(double db, double height) {
  // +24 dB at top, -24 dB at bottom, 0 dB at center
  final normalized = (24 - db) / 48;
  return normalized * height;
}

/// Peaking EQ gain at a given frequency.
double _peakGain(double f, double f0, double gainDb, double q) {
  if (gainDb == 0) return 0;
  final ratio = f / f0;
  final bw = 1 / q;
  final normalizedDist = (ratio - 1 / ratio) * bw;
  final magnitude = 1 / (1 + normalizedDist * normalizedDist);
  return gainDb * magnitude;
}

/// Low shelf gain: boost/cut below fc, smooth transition above.
double _lowShelfGain(double f, double fc, double gainDb, double q) {
  if (gainDb == 0) return 0;
  final ratio = f / fc;
  final s = 1 / q; // slope factor
  // Smooth sigmoid transition centered at fc
  final t = 1 / (1 + math.exp(-s * 4 * (ratio - 1)));
  return gainDb * (1 - t);
}

/// High shelf gain: boost/cut above fc, smooth transition below.
double _highShelfGain(double f, double fc, double gainDb, double q) {
  if (gainDb == 0) return 0;
  final ratio = f / fc;
  final s = 1 / q;
  final t = 1 / (1 + math.exp(-s * 4 * (ratio - 1)));
  return gainDb * t;
}

/// High-pass (low-cut) rolloff: -24 dB/octave below fc.
double _lowCutGain(double f, double fc, double q) {
  if (f >= fc) return 0;
  final ratio = fc / f;
  final order = (1 / q * 2).clamp(1.0, 4.0);
  final attenuation = -20 * order * math.log(ratio) / math.log(2);
  return attenuation.clamp(-36.0, 0.0);
}

/// Low-pass (high-cut) rolloff: -24 dB/octave above fc.
double _highCutGain(double f, double fc, double q) {
  if (f <= fc) return 0;
  final ratio = f / fc;
  final order = (1 / q * 2).clamp(1.0, 4.0);
  final attenuation = -20 * order * math.log(ratio) / math.log(2);
  return attenuation.clamp(-36.0, 0.0);
}

/// Calculate combined frequency response for a list of bands at a pixel x.
double _bandGainAtFreq(double freq, ParametricEqBand band) {
  if (!band.enabled) return 0;
  switch (band.type) {
    case BandType.peak:
      return _peakGain(freq, band.frequency, band.gain, band.q);
    case BandType.lowShelf:
      return _lowShelfGain(freq, band.frequency, band.gain, band.q);
    case BandType.highShelf:
      return _highShelfGain(freq, band.frequency, band.gain, band.q);
    case BandType.lowCut:
      return _lowCutGain(freq, band.frequency, band.q);
    case BandType.highCut:
      return _highCutGain(freq, band.frequency, band.q);
  }
}

/// Calculate combined response across pixel width.
List<double> _calculateResponse(List<ParametricEqBand> bands, int width) {
  final response = List<double>.filled(width, 0.0);
  for (var x = 0; x < width; x++) {
    final freq = _xToFreq(x.toDouble(), width.toDouble());
    var totalDb = 0.0;
    for (final band in bands) {
      totalDb += _bandGainAtFreq(freq, band);
    }
    response[x] = totalDb.clamp(-36.0, 24.0);
  }
  return response;
}

// ─── Frequency Label Helper ─────────────────────────────────────────────────

String _formatFrequency(double hz) {
  if (hz >= 1000) {
    final khz = hz / 1000;
    return khz == khz.roundToDouble()
        ? '${khz.toInt()} kHz'
        : '${khz.toStringAsFixed(1)} kHz';
  }
  return '${hz.round()} Hz';
}

String _formatGain(double db) {
  if (db > 0) return '+${db.toStringAsFixed(1)}';
  return db.toStringAsFixed(1);
}

// ─── Band Type Label ────────────────────────────────────────────────────────

String _bandTypeLabel(BandType type) {
  switch (type) {
    case BandType.peak:
      return 'Peak';
    case BandType.lowShelf:
      return 'Low Shelf';
    case BandType.highShelf:
      return 'High Shelf';
    case BandType.lowCut:
      return 'Low Cut';
    case BandType.highCut:
      return 'High Cut';
  }
}
