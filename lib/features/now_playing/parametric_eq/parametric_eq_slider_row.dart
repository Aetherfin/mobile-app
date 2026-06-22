part of 'parametric_eq_screen.dart';

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
