import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:aetherfin/design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../eq_dsp_widgets.dart';
import '../eq_preset_manager.dart';
import '../parametric_band.dart';
import '../parametric_eq_curve.dart';

// ── Isolated Band Controls ───────────────────────────────────────────────────

/// Per-band controls with local slider state.
/// Only rebuilds itself on slider ticks — parent rebuilds on structural changes.
class _IsolatedBandControls extends StatefulWidget {
  const _IsolatedBandControls({
    super.key,
    required this.index,
    required this.band,
    required this.spectral,
    required this.onFieldChanged,
    required this.onApply,
  });

  final int index;
  final ParametricBand band;
  final Color spectral;
  final void Function(String field, dynamic value) onFieldChanged;
  final Future<void> Function() onApply;

  @override
  State<_IsolatedBandControls> createState() => _IsolatedBandControlsState();
}

class _IsolatedBandControlsState extends State<_IsolatedBandControls> {
  late double _gain = widget.band.gain;
  late double _frequency = widget.band.frequency;
  late double _q = widget.band.q;

  @override
  void didUpdateWidget(covariant _IsolatedBandControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.band.gain != widget.band.gain) _gain = widget.band.gain;
    if (oldWidget.band.frequency != widget.band.frequency) {
      _frequency = widget.band.frequency;
    }
    if (oldWidget.band.q != widget.band.q) _q = widget.band.q;
  }

  void _set(String field, dynamic value) => widget.onFieldChanged(field, value);

  @override
  Widget build(BuildContext context) {
    final i = widget.index;
    return EqExpandableContent(
      visible: widget.band.enabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gain slider
          eqSliderRow(
            'Gain',
            _gain,
            -24.0,
            24.0,
            96,
            (v) {
              setState(() => _gain = v);
              _set('parametricBand${i}Gain', v);
            },
            widget.onApply,
            suffix: 'dB',
            precision: 1,
          ),
          // Frequency slider (logarithmic mapping)
          _LogFrequencySlider(
            frequency: _frequency,
            spectral: widget.spectral,
            onChanged: (v) {
              setState(() => _frequency = v);
              _set('parametricBand${i}Freq', v);
            },
            onChangeEnd: widget.onApply,
          ),
          // Q factor slider
          _QFactorSlider(
            q: _q,
            spectral: widget.spectral,
            onChanged: (v) {
              setState(() => _q = v);
              _set('parametricBand${i}Q', v);
            },
            onChangeEnd: widget.onApply,
          ),
        ],
      ),
    );
  }
}

// ── Parametric Section ───────────────────────────────────────────────────────

/// Parametric EQ section with per-band gain / frequency / Q controls.
class EqParametricSection extends ConsumerStatefulWidget {
  const EqParametricSection({
    super.key,
    required this.enabled,
    required this.bands,
    required this.onChanged,
    required this.onApply,
  });

  final bool enabled;
  final List<ParametricBand> bands;
  final void Function(String field, dynamic value) onChanged;
  final Future<void> Function() onApply;

  @override
  ConsumerState<EqParametricSection> createState() =>
      _EqParametricSectionState();
}

class _EqParametricSectionState extends ConsumerState<EqParametricSection> {
  late bool _enabled = widget.enabled;
  late List<ParametricBand> _bands;
  String? _activePreset;
  Map<String, ParametricPreset> _userPresets = {};

  @override
  void initState() {
    super.initState();
    _bands = widget.bands
        .map(
          (b) => ParametricBand(
            frequency: b.frequency,
            gain: b.gain,
            q: b.q,
            enabled: b.enabled,
          ),
        )
        .toList();
    _loadUserPresets();
  }

  Future<void> _loadUserPresets() async {
    final presets = await EqPresetManager.loadUserParametricPresets();
    if (mounted) setState(() => _userPresets = presets);
  }

  @override
  void didUpdateWidget(covariant EqParametricSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _enabled = widget.enabled;
    if (oldWidget.bands != widget.bands) {
      _bands = widget.bands
          .map(
            (b) => ParametricBand(
              frequency: b.frequency,
              gain: b.gain,
              q: b.q,
              enabled: b.enabled,
            ),
          )
          .toList();
    }
  }

  void _set(String field, dynamic value) {
    widget.onChanged(field, value);
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EqEffectToggle(
          title: 'Parametric Equalizer',
          subtitle: '5-band parametric EQ',
          value: _enabled,
          onChanged: (v) {
            setState(() => _enabled = v);
            _set('parametricEnabled', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _enabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Frequency response curve
              _buildCurveView(spectral),
              const SizedBox(height: AfSpacing.s8),
              // Preset chips
              _buildPresetChips(spectral),
              const SizedBox(height: AfSpacing.s8),
              // Band controls — each band is an isolated widget
              for (var i = 0; i < _bands.length; i++) ...[
                _buildBandHeader(i, spectral),
                _IsolatedBandControls(
                  key: ValueKey('band-ctrl-$i'),
                  index: i,
                  band: _bands[i],
                  spectral: spectral,
                  onFieldChanged: _set,
                  onApply: widget.onApply,
                ),
                if (i < _bands.length - 1) const SizedBox(height: AfSpacing.s8),
              ],
              const SizedBox(height: AfSpacing.s8),
              _buildActionButtons(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBandHeader(int index, Color spectral) {
    final band = _bands[index];
    return Row(
      children: [
        Icon(
          band.enabled ? LucideIcons.circleDot : LucideIcons.circle,
          size: 14,
          color: band.enabled ? spectral : AfColors.textTertiary,
        ),
        const SizedBox(width: AfSpacing.s8),
        Text(
          'Band ${index + 1}',
          style: AfTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          '${_formatFrequency(band.frequency)}  •  ${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB',
          style: AfTypography.mono.copyWith(
            color: band.enabled ? spectral : AfColors.textTertiary,
          ),
        ),
        const SizedBox(width: AfSpacing.s8),
        SizedBox(
          width: 40,
          height: 24,
          child: Switch(
            value: band.enabled,
            onChanged: (v) {
              setState(() {
                _bands[index] = ParametricBand(
                  frequency: band.frequency,
                  gain: band.gain,
                  q: band.q,
                  enabled: v,
                );
              });
              _set('parametricBand${index}Enabled', v);
              unawaited(widget.onApply());
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildCurveView(Color spectral) {
    return SizedBox(
      height: 120,
      child: ParametricEqCurveView(
        bands: _bands,
        accentColor: spectral,
        onBandChanged: (index, band) {
          setState(() => _bands[index] = band);
          _set('parametricBand${index}Freq', band.frequency);
          _set('parametricBand${index}Gain', band.gain);
        },
        onBandSelected: (_) {}, // Selection handled internally by curve view
        onPanEnd: widget.onApply,
      ),
    );
  }

  Widget _buildPresetChips(Color spectral) {
    return EqPresetManager.buildParametricPresetChips(
      activePreset: _activePreset,
      userPresets: _userPresets,
      ref: ref,
      onApply: (name, preset) {
        setState(() {
          _activePreset = name;
          // Copy the bands from the preset
          for (var i = 0; i < _bands.length; i++) {
            if (i < preset.bands.length) {
              final b = preset.bands[i];
              _bands[i] = ParametricBand(
                frequency: b.frequency,
                gain: b.gain,
                q: b.q,
                enabled: b.enabled,
              );
            } else {
              _bands[i] = ParametricBand.defaultAt(i);
            }
          }
        });
        // Sync to parent state
        for (var i = 0; i < _bands.length; i++) {
          _set('parametricBand${i}Freq', _bands[i].frequency);
          _set('parametricBand${i}Gain', _bands[i].gain);
          _set('parametricBand${i}Q', _bands[i].q);
          _set('parametricBand${i}Enabled', _bands[i].enabled);
        }
        _set('parametricEnabled', true);
        unawaited(widget.onApply());
      },
      onDelete: (name) async {
        await EqPresetManager.deleteParametricPreset(name);
        await _loadUserPresets();
        if (_activePreset == name) setState(() => _activePreset = null);
      },
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () {
            setState(() {
              for (var i = 0; i < _bands.length; i++) {
                _bands[i] = ParametricBand.defaultAt(i);
              }
              _activePreset = null;
            });
            for (var i = 0; i < _bands.length; i++) {
              final defaultBand = ParametricBand.defaultAt(i);
              _set('parametricBand${i}Freq', defaultBand.frequency);
              _set('parametricBand${i}Gain', defaultBand.gain);
              _set('parametricBand${i}Q', defaultBand.q);
              _set('parametricBand${i}Enabled', defaultBand.enabled);
            }
            unawaited(widget.onApply());
          },
          icon: const Icon(LucideIcons.rotateCcw, size: 16),
          label: const Text('Reset'),
        ),
        const SizedBox(width: AfSpacing.s8),
        TextButton.icon(
          onPressed: _saveCurrentAsPreset,
          icon: const Icon(LucideIcons.save, size: 16),
          label: const Text('Save preset'),
        ),
      ],
    );
  }

  Future<void> _saveCurrentAsPreset() async {
    final name = await EqPresetManager.showSaveDialog(context);
    if (name == null || name.isEmpty) return;
    final preset = ParametricPreset(
      name: name,
      bands: _bands
          .map(
            (b) => ParametricBand(
              frequency: b.frequency,
              gain: b.gain,
              q: b.q,
              enabled: b.enabled,
            ),
          )
          .toList(),
    );
    await EqPresetManager.saveParametricPreset(name, preset);
    await _loadUserPresets();
    setState(() => _activePreset = name);
  }

  String _formatFrequency(double freq) {
    if (freq >= 1000) {
      return '${(freq / 1000).toStringAsFixed(freq % 1000 == 0 ? 0 : 1)}kHz';
    }
    return '${freq.toStringAsFixed(0)}Hz';
  }
}

/// Frequency slider with logarithmic mapping.
class _LogFrequencySlider extends StatelessWidget {
  const _LogFrequencySlider({
    required this.frequency,
    required this.spectral,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double frequency;
  final Color spectral;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 72,
              child: Text('Freq', style: AfTypography.bodyMedium),
            ),
            const Spacer(),
            Text(
              '${frequency.toStringAsFixed(0)} Hz',
              style: AfTypography.mono.copyWith(color: spectral),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: _frequencyToPosition(frequency),
            min: 0,
            max: 1,
            divisions: 1000,
            activeColor: spectral,
            onChanged: (pos) => onChanged(_positionToFrequency(pos)),
            onChangeEnd: (_) => onChangeEnd(),
          ),
        ),
      ],
    );
  }

  /// Map frequency (20–20000) to slider position (0–1) using log scale.
  static double _frequencyToPosition(double freq) {
    return (log(freq / 20) / log(1000)).clamp(0.0, 1.0);
  }

  /// Map slider position (0–1) to frequency (20–20000) using log scale.
  static double _positionToFrequency(double pos) {
    return (20 * pow(1000, pos)).clamp(20.0, 20000.0).toDouble();
  }
}

/// Q factor slider with descriptive label.
class _QFactorSlider extends StatelessWidget {
  const _QFactorSlider({
    required this.q,
    required this.spectral,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double q;
  final Color spectral;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  String get _qLabel {
    if (q < 0.8) return 'Wide';
    if (q < 1.5) return 'Standard';
    if (q < 4.0) return 'Medium';
    if (q < 8.0) return 'Narrow';
    return 'Very Narrow';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 72,
              child: Text('Q', style: AfTypography.bodyMedium),
            ),
            const Spacer(),
            Text(
              '${q.toStringAsFixed(1)}  $_qLabel',
              style: AfTypography.mono.copyWith(color: spectral),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: q.clamp(0.3, 12.0),
            min: 0.3,
            max: 12.0,
            divisions: 117,
            activeColor: spectral,
            onChanged: onChanged,
            onChangeEnd: (_) => onChangeEnd(),
          ),
        ),
      ],
    );
  }
}
