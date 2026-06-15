import 'dart:async';

import 'package:flutter/material.dart';

import '../eq_dsp_widgets.dart';

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
  late double _phaserInGain = widget.phaserInGain;
  late double _phaserOutGain = widget.phaserOutGain;
  late double _phaserDelay = widget.phaserDelay;
  late double _phaserDecay = widget.phaserDecay;
  late double _phaserSpeed = widget.phaserSpeed;
  late bool _flanger = widget.flanger;
  late double _flangerDelay = widget.flangerDelay;
  late double _flangerDepth = widget.flangerDepth;
  late double _flangerRegen = widget.flangerRegen;
  late double _flangerWidth = widget.flangerWidth;
  late double _flangerSpeed = widget.flangerSpeed;
  late bool _chorus = widget.chorus;
  late double _chorusInGain = widget.chorusInGain;
  late double _chorusOutGain = widget.chorusOutGain;
  late String _chorusDelays = widget.chorusDelays;
  late String _chorusDecays = widget.chorusDecays;
  late String _chorusSpeeds = widget.chorusSpeeds;
  late String _chorusDepths = widget.chorusDepths;
  late bool _tremolo = widget.tremolo;
  late double _tremoloFreq = widget.tremoloFreq;
  late double _tremoloDepth = widget.tremoloDepth;
  late bool _vibrato = widget.vibrato;
  late double _vibratoFreq = widget.vibratoFreq;
  late double _vibratoDepth = widget.vibratoDepth;

  @override
  void didUpdateWidget(covariant EqModulationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phaser != widget.phaser) _phaser = widget.phaser;
    if (oldWidget.phaserInGain != widget.phaserInGain) {
      _phaserInGain = widget.phaserInGain;
    }
    if (oldWidget.phaserOutGain != widget.phaserOutGain) {
      _phaserOutGain = widget.phaserOutGain;
    }
    if (oldWidget.phaserDelay != widget.phaserDelay) {
      _phaserDelay = widget.phaserDelay;
    }
    if (oldWidget.phaserDecay != widget.phaserDecay) {
      _phaserDecay = widget.phaserDecay;
    }
    if (oldWidget.phaserSpeed != widget.phaserSpeed) {
      _phaserSpeed = widget.phaserSpeed;
    }
    if (oldWidget.flanger != widget.flanger) _flanger = widget.flanger;
    if (oldWidget.flangerDelay != widget.flangerDelay) {
      _flangerDelay = widget.flangerDelay;
    }
    if (oldWidget.flangerDepth != widget.flangerDepth) {
      _flangerDepth = widget.flangerDepth;
    }
    if (oldWidget.flangerRegen != widget.flangerRegen) {
      _flangerRegen = widget.flangerRegen;
    }
    if (oldWidget.flangerWidth != widget.flangerWidth) {
      _flangerWidth = widget.flangerWidth;
    }
    if (oldWidget.flangerSpeed != widget.flangerSpeed) {
      _flangerSpeed = widget.flangerSpeed;
    }
    if (oldWidget.chorus != widget.chorus) _chorus = widget.chorus;
    if (oldWidget.chorusInGain != widget.chorusInGain) {
      _chorusInGain = widget.chorusInGain;
    }
    if (oldWidget.chorusOutGain != widget.chorusOutGain) {
      _chorusOutGain = widget.chorusOutGain;
    }
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
    if (oldWidget.tremoloFreq != widget.tremoloFreq) {
      _tremoloFreq = widget.tremoloFreq;
    }
    if (oldWidget.tremoloDepth != widget.tremoloDepth) {
      _tremoloDepth = widget.tremoloDepth;
    }
    if (oldWidget.vibrato != widget.vibrato) _vibrato = widget.vibrato;
    if (oldWidget.vibratoFreq != widget.vibratoFreq) {
      _vibratoFreq = widget.vibratoFreq;
    }
    if (oldWidget.vibratoDepth != widget.vibratoDepth) {
      _vibratoDepth = widget.vibratoDepth;
    }
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
              eqSliderRow(
                'In gain',
                _phaserInGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _phaserInGain = v);
                  _set('phaserInGain', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Out gain',
                _phaserOutGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _phaserOutGain = v);
                  _set('phaserOutGain', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Delay',
                _phaserDelay,
                0.0,
                5.0,
                50,
                (v) {
                  setState(() => _phaserDelay = v);
                  _set('phaserDelay', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'ms',
              ),
              eqSliderRow(
                'Decay',
                _phaserDecay,
                0.0,
                0.99,
                99,
                (v) {
                  setState(() => _phaserDecay = v);
                  _set('phaserDecay', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Speed',
                _phaserSpeed,
                0.1,
                2.0,
                19,
                (v) {
                  setState(() => _phaserSpeed = v);
                  _set('phaserSpeed', v);
                },
                widget.onApply,
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
              eqSliderRow(
                'Delay',
                _flangerDelay,
                0.0,
                30.0,
                60,
                (v) {
                  setState(() => _flangerDelay = v);
                  _set('flangerDelay', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'ms',
              ),
              eqSliderRow(
                'Depth',
                _flangerDepth,
                0.0,
                10.0,
                20,
                (v) {
                  setState(() => _flangerDepth = v);
                  _set('flangerDepth', v);
                },
                widget.onApply,
                precision: 1,
              ),
              eqSliderRow(
                'Regen',
                _flangerRegen,
                -95.0,
                95.0,
                38,
                (v) {
                  setState(() => _flangerRegen = v);
                  _set('flangerRegen', v);
                },
                widget.onApply,
                precision: 0,
                suffix: '%',
              ),
              eqSliderRow(
                'Width',
                _flangerWidth,
                0.0,
                100.0,
                20,
                (v) {
                  setState(() => _flangerWidth = v);
                  _set('flangerWidth', v);
                },
                widget.onApply,
                precision: 0,
                suffix: '%',
              ),
              eqSliderRow(
                'Speed',
                _flangerSpeed,
                0.1,
                10.0,
                99,
                (v) {
                  setState(() => _flangerSpeed = v);
                  _set('flangerSpeed', v);
                },
                widget.onApply,
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
              eqSliderRow(
                'In gain',
                _chorusInGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _chorusInGain = v);
                  _set('chorusInGain', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Out gain',
                _chorusOutGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _chorusOutGain = v);
                  _set('chorusOutGain', v);
                },
                widget.onApply,
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
              eqTextFieldRow(
                context,
                'Depths',
                _chorusDepths,
                'e.g. 2|3',
                (v) {
                  setState(() => _chorusDepths = v);
                  _set('chorusDepths', v);
                  unawaited(widget.onApply());
                },
                numericPipe: true,
              ),
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
              eqSliderRow(
                'Frequency',
                _tremoloFreq,
                0.1,
                20.0,
                40,
                (v) {
                  setState(() => _tremoloFreq = v);
                  _set('tremoloFreq', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'Hz',
              ),
              eqSliderRow(
                'Depth',
                _tremoloDepth,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _tremoloDepth = v);
                  _set('tremoloDepth', v);
                },
                widget.onApply,
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
              eqSliderRow(
                'Frequency',
                _vibratoFreq,
                0.1,
                20.0,
                40,
                (v) {
                  setState(() => _vibratoFreq = v);
                  _set('vibratoFreq', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'Hz',
              ),
              eqSliderRow(
                'Depth',
                _vibratoDepth,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _vibratoDepth = v);
                  _set('vibratoDepth', v);
                },
                widget.onApply,
                precision: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
