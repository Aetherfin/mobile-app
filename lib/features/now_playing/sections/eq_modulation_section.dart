import 'dart:async';

import 'package:flutter/material.dart';

import '../eq_dsp_widgets.dart';

// ── Isolated Slider ──────────────────────────────────────────────────────────

/// Self-contained slider that holds its own value locally.
/// Parent only rebuilds on structural changes (toggle/add/remove), not slider ticks.
class _IsolatedEqSlider extends StatefulWidget {
  const _IsolatedEqSlider({
    required this.label,
    required this.initialValue,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    this.suffix,
    this.precision = 0,
  });

  final String label;
  final double initialValue;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;
  final String? suffix;
  final int precision;

  @override
  State<_IsolatedEqSlider> createState() => _IsolatedEqSliderState();
}

class _IsolatedEqSliderState extends State<_IsolatedEqSlider> {
  late double _value = widget.initialValue;

  @override
  void didUpdateWidget(covariant _IsolatedEqSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _value = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return eqSliderRow(
      widget.label,
      _value,
      widget.min,
      widget.max,
      widget.divisions,
      (v) {
        setState(() => _value = v);
        widget.onChanged(v);
      },
      widget.onChangeEnd,
      suffix: widget.suffix,
      precision: widget.precision,
    );
  }
}

// ── Modulation Section ───────────────────────────────────────────────────────

class EqModulationSection extends StatefulWidget {
  const EqModulationSection({
    super.key,
    required this.phaser,
    required this.phaserInGain,
    required this.phaserOutGain,
    required this.phaserDelay,
    required this.phaserDecay,
    required this.phaserSpeed,
    required this.flanger,
    required this.flangerDelay,
    required this.flangerDepth,
    required this.flangerRegen,
    required this.flangerWidth,
    required this.flangerSpeed,
    required this.chorus,
    required this.chorusInGain,
    required this.chorusOutGain,
    required this.chorusDelays,
    required this.chorusDecays,
    required this.chorusSpeeds,
    required this.chorusDepths,
    required this.tremolo,
    required this.tremoloFreq,
    required this.tremoloDepth,
    required this.vibrato,
    required this.vibratoFreq,
    required this.vibratoDepth,
    required this.onChanged,
    required this.onApply,
  });

  final bool phaser;
  final double phaserInGain;
  final double phaserOutGain;
  final double phaserDelay;
  final double phaserDecay;
  final double phaserSpeed;
  final bool flanger;
  final double flangerDelay;
  final double flangerDepth;
  final double flangerRegen;
  final double flangerWidth;
  final double flangerSpeed;
  final bool chorus;
  final double chorusInGain;
  final double chorusOutGain;
  final String chorusDelays;
  final String chorusDecays;
  final String chorusSpeeds;
  final String chorusDepths;
  final bool tremolo;
  final double tremoloFreq;
  final double tremoloDepth;
  final bool vibrato;
  final double vibratoFreq;
  final double vibratoDepth;
  final void Function(String field, dynamic value) onChanged;
  final Future<void> Function() onApply;

  @override
  State<EqModulationSection> createState() => _EqModulationSectionState();
}

class _EqModulationSectionState extends State<EqModulationSection> {
  late bool _phaser = widget.phaser;
  late bool _flanger = widget.flanger;
  late bool _chorus = widget.chorus;
  late bool _tremolo = widget.tremolo;
  late bool _vibrato = widget.vibrato;

  // ponytail: chorus text fields still need parent state (string values, not sliders)
  late String _chorusDelays = widget.chorusDelays;
  late String _chorusDecays = widget.chorusDecays;
  late String _chorusSpeeds = widget.chorusSpeeds;
  late String _chorusDepths = widget.chorusDepths;

  @override
  void didUpdateWidget(covariant EqModulationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phaser != widget.phaser) _phaser = widget.phaser;
    if (oldWidget.flanger != widget.flanger) _flanger = widget.flanger;
    if (oldWidget.chorus != widget.chorus) _chorus = widget.chorus;
    if (oldWidget.chorusDelays != widget.chorusDelays) {
      _chorusDelays = widget.chorusDelays;
    }
    if (oldWidget.chorusDecays != widget.chorusDecays) {
      _chorusDecays = widget.chorusDecays;
    }
    if (oldWidget.chorusSpeeds != widget.chorusSpeeds) {
      _chorusSpeeds = widget.chorusSpeeds;
    }
    if (oldWidget.chorusDepths != widget.chorusDepths) {
      _chorusDepths = widget.chorusDepths;
    }
    if (oldWidget.tremolo != widget.tremolo) _tremolo = widget.tremolo;
    if (oldWidget.vibrato != widget.vibrato) _vibrato = widget.vibrato;
  }

  void _set(String field, dynamic value) => widget.onChanged(field, value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Phaser ──
        EqEffectToggle(
          title: 'Phaser',
          subtitle: 'Phase-shifting sweep effect',
          value: _phaser,
          onChanged: (v) {
            setState(() => _phaser = v);
            _set('phaser', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _phaser,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IsolatedEqSlider(
                label: 'In gain',
                initialValue: widget.phaserInGain,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) => _set('phaserInGain', v),
                onChangeEnd: widget.onApply,
                precision: 2,
              ),
              _IsolatedEqSlider(
                label: 'Out gain',
                initialValue: widget.phaserOutGain,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) => _set('phaserOutGain', v),
                onChangeEnd: widget.onApply,
                precision: 2,
              ),
              _IsolatedEqSlider(
                label: 'Delay',
                initialValue: widget.phaserDelay,
                min: 0.0,
                max: 5.0,
                divisions: 50,
                onChanged: (v) => _set('phaserDelay', v),
                onChangeEnd: widget.onApply,
                precision: 1,
                suffix: 'ms',
              ),
              _IsolatedEqSlider(
                label: 'Decay',
                initialValue: widget.phaserDecay,
                min: 0.0,
                max: 0.99,
                divisions: 99,
                onChanged: (v) => _set('phaserDecay', v),
                onChangeEnd: widget.onApply,
                precision: 2,
              ),
              _IsolatedEqSlider(
                label: 'Speed',
                initialValue: widget.phaserSpeed,
                min: 0.1,
                max: 2.0,
                divisions: 19,
                onChanged: (v) => _set('phaserSpeed', v),
                onChangeEnd: widget.onApply,
                precision: 2,
                suffix: 'Hz',
              ),
            ],
          ),
        ),
        // ── Flanger ──
        EqEffectToggle(
          title: 'Flanger',
          subtitle: 'Flanging with feedback',
          value: _flanger,
          onChanged: (v) {
            setState(() => _flanger = v);
            _set('flanger', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _flanger,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IsolatedEqSlider(
                label: 'Delay',
                initialValue: widget.flangerDelay,
                min: 0.0,
                max: 30.0,
                divisions: 60,
                onChanged: (v) => _set('flangerDelay', v),
                onChangeEnd: widget.onApply,
                precision: 1,
                suffix: 'ms',
              ),
              _IsolatedEqSlider(
                label: 'Depth',
                initialValue: widget.flangerDepth,
                min: 0.0,
                max: 10.0,
                divisions: 20,
                onChanged: (v) => _set('flangerDepth', v),
                onChangeEnd: widget.onApply,
                precision: 1,
              ),
              _IsolatedEqSlider(
                label: 'Regen',
                initialValue: widget.flangerRegen,
                min: -95.0,
                max: 95.0,
                divisions: 38,
                onChanged: (v) => _set('flangerRegen', v),
                onChangeEnd: widget.onApply,
                precision: 0,
                suffix: '%',
              ),
              _IsolatedEqSlider(
                label: 'Width',
                initialValue: widget.flangerWidth,
                min: 0.0,
                max: 100.0,
                divisions: 20,
                onChanged: (v) => _set('flangerWidth', v),
                onChangeEnd: widget.onApply,
                precision: 0,
                suffix: '%',
              ),
              _IsolatedEqSlider(
                label: 'Speed',
                initialValue: widget.flangerSpeed,
                min: 0.1,
                max: 10.0,
                divisions: 99,
                onChanged: (v) => _set('flangerSpeed', v),
                onChangeEnd: widget.onApply,
                precision: 1,
                suffix: 'Hz',
              ),
            ],
          ),
        ),
        // ── Chorus ──
        EqEffectToggle(
          title: 'Chorus',
          subtitle: 'Multi-voice chorus effect',
          value: _chorus,
          onChanged: (v) {
            setState(() => _chorus = v);
            _set('chorus', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _chorus,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IsolatedEqSlider(
                label: 'In gain',
                initialValue: widget.chorusInGain,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) => _set('chorusInGain', v),
                onChangeEnd: widget.onApply,
                precision: 2,
              ),
              _IsolatedEqSlider(
                label: 'Out gain',
                initialValue: widget.chorusOutGain,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) => _set('chorusOutGain', v),
                onChangeEnd: widget.onApply,
                precision: 2,
              ),
              eqTextFieldRow(
                context,
                'Delays (ms)',
                _chorusDelays,
                'e.g. 40|60',
                (v) {
                  setState(() => _chorusDelays = v);
                  _set('chorusDelays', v);
                  unawaited(widget.onApply());
                },
                numericPipe: true,
              ),
              eqTextFieldRow(
                context,
                'Decays',
                _chorusDecays,
                'e.g. 0.4|0.32',
                (v) {
                  setState(() => _chorusDecays = v);
                  _set('chorusDecays', v);
                  unawaited(widget.onApply());
                },
                numericPipe: true,
              ),
              eqTextFieldRow(
                context,
                'Speeds (Hz)',
                _chorusSpeeds,
                'e.g. 0.25|0.4',
                (v) {
                  setState(() => _chorusSpeeds = v);
                  _set('chorusSpeeds', v);
                  unawaited(widget.onApply());
                },
                numericPipe: true,
              ),
              eqTextFieldRow(context, 'Depths', _chorusDepths, 'e.g. 2|3', (v) {
                setState(() => _chorusDepths = v);
                _set('chorusDepths', v);
                unawaited(widget.onApply());
              }, numericPipe: true),
            ],
          ),
        ),
        // ── Tremolo ──
        EqEffectToggle(
          title: 'Tremolo',
          subtitle: 'Amplitude modulation',
          value: _tremolo,
          onChanged: (v) {
            setState(() => _tremolo = v);
            _set('tremolo', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _tremolo,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IsolatedEqSlider(
                label: 'Frequency',
                initialValue: widget.tremoloFreq,
                min: 0.1,
                max: 20.0,
                divisions: 40,
                onChanged: (v) => _set('tremoloFreq', v),
                onChangeEnd: widget.onApply,
                precision: 1,
                suffix: 'Hz',
              ),
              _IsolatedEqSlider(
                label: 'Depth',
                initialValue: widget.tremoloDepth,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) => _set('tremoloDepth', v),
                onChangeEnd: widget.onApply,
                precision: 2,
              ),
            ],
          ),
        ),
        // ── Vibrato ──
        EqEffectToggle(
          title: 'Vibrato',
          subtitle: 'Pitch modulation',
          value: _vibrato,
          onChanged: (v) {
            setState(() => _vibrato = v);
            _set('vibrato', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _vibrato,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IsolatedEqSlider(
                label: 'Frequency',
                initialValue: widget.vibratoFreq,
                min: 0.1,
                max: 20.0,
                divisions: 40,
                onChanged: (v) => _set('vibratoFreq', v),
                onChangeEnd: widget.onApply,
                precision: 1,
                suffix: 'Hz',
              ),
              _IsolatedEqSlider(
                label: 'Depth',
                initialValue: widget.vibratoDepth,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) => _set('vibratoDepth', v),
                onChangeEnd: widget.onApply,
                precision: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
