import 'dart:math' as math;

// ignore_for_file: unused_element_parameter
// _IsolatedSliderRow is kept as a reusable component; its unused optional
// params are intentional for future use by other screens.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/pro_audio.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../utils/display_error.dart';
import '../../../utils/log.dart';
import '../../../widgets/af_dialog.dart';
import '../../../widgets/af_loading_indicator.dart';
import 'package:aetherfin/core/audio/models/parametric_eq_state.dart';
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

// ─── Interactive Curve View ─────────────────────────────────────────────────

class _ParametricEqCurveView extends StatefulWidget {
  const _ParametricEqCurveView({
    required this.bands,
    required this.selectedBand,
    required this.onBandChanged,
    required this.onBandSelected,
    this.onPanEnd,
  });

  final List<ParametricEqBand> bands;
  final int? selectedBand;
  final void Function(int index, ParametricEqBand band) onBandChanged;
  final void Function(int? index) onBandSelected;
  final VoidCallback? onPanEnd;

  @override
  State<_ParametricEqCurveView> createState() => _ParametricEqCurveViewState();
}

class _ParametricEqCurveViewState extends State<_ParametricEqCurveView> {
  int? _draggingBand;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Parametric EQ curve. ${widget.bands.where((b) => b.enabled).length} active bands.',
      child: GestureDetector(
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: (_) {
          setState(() => _draggingBand = null);
          widget.onPanEnd?.call();
        },
        onTapUp: _handleTap,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              final band = widget.bands[widget.selectedBand ?? 0];
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                final newFreq = (band.frequency * 0.9).clamp(20.0, 20000.0);
                widget.onBandChanged(
                  widget.selectedBand ?? 0,
                  ParametricEqBand(
                    frequency: newFreq,
                    gain: band.gain,
                    q: band.q,
                    type: band.type,
                    enabled: band.enabled,
                  ),
                );
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                final newFreq = (band.frequency * 1.1).clamp(20.0, 20000.0);
                widget.onBandChanged(
                  widget.selectedBand ?? 0,
                  ParametricEqBand(
                    frequency: newFreq,
                    gain: band.gain,
                    q: band.q,
                    type: band.type,
                    enabled: band.enabled,
                  ),
                );
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                final isCutType =
                    band.type == BandType.lowCut ||
                    band.type == BandType.highCut;
                if (!isCutType) {
                  final newGain = (band.gain + 1).clamp(-24.0, 12.0);
                  widget.onBandChanged(
                    widget.selectedBand ?? 0,
                    ParametricEqBand(
                      frequency: band.frequency,
                      gain: newGain,
                      q: band.q,
                      type: band.type,
                      enabled: band.enabled,
                    ),
                  );
                }
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                final isCutType =
                    band.type == BandType.lowCut ||
                    band.type == BandType.highCut;
                if (!isCutType) {
                  final newGain = (band.gain - 1).clamp(-24.0, 12.0);
                  widget.onBandChanged(
                    widget.selectedBand ?? 0,
                    ParametricEqBand(
                      frequency: band.frequency,
                      gain: newGain,
                      q: band.q,
                      type: band.type,
                      enabled: band.enabled,
                    ),
                  );
                }
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: CustomPaint(
            painter: _ParametricEqPainter(
              bands: widget.bands,
              selectedBand: _draggingBand ?? widget.selectedBand,
            ),
            size: Size.infinite,
          ),
        ),
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

// ─── Isolated Slider Row ────────────────────────────────────────────────────

/// Self-contained slider that holds its own display value locally.
/// Parent only rebuilds on structural changes (band select/add/remove/type).
class _IsolatedSliderRow extends StatefulWidget {
  const _IsolatedSliderRow({
    super.key,
    required this.label,
    required this.initialValue,
    required this.min,
    required this.max,
    required this.display,
    required this.color,
    required this.onChanged,
    this.onChangeEnd,
    this.isLogarithmic = false,
  });

  final String label;
  final double initialValue;
  final double min;
  final double max;
  final String display;
  final Color color;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool isLogarithmic;

  @override
  State<_IsolatedSliderRow> createState() => _IsolatedSliderRowState();
}

class _IsolatedSliderRowState extends State<_IsolatedSliderRow> {
  late double _value = widget.initialValue;

  @override
  void didUpdateWidget(covariant _IsolatedSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _value = widget.initialValue;
    }
  }

  double _toSliderPosition(double val) {
    if (widget.isLogarithmic) {
      final logMin = math.log(widget.min) / math.log(10);
      final logMax = math.log(widget.max) / math.log(10);
      final logVal = math.log(val) / math.log(10);
      return ((logVal - logMin) / (logMax - logMin)).clamp(0.0, 1.0);
    }
    return ((val - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
  }

  double _fromSliderPosition(double pos) {
    if (widget.isLogarithmic) {
      final logMin = math.log(widget.min) / math.log(10);
      final logMax = math.log(widget.max) / math.log(10);
      final logVal = logMin + pos * (logMax - logMin);
      final freq = math.pow(10, logVal).toDouble();
      return freq.clamp(widget.min, widget.max);
    }
    final actual = widget.min + pos * (widget.max - widget.min);
    return actual.clamp(widget.min, widget.max);
  }

  @override
  Widget build(BuildContext context) {
    final displayText = widget.label == 'Freq'
        ? _formatFrequency(_value)
        : widget.label == 'Gain'
        ? '${_formatGain(_value)} dB'
        : _value.toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(widget.label, style: AfTypography.bodyMedium),
            ),
            const Spacer(),
            Text(
              displayText,
              style: AfTypography.mono.copyWith(color: widget.color),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: widget.color,
            inactiveTrackColor: AfColors.surfaceHigh,
            thumbColor: widget.color,
            overlayColor: widget.color.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: _toSliderPosition(_value),
            min: 0,
            max: 1,
            onChanged: (v) {
              final actual = _fromSliderPosition(v);
              setState(() => _value = actual);
              widget.onChanged(actual);
            },
            onChangeEnd: widget.onChangeEnd,
          ),
        ),
      ],
    );
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
  bool _masterEnabled = false;
  String? _activePreset;
  bool _loaded = false;
  bool _disposed = false;

  // ponytail: shared_preferences key for master toggle persistence
  static const _kMasterEnabledKey = 'af.parametric_eq_master_enabled';

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

      // Load master enabled state from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final masterEnabled = prefs.getBool(_kMasterEnabledKey) ?? false;

      if (!_disposed && mounted) {
        setState(() {
          _eqState = loaded;
          _masterEnabled = masterEnabled;
          _loaded = true;
          // Clamp selected band
          if (_selectedBand >= _eqState.bands.length) {
            _selectedBand = _eqState.bands.length - 1;
          }
        });
      } else if (_disposed) {
        _eqState = loaded;
        _masterEnabled = masterEnabled;
        _loaded = true;
      }
    } catch (e, stack) {
      afLog(
        'audio',
        'Failed to load parametric EQ',
        error: e,
        stackTrace: stack,
      );
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
    showBlurDialog<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset Parametric EQ?', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text(
            'This will restore all bands to default frequency and gain settings.',
            style: AfTypography.bodyMedium,
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Cancel'),
              ),
              Focus(
                autofocus: true,
                child: TextButton(
                  onPressed: () {
                    context.pop();
                    _performReset();
                  },
                  child: Text(
                    'Reset',
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.semanticError,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _performReset() {
    setState(() {
      _eqState = ParametricEqState();
      _selectedBand = 0;
      _activePreset = null;
    });
    _saveAndApply();
  }

  void _onMasterToggle(bool value) {
    setState(() => _masterEnabled = value);
    SharedPreferences.getInstance().then(
      (p) => p.setBool(_kMasterEnabledKey, value),
    );
    _saveAndApply();
  }

  Future<void> _saveAndApply() async {
    if (!mounted) return;
    try {
      final svc = ref.read(playerServiceProvider);

      // Strip existing parametric EQ lavfi strings from custom filters
      final currentCustom = svc.audioEffects.custom;
      final nonParametric = currentCustom
          .where((f) => !_isParametricLavfi(f))
          .toList();

      // Re-add parametric EQ strings only if master is enabled
      final List<String> newCustom;
      if (_masterEnabled) {
        final lavfi = _eqState.toLavfiStrings();
        newCustom = [...nonParametric, ...lavfi];
      } else {
        newCustom = nonParametric;
      }

      await svc.updateAudioEffects((current) {
        return current.copyWith(custom: newCustom);
      });
      await PlayerSettingsStore.saveAudioEffects(svc.audioEffects);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Failed to apply'))),
        );
      }
    }
  }

  /// Check if a lavfi filter string belongs to the parametric EQ.
  static bool _isParametricLavfi(String filter) =>
      filter.startsWith('lavfi-equalizer=') ||
      filter.startsWith('lavfi-bass=') ||
      filter.startsWith('lavfi-treble=') ||
      filter.startsWith('lavfi-highpass=') ||
      filter.startsWith('lavfi-lowpass=');

  // ── Slider Conversion Helpers ───────────────────────────────────────────

  static double _freqToSlider(double freq) {
    final logMin = math.log(20) / math.log(10);
    final logMax = math.log(20000) / math.log(10);
    final logVal = math.log(freq.clamp(20.0, 20000.0)) / math.log(10);
    return ((logVal - logMin) / (logMax - logMin)).clamp(0.0, 1.0);
  }

  static double _freqFromSlider(double pos) {
    final logMin = math.log(20) / math.log(10);
    final logMax = math.log(20000) / math.log(10);
    final logVal = logMin + pos * (logMax - logMin);
    return math.pow(10, logVal).toDouble().clamp(20.0, 20000.0);
  }

  static double _gainToSlider(double gain) {
    return ((gain - (-24)) / (12 - (-24))).clamp(0.0, 1.0);
  }

  static double _gainFromSlider(double pos) {
    return (-24 + pos * 36).clamp(-24.0, 12.0);
  }

  static double _qToSlider(double q) {
    return ((q - 0.3) / (12.0 - 0.3)).clamp(0.0, 1.0);
  }

  static double _qFromSlider(double pos) {
    return (0.3 + pos * 11.7).clamp(0.3, 12.0);
  }

  // ── Step Button Helpers ─────────────────────────────────────────────────

  void _stepFrequency(int direction) {
    final band = _eqState.bands[_selectedBand];
    final newFreq =
        (direction > 0 ? band.frequency * 1.1 : band.frequency / 1.1).clamp(
          20.0,
          20000.0,
        );
    _onFrequencyChanged(newFreq);
    _saveAndApply();
  }

  void _stepGain(int direction) {
    final band = _eqState.bands[_selectedBand];
    final newGain = (band.gain + direction * 0.5).clamp(-24.0, 12.0);
    _onGainChanged(newGain);
    _saveAndApply();
  }

  void _stepQ(int direction) {
    final band = _eqState.bands[_selectedBand];
    final newQ = (band.q + direction * 0.1).clamp(0.3, 12.0);
    _onQChanged(newQ);
    _saveAndApply();
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
          child: AfLoadingIndicator(color: AfColors.accentPrimary),
        ),
      );
    }

    final spectral = ref.watch(currentSpectralProvider);
    final band = _eqState.bands[_selectedBand];
    final isCutType =
        band.type == BandType.lowCut || band.type == BandType.highCut;
    final color = _bandColor(_selectedBand);

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
          // ── Master Enable Toggle ─────────────────────────────────────
          _buildMasterToggle(),
          const SizedBox(height: AfSpacing.s8),

          // ── All interactive content ──────────────────────────────────
          Opacity(
            opacity: _masterEnabled ? 1.0 : 0.4,
            child: AbsorbPointer(
              absorbing: !_masterEnabled,
              child: Column(
                children: [
                  // ── Frequency Response Curve (hero, 300dp) ───────────
                  _buildCurveSection(),
                  const SizedBox(height: AfSpacing.s8),

                  // ── Band Strip (color-coded dots) ───────────────────
                  _buildBandStrip(),
                  const SizedBox(height: AfSpacing.s8),

                  // ── Preset Dropdown ──────────────────────────────────
                  _buildPresetDropdown(),
                  const SizedBox(height: AfSpacing.s8),

                  // ── Control Panel ───────────────────────────────────
                  _buildControlPanel(band, isCutType, color, spectral),
                  const SizedBox(height: AfSpacing.s8),

                  // ── Add Band + Trash ────────────────────────────────
                  _buildBandActions(),
                ],
              ),
            ),
          ),

          // ── Bottom spacing ────────────────────────────────────────────
          const SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
        ],
      ),
    );
  }

  // ── Master Enable Toggle ─────────────────────────────────────────────────

  Widget _buildMasterToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AfColors.glassFill,
        borderRadius: AfRadii.borderLg,
        border: Border.all(color: AfColors.glassBorder),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s16,
        vertical: AfSpacing.s12,
      ),
      child: Row(
        children: [
          Icon(
            _masterEnabled ? LucideIcons.power : LucideIcons.powerOff,
            size: 18,
            color: _masterEnabled
                ? AfColors.accentPrimary
                : AfColors.textTertiary,
          ),
          const SizedBox(width: AfSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Parametric EQ',
                  style: AfTypography.bodyMedium.copyWith(
                    color: AfColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _masterEnabled
                      ? 'Active — filters applied'
                      : 'Bypassed — no processing',
                  style: AfTypography.caption.copyWith(
                    color: _masterEnabled
                        ? AfColors.accentPrimary
                        : AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            toggled: _masterEnabled,
            label: 'Parametric EQ: ${_masterEnabled ? "on" : "off"}',
            child: GestureDetector(
              onTap: () => _onMasterToggle(!_masterEnabled),
              child: AnimatedContainer(
                duration: AfDurations.quick,
                curve: AfCurves.easeStandard,
                width: 48,
                height: 28,
                decoration: BoxDecoration(
                  color: _masterEnabled
                      ? AfColors.accentPrimary
                      : AfColors.surfaceHigh,
                  borderRadius: AfRadii.borderPill,
                ),
                child: AnimatedAlign(
                  duration: AfDurations.quick,
                  alignment: _masterEnabled
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  curve: AfCurves.easeStandard,
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s2,
                    ),
                    decoration: const BoxDecoration(
                      color: AfColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Curve Section (300dp hero) ────────────────────────────────────────────

  Widget _buildCurveSection() {
    return Material(
      color: AfColors.surfaceLow,
      borderRadius: AfRadii.borderLg,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 300,
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
                  onPanEnd: _saveAndApply,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Band Strip (color-coded dots) ──────────────────────────────────────────

  Widget _buildBandStrip() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _eqState.bands.length,
        itemBuilder: (context, index) {
          final b = _eqState.bands[index];
          final isSelected = index == _selectedBand;
          final dotSize = isSelected ? 14.0 : 10.0;
          final dotColor = _bandColor(index);
          final opacity = b.enabled ? 1.0 : 0.4;

          return GestureDetector(
            onTap: () => _onBandSelected(index),
            onDoubleTap: () {
              _onBandSelected(index);
              _onToggleBand(index);
            },
            onLongPress: () {
              _onBandSelected(index);
              _showBandPicker();
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: AfDurations.quick,
                    curve: AfCurves.easeStandard,
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor.withValues(alpha: opacity),
                      border: isSelected
                          ? Border.all(color: AfColors.textPrimary, width: 2)
                          : null,
                    ),
                  ),
                  const SizedBox(height: ProAudioSpacing.controlGap),
                  Text(
                    _formatFrequency(b.frequency),
                    style: ProAudioTypography.dbLabel.copyWith(
                      color: AfColors.textTertiary.withValues(alpha: opacity),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Preset Dropdown ───────────────────────────────────────────────────────

  Widget _buildPresetDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AfColors.glassFill,
        borderRadius: AfRadii.borderLg,
        border: Border.all(color: AfColors.glassBorder),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s16,
        vertical: AfSpacing.s8,
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.slidersHorizontal,
            size: 16,
            color: AfColors.textTertiary,
          ),
          const SizedBox(width: AfSpacing.s12),
          Text(
            'Preset',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textSecondary,
            ),
          ),
          const Spacer(),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _activePreset,
              isDense: true,
              dropdownColor: AfColors.surfaceRaised,
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.accentPrimary,
              ),
              hint: Text(
                'Flat',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              items: kParametricPresets.keys.map((name) {
                return DropdownMenuItem(value: name, child: Text(name));
              }).toList(),
              onChanged: (name) {
                if (name != null) {
                  setState(() => _activePreset = name);
                  _applyPreset(name);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Control Panel (glass card) ─────────────────────────────────────────────

  Widget _buildControlPanel(
    ParametricEqBand band,
    bool isCutType,
    Color color,
    Spectral spectral,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AfColors.glassFill,
        borderRadius: AfRadii.borderLg,
        border: Border.all(color: AfColors.glassBorder),
      ),
      padding: const EdgeInsets.all(AfSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Type Segmented Button ──────────────────────────────────────
          _buildTypeSegmented(band.type, spectral),
          const SizedBox(height: AfSpacing.s12),

          // ── Freq Row ─────────────────────────────────────────────────
          _buildValueRow(
            label: 'Freq',
            sliderPos: _freqToSlider(band.frequency),
            displayText: _formatFrequency(band.frequency),
            color: color,
            onSliderChanged: (v) => _onFrequencyChanged(_freqFromSlider(v)),
            onSliderEnd: (_) => _saveAndApply(),
            onStep: _stepFrequency,
          ),
          const SizedBox(height: AfSpacing.s4),

          // ── Gain Row (hidden for cut types) ──────────────────────────
          if (!isCutType)
            _buildValueRow(
              label: 'Gain',
              sliderPos: _gainToSlider(band.gain),
              displayText: '${_formatGain(band.gain)} dB',
              color: color,
              onSliderChanged: (v) => _onGainChanged(_gainFromSlider(v)),
              onSliderEnd: (_) => _saveAndApply(),
              onStep: _stepGain,
            ),
          if (isCutType) const SizedBox(height: AfSpacing.s4),

          // ── Q Row ────────────────────────────────────────────────────
          _buildValueRow(
            label: 'Q',
            sliderPos: _qToSlider(band.q),
            displayText: band.q.toStringAsFixed(1),
            color: color,
            onSliderChanged: (v) => _onQChanged(_qFromSlider(v)),
            onSliderEnd: (_) => _saveAndApply(),
            onStep: _stepQ,
          ),
        ],
      ),
    );
  }

  // ── Type Segmented Button ──────────────────────────────────────────────────

  Widget _buildTypeSegmented(BandType currentType, Spectral spectral) {
    return SegmentedButton<BandType>(
      segments: const [
        ButtonSegment(value: BandType.peak, label: Text('Peak')),
        ButtonSegment(value: BandType.lowShelf, label: Text('L.Shelf')),
        ButtonSegment(value: BandType.highShelf, label: Text('H.Shelf')),
        ButtonSegment(value: BandType.lowCut, label: Text('L.Cut')),
        ButtonSegment(value: BandType.highCut, label: Text('H.Cut')),
      ],
      selected: {currentType},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) _onTypeChanged(selected.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return spectral.primary.withValues(alpha: 0.25);
          }
          return AfColors.surfaceBase;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return spectral.primary;
          }
          return AfColors.textSecondary;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(color: spectral.primary.withValues(alpha: 0.5));
          }
          return const BorderSide(color: AfColors.surfaceHigh);
        }),
        textStyle: WidgetStateProperty.all(
          AfTypography.caption.copyWith(fontWeight: FontWeight.w500),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(
            horizontal: AfSpacing.s4,
            vertical: AfSpacing.s4,
          ),
        ),
      ),
      showSelectedIcon: false,
    );
  }

  // ── Value Row (label + slider + step buttons + display) ────────────────────

  Widget _buildValueRow({
    required String label,
    required double sliderPos,
    required String displayText,
    required Color color,
    required ValueChanged<double> onSliderChanged,
    required ValueChanged<double> onSliderEnd,
    required void Function(int) onStep,
  }) {
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label, style: AfTypography.bodyMedium)),
        Expanded(
          child: SliderTheme(
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
              value: sliderPos,
              min: 0,
              max: 1,
              onChanged: onSliderChanged,
              onChangeEnd: onSliderEnd,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => onStep(-1),
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              LucideIcons.minus,
              size: 14,
              color: AfColors.textSecondary,
            ),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            displayText,
            textAlign: TextAlign.right,
            style: AfTypography.mono.copyWith(color: color),
          ),
        ),
        GestureDetector(
          onTap: () => onStep(1),
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              LucideIcons.plus,
              size: 14,
              color: AfColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // ── Band Actions (Add + Trash) ────────────────────────────────────────────

  Widget _buildBandActions() {
    return Row(
      children: [
        // Add Band button
        if (_eqState.bands.length < ParametricEqState.maxBands)
          Expanded(
            child: GestureDetector(
              onTap: _addBand,
              child: Container(
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
                      size: AfIconSizes.xs,
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
            ),
          ),

        // Trash button (only if > 1 band)
        if (_eqState.bands.length > 1) ...[
          if (_eqState.bands.length < ParametricEqState.maxBands)
            const SizedBox(width: AfSpacing.s8),
          Expanded(
            child: GestureDetector(
              onTap: () => _removeBand(_selectedBand),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: AfSpacing.s12),
                decoration: BoxDecoration(
                  color: AfColors.surfaceBase,
                  borderRadius: AfRadii.borderSm,
                  border: Border.all(
                    color: AfColors.semanticError.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      LucideIcons.trash2,
                      size: AfIconSizes.xs,
                      color: AfColors.semanticError,
                    ),
                    const SizedBox(width: AfSpacing.s8),
                    Text(
                      'Remove Band',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.semanticError,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showBandPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AfColors.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AfRadii.rLg),
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
                          if (context.canPop()) context.pop();
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
                      key: ValueKey('peq-band-$index'),
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
                        if (context.canPop()) context.pop();
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
}
