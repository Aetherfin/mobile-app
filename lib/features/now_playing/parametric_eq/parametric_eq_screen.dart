import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/pro_audio.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../utils/display_error.dart';
import '../../../utils/log.dart';
import '../parametric_eq_state.dart';
import '../parametric_presets.dart';

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

    // White border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(x, y), radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ParametricEqPainter oldDelegate) =>
      oldDelegate.bands != bands || oldDelegate.selectedBand != selectedBand;
}

// ─── Interactive Curve View ─────────────────────────────────────────────────

class _ParametricEqCurveView extends StatefulWidget {
  const _ParametricEqCurveView({
    required this.bands,
    required this.selectedBand,
    required this.onBandChanged,
    required this.onBandSelected,
  });

  final List<ParametricEqBand> bands;
  final int? selectedBand;
  final void Function(int index, ParametricEqBand band) onBandChanged;
  final void Function(int? index) onBandSelected;

  @override
  State<_ParametricEqCurveView> createState() => _ParametricEqCurveViewState();
}

class _ParametricEqCurveViewState extends State<_ParametricEqCurveView> {
  int? _draggingBand;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: (_) => setState(() => _draggingBand = null),
      onTapUp: _handleTap,
      child: CustomPaint(
        painter: _ParametricEqPainter(
          bands: widget.bands,
          selectedBand: _draggingBand ?? widget.selectedBand,
        ),
        size: Size.infinite,
      ),
    );
  }

  void _handleTap(TapUpDetails details) {
    final idx = _bandAtPosition(details.localPosition);
    widget.onBandSelected(idx);
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
    final w = context.size?.width ?? 400;

    // Vertical drag = gain (except for cut types)
    final newGain =
        (band.type == BandType.lowCut || band.type == BandType.highCut)
        ? band.gain
        : (band.gain - details.delta.dy * 0.5).clamp(-24.0, 12.0);

    // Horizontal drag = frequency
    final newFreq = _xToFreq(details.localPosition.dx, w).clamp(20.0, 20000.0);

    widget.onBandChanged(
      _draggingBand!,
      ParametricEqBand(
        frequency: newFreq,
        gain: newGain,
        q: band.q,
        type: band.type,
        enabled: band.enabled,
      ),
    );
  }

  int? _bandAtPosition(Offset pos) {
    final w = context.size?.width ?? 400;
    final h = context.size?.height ?? 200;
    for (var i = 0; i < widget.bands.length; i++) {
      if (!widget.bands[i].enabled) continue;
      final band = widget.bands[i];
      final handleX = _freqToX(band.frequency, w);
      final handleGain =
          (band.type == BandType.lowCut || band.type == BandType.highCut)
          ? -6.0
          : band.gain;
      final handleY = _dbToY(handleGain, h);
      final dist = (Offset(handleX, handleY) - pos).distance;
      if (dist < 24) return i;
    }
    return null;
  }
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

// ═════════════════════════════════════════════════════════════════════════════
// ParametricEqScreen
// ═════════════════════════════════════════════════════════════════════════════

class ParametricEqScreen extends ConsumerStatefulWidget {
  const ParametricEqScreen({super.key});

  @override
  ConsumerState<ParametricEqScreen> createState() => _ParametricEqScreenState();
}

class _ParametricEqScreenState extends ConsumerState<ParametricEqScreen> {
  ParametricEqState _eqState = ParametricEqState();
  int _selectedBand = 0;
  bool _loaded = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      // Load parametric EQ from the unified audio effects key
      final svc = ref.read(playerServiceProvider);
      final current = svc.audioEffects;
      final loaded = ParametricEqState.fromCustomFilters(current.custom);
      if (!_disposed && mounted) {
        setState(() {
          _eqState = loaded;
          _loaded = true;
          // Clamp selected band
          if (_selectedBand >= _eqState.bands.length) {
            _selectedBand = _eqState.bands.length - 1;
          }
        });
      } else if (_disposed) {
        // Widget was disposed during load, but we can still update the state
        // in case it's rebuilt
        _eqState = loaded;
        _loaded = true;
      }
    } catch (e, stack) {
      afLog(
        'audio',
        'Failed to load parametric EQ',
        error: e,
        stackTrace: stack,
      );
      // Fall back to defaults so the screen is still usable
      if (!_disposed && mounted) {
        setState(() {
          _eqState = ParametricEqState();
          _loaded = true;
        });
      } else {
        _eqState = ParametricEqState();
        _loaded = true;
      }
    }
  }

  void _onBandChanged(int index, ParametricEqBand band) {
    setState(() {
      _eqState.setBand(index, band);
    });
    _saveAndApply();
  }

  void _onBandSelected(int? index) {
    if (index != null && index < _eqState.bands.length) {
      setState(() => _selectedBand = index);
    }
  }

  void _onToggleBand(int index) {
    setState(() {
      _eqState.toggleBand(index);
    });
    _saveAndApply();
  }

  void _onFrequencyChanged(double value) {
    final band = _eqState.bands[_selectedBand];
    setState(() {
      _eqState.setBand(
        _selectedBand,
        ParametricEqBand(
          frequency: value,
          gain: band.gain,
          q: band.q,
          type: band.type,
          enabled: band.enabled,
        ),
      );
    });
    _saveAndApply();
  }

  void _onGainChanged(double value) {
    final band = _eqState.bands[_selectedBand];
    setState(() {
      _eqState.setBand(
        _selectedBand,
        ParametricEqBand(
          frequency: band.frequency,
          gain: value,
          q: band.q,
          type: band.type,
          enabled: band.enabled,
        ),
      );
    });
    _saveAndApply();
  }

  void _onQChanged(double value) {
    final band = _eqState.bands[_selectedBand];
    setState(() {
      _eqState.setBand(
        _selectedBand,
        ParametricEqBand(
          frequency: band.frequency,
          gain: band.gain,
          q: value,
          type: band.type,
          enabled: band.enabled,
        ),
      );
    });
    _saveAndApply();
  }

  void _onTypeChanged(BandType type) {
    final band = _eqState.bands[_selectedBand];
    setState(() {
      _eqState.setBand(
        _selectedBand,
        ParametricEqBand(
          frequency: band.frequency,
          gain: band.gain,
          q: band.q,
          type: type,
          enabled: band.enabled,
        ),
      );
    });
    _saveAndApply();
  }

  void _addBand() {
    if (_eqState.bands.length >= ParametricEqState.maxBands) return;
    setState(() {
      _eqState.addBand();
      _selectedBand = _eqState.bands.length - 1;
    });
    _saveAndApply();
  }

  void _removeBand(int index) {
    if (_eqState.bands.length <= 1) return;
    setState(() {
      _eqState.removeBand(index);
      if (_selectedBand >= _eqState.bands.length) {
        _selectedBand = _eqState.bands.length - 1;
      }
    });
    _saveAndApply();
  }

  void _applyPreset(String name) {
    final preset = kParametricPresets[name];
    if (preset == null) return;
    setState(() {
      // Replace bands with preset bands
      _eqState.bands.clear();
      for (final b in preset.bands) {
        _eqState.bands.add(
          ParametricEqBand(
            frequency: b.frequency,
            gain: b.gain,
            q: b.q,
            type: BandType.peak,
            enabled: true,
          ),
        );
      }
      _selectedBand = 0;
    });
    _saveAndApply();
  }

  void _resetAll() {
    setState(() {
      _eqState = ParametricEqState();
      _selectedBand = 0;
    });
    _saveAndApply();
  }

  Future<void> _saveAndApply() async {
    if (!mounted) return;
    try {
      final svc = ref.read(playerServiceProvider);
      final current = svc.audioEffects;
      final merged = _eqState.toAudioEffects(current);
      await svc.updateAudioEffects((_) => merged);
      await PlayerSettingsStore.saveAudioEffects(merged);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Failed to apply'))),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        backgroundColor: AfColors.surfaceCanvas,
        appBar: AppBar(
          backgroundColor: AfColors.surfaceCanvas,
          surfaceTintColor: Colors.transparent,
          title: const Text('Parametric EQ'),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AfColors.accentPrimary),
        ),
      );
    }

    final band = _eqState.bands[_selectedBand];
    final isCutType =
        band.type == BandType.lowCut || band.type == BandType.highCut;

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        title: const Text('Parametric EQ'),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: _resetAll,
            child: Text(
              'Reset',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.semanticError,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          // ── Frequency Response Curve ──────────────────────────────────
          _buildCurveSection(),
          const SizedBox(height: AfSpacing.s12),

          // ── Preset Chips ──────────────────────────────────────────────
          _buildPresetChips(),
          const SizedBox(height: AfSpacing.s12),

          // ── Band Selector ─────────────────────────────────────────────
          _buildBandSelector(),
          const SizedBox(height: AfSpacing.s8),

          // ── Band Controls Card ────────────────────────────────────────
          _buildBandControls(band, isCutType),
          const SizedBox(height: AfSpacing.s12),

          // ── Add Band Button ───────────────────────────────────────────
          if (_eqState.bands.length < ParametricEqState.maxBands)
            _buildAddBandButton(),

          const SizedBox(height: AfSpacing.s24),
        ],
      ),
    );
  }

  // ── Curve Section ──────────────────────────────────────────────────────

  Widget _buildCurveSection() {
    return Material(
      color: AfColors.surfaceLow,
      borderRadius: AfRadii.borderLg,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 200,
        child: Stack(
          children: [
            // dB labels on left edge
            Positioned(
              left: AfSpacing.s4,
              top: 0,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final db in [12.0, 6.0, 0.0, -6.0, -12.0, -18.0, -24.0])
                    Text(
                      db >= 0 ? '+${db.toInt()}' : '${db.toInt()}',
                      style: AfTypography.overline.copyWith(
                        color: AfColors.textTertiary.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            // Frequency labels at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: AfSpacing.s4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final hz in ['20', '100', '500', '2k', '10k', '20k'])
                    Text(
                      hz,
                      style: AfTypography.overline.copyWith(
                        color: AfColors.textTertiary.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            // Interactive curve
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(AfSpacing.s8),
                child: _ParametricEqCurveView(
                  bands: _eqState.bands,
                  selectedBand: _selectedBand,
                  onBandChanged: _onBandChanged,
                  onBandSelected: _onBandSelected,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Preset Chips ───────────────────────────────────────────────────────

  Widget _buildPresetChips() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kParametricPresets.length,
        separatorBuilder: (_, _) => const SizedBox(width: AfSpacing.s8),
        itemBuilder: (context, index) {
          final name = kParametricPresets.keys.elementAt(index);
          return GestureDetector(
            onTap: () => _applyPreset(name),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s12,
                vertical: AfSpacing.s4,
              ),
              decoration: BoxDecoration(
                color: AfColors.surfaceBase,
                borderRadius: AfRadii.borderPill,
                border: Border.all(color: AfColors.surfaceHigh),
              ),
              child: Text(
                name,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Band Selector ─────────────────────────────────────────────────────

  Widget _buildBandSelector() {
    final selected = _eqState.bands[_selectedBand];
    return Material(
      color: AfColors.surfaceBase,
      borderRadius: AfRadii.borderSm,
      child: InkWell(
        borderRadius: AfRadii.borderSm,
        onTap: _showBandPicker,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s12,
            vertical: AfSpacing.s8,
          ),
          child: Row(
            children: [
              // Color indicator
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _bandColor(_selectedBand),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AfSpacing.s8),
              Text(
                'Band ${_selectedBand + 1}',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textPrimary,
                ),
              ),
              const SizedBox(width: AfSpacing.s4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s8,
                  vertical: AfSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: _bandColor(_selectedBand).withValues(alpha: 0.15),
                  borderRadius: AfRadii.borderPill,
                ),
                child: Text(
                  _formatFrequency(selected.frequency),
                  style: AfTypography.caption.copyWith(
                    color: _bandColor(_selectedBand),
                  ),
                ),
              ),
              const Spacer(),
              // Enable/disable toggle
              GestureDetector(
                onTap: () => _onToggleBand(_selectedBand),
                child: AnimatedContainer(
                  duration: AfDurations.quick,
                  curve: AfCurves.easeStandard,
                  width: 44,
                  height: 26,
                  decoration: BoxDecoration(
                    color: selected.enabled
                        ? _bandColor(_selectedBand)
                        : AfColors.surfaceHigh,
                    borderRadius: AfRadii.borderPill,
                  ),
                  child: AnimatedAlign(
                    duration: AfDurations.quick,
                    alignment: selected.enabled
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    curve: AfCurves.easeStandard,
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: const BoxDecoration(
                        color: AfColors.textPrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AfSpacing.s8),
              const Icon(
                LucideIcons.chevronDown,
                size: 16,
                color: AfColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBandPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AfColors.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AfRadii.lg)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AfSpacing.s8),
              Container(
                width: 32,
                height: 4,
                decoration: const BoxDecoration(
                  color: AfColors.surfaceHigh,
                  borderRadius: AfRadii.borderPill,
                ),
              ),
              const SizedBox(height: AfSpacing.s12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                child: Row(
                  children: [
                    Text(
                      'SELECT BAND',
                      style: AfTypography.label.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    if (_eqState.bands.length > 1)
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _removeBand(_selectedBand);
                        },
                        child: const Icon(
                          LucideIcons.trash2,
                          size: 18,
                          color: AfColors.semanticError,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AfSpacing.s8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _eqState.bands.length,
                  itemBuilder: (context, index) {
                    final b = _eqState.bands[index];
                    final isSelected = index == _selectedBand;
                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _bandColor(index),
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            'Band ${index + 1}',
                            style: AfTypography.bodyMedium.copyWith(
                              color: isSelected
                                  ? _bandColor(index)
                                  : AfColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(width: AfSpacing.s8),
                          Text(
                            _bandTypeLabel(b.type),
                            style: AfTypography.caption.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatFrequency(b.frequency),
                            style: AfTypography.monoSmall.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                          if (!b.enabled) ...[
                            const SizedBox(width: AfSpacing.s4),
                            const Icon(
                              LucideIcons.eyeOff,
                              size: 14,
                              color: AfColors.textDisabled,
                            ),
                          ],
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _selectedBand = index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Band Controls Card ────────────────────────────────────────────────

  Widget _buildBandControls(ParametricEqBand band, bool isCutType) {
    final color = _bandColor(_selectedBand);
    return Material(
      color: AfColors.surfaceBase,
      borderRadius: AfRadii.borderLg,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AfSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Type selector
            Row(
              children: [
                Text(
                  'Type',
                  style: AfTypography.bodyMedium.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s8,
                    vertical: AfSpacing.s2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: AfRadii.borderPill,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<BandType>(
                      value: band.type,
                      isDense: true,
                      dropdownColor: AfColors.surfaceRaised,
                      style: AfTypography.bodySmall.copyWith(color: color),
                      items: BandType.values.map((t) {
                        return DropdownMenuItem(
                          value: t,
                          child: Text(_bandTypeLabel(t)),
                        );
                      }).toList(),
                      onChanged: (t) {
                        if (t != null) _onTypeChanged(t);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AfSpacing.s12),

            // Frequency slider
            _buildSliderRow(
              label: 'Freq',
              value: band.frequency,
              min: 20,
              max: 20000,
              display: _formatFrequency(band.frequency),
              color: color,
              onChanged: _onFrequencyChanged,
            ),
            const SizedBox(height: AfSpacing.s4),

            // Gain slider (hidden for cut types)
            if (!isCutType)
              _buildSliderRow(
                label: 'Gain',
                value: band.gain,
                min: -24,
                max: 12,
                display: '${_formatGain(band.gain)} dB',
                color: color,
                onChanged: _onGainChanged,
              ),
            if (isCutType) const SizedBox(height: AfSpacing.s4),

            // Q slider
            _buildSliderRow(
              label: 'Q',
              value: band.q,
              min: 0.3,
              max: 12.0,
              display: band.q.toStringAsFixed(1),
              color: color,
              onChanged: _onQChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    // For frequency, use logarithmic slider
    final isLogarithmic = label == 'Freq';

    // Convert value to slider position and back
    double sliderValue;
    if (isLogarithmic) {
      final logMin = math.log(min) / math.log(10);
      final logMax = math.log(max) / math.log(10);
      final logVal = math.log(value) / math.log(10);
      sliderValue = ((logVal - logMin) / (logMax - logMin)).clamp(0.0, 1.0);
    } else {
      sliderValue = ((value - min) / (max - min)).clamp(0.0, 1.0);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(label, style: AfTypography.bodyMedium),
            ),
            const Spacer(),
            Text(display, style: AfTypography.mono.copyWith(color: color)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: color,
            inactiveTrackColor: AfColors.surfaceHigh,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: sliderValue,
            min: 0,
            max: 1,
            onChanged: (v) {
              if (isLogarithmic) {
                final logMin = math.log(min) / math.log(10);
                final logMax = math.log(max) / math.log(10);
                final logVal = logMin + v * (logMax - logMin);
                final freq = math.pow(10, logVal).toDouble();
                onChanged(freq.clamp(min, max));
              } else {
                final actual = min + v * (max - min);
                onChanged(actual.clamp(min, max));
              }
            },
          ),
        ),
      ],
    );
  }

  // ── Add Band Button ──────────────────────────────────────────────────

  Widget _buildAddBandButton() {
    return GestureDetector(
      onTap: _addBand,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AfSpacing.s12),
        decoration: BoxDecoration(
          color: AfColors.surfaceBase,
          borderRadius: AfRadii.borderSm,
          border: Border.all(
            color: AfColors.accentPrimary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              LucideIcons.plus,
              size: 16,
              color: AfColors.accentPrimary,
            ),
            const SizedBox(width: AfSpacing.s8),
            Text(
              'Add Band (${_eqState.bands.length}/${ParametricEqState.maxBands})',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.accentPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
