part of 'parametric_eq_screen.dart';

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
