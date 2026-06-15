import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../utils/log.dart';
import '../../../widgets/af_dialog.dart';
import '../eq_dsp_widgets.dart';
import '../eq_preset.dart';
import '../eq_preset_manager.dart';
import '../graphic_eq_state.dart';

/// Standalone 18-band graphic EQ screen.
///
/// FabFilter-style dark UI with vertical band sliders, preset chips,
/// and real-time audio effect application via [GraphicEqState].
class GraphicEqScreen extends ConsumerStatefulWidget {
  const GraphicEqScreen({super.key});

  @override
  ConsumerState<GraphicEqScreen> createState() => _GraphicEqScreenState();
}

class _GraphicEqScreenState extends ConsumerState<GraphicEqScreen> {
  GraphicEqState _state = GraphicEqState();
  String? _activePreset;
  Map<String, EqPreset> _userPresets = {};
  bool _loaded = false;

  /// Ordered band keys matching [GraphicEqState.levels] indices.
  static const _bandKeys = [
    '1b',
    '2b',
    '3b',
    '4b',
    '5b',
    '6b',
    '7b',
    '8b',
    '9b',
    '10b',
    '11b',
    '12b',
    '13b',
    '14b',
    '15b',
    '16b',
    '17b',
    '18b',
  ];

  @override
  void initState() {
    super.initState();
    _loadState();
    _loadPresets();
  }

  Future<void> _loadState() async {
    try {
      // Load graphic EQ from the unified audio effects key
      final svc = ref.read(playerServiceProvider);
      final current = svc.audioEffects;
      final state = GraphicEqState.fromAudioEffects(current);
      if (mounted) {
        setState(() {
          _state = state;
          _loaded = true;
        });
      }
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Graphic EQ state load failed',
        error: e,
        stackTrace: stack,
      );
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _loadPresets() async {
    final presets = await EqPresetManager.loadUserPresets();
    if (mounted) setState(() => _userPresets = presets);
  }

  // ── Apply / Save ─────────────────────────────────────────────────────

  Future<void> _apply() async {
    final svc = ref.read(playerServiceProvider);
    try {
      await svc.updateAudioEffects((current) {
        return _state.toAudioEffects(current);
      });
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Graphic EQ apply audio effects failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> _save() async {
    final svc = ref.read(playerServiceProvider);
    final current = svc.audioEffects;
    final merged = _state.toAudioEffects(current);
    await svc.updateAudioEffects((_) => merged);
    await PlayerSettingsStore.saveAudioEffects(merged);
  }

  // ── Handlers ─────────────────────────────────────────────────────────

  void _onEnabledChanged(bool enabled) {
    setState(() {
      _state = GraphicEqState(
        levels: List<double>.from(_state.levels),
        enabled: enabled,
      );
    });
    unawaited(_apply());
    unawaited(_save());
  }

  void _onBandChanged(int index, double value) {
    setState(() {
      _state.levels[index] = value;
      _activePreset = null;
    });
    unawaited(_apply());
    unawaited(_save());
  }

  void _resetAll() {
    showBlurDialog<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset Graphic EQ?', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text(
            'This will flatten all 18 bands to 0 dB.',
            style: AfTypography.bodyMedium,
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              Focus(
                autofocus: true,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
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
      _state = GraphicEqState(
        levels: List<double>.filled(18, 0.0),
        enabled: _state.enabled,
      );
      _activePreset = null;
    });
    unawaited(_apply());
    unawaited(_save());
  }

  void _applyPreset(String name, EqPreset preset) {
    final levels = List<double>.filled(18, 0.0);
    for (var i = 0; i < 18; i++) {
      final gain = preset.bands[_bandKeys[i]];
      if (gain != null) levels[i] = gain - 0.5;
    }
    setState(() {
      _state = GraphicEqState(levels: levels, enabled: true);
      _activePreset = name;
    });
    unawaited(_apply());
    unawaited(_save());
  }

  void _deletePreset(String name) {
    EqPresetManager.showDeleteDialog(
      context: context,
      name: name,
      onConfirm: () async {
        await EqPresetManager.deletePreset(name);
        if (mounted) {
          setState(() {
            _userPresets.remove(name);
            if (_activePreset == name) _activePreset = null;
          });
        }
      },
    );
  }

  // ── Color helpers ────────────────────────────────────────────────────

  /// Band bar color: blue for cut, neutral for flat, spectral for boost.
  Color _bandColor(double level, Spectral spectral) {
    if (level.abs() < 0.5) return AfColors.surfaceHigh;
    final t = (level.abs() / 12.0).clamp(0.0, 1.0);
    if (level < 0) {
      return Color.lerp(AfColors.surfaceHigh, AfColors.accentPrimary, t)!;
    }
    return Color.lerp(AfColors.surfaceHigh, spectral.primary, t)!;
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        title: const Text('Graphic EQ'),
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
      body: _loaded
          ? SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
                vertical: AfSpacing.s8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Enable toggle ──
                  EqEffectToggle(
                    title: 'Graphic EQ',
                    subtitle: _state.enabled
                        ? '18-band equalizer active'
                        : 'Bypassed — no EQ applied',
                    value: _state.enabled,
                    onChanged: _onEnabledChanged,
                  ),
                  const SizedBox(height: AfSpacing.s16),

                  // ── Preset chips ──
                  EqPresetManager.buildPresetChips(
                    activePreset: _activePreset,
                    userPresets: _userPresets,
                    ref: ref,
                    onApply: _applyPreset,
                    onDelete: _deletePreset,
                  ),
                  const SizedBox(height: AfSpacing.s24),

                  // ── Frequency response visualization ──
                  _buildVisualization(spectral),
                  const SizedBox(height: AfSpacing.s24),

                  // ── 18-band vertical sliders ──
                  Opacity(
                    opacity: _state.enabled ? 1.0 : 0.4,
                    child: AbsorbPointer(
                      absorbing: !_state.enabled,
                      child: SizedBox(
                        height: 260,
                        child: _buildBandSliders(spectral),
                      ),
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s32),
                ],
              ),
            )
          : const Center(
              child: CircularProgressIndicator(color: AfColors.accentPrimary),
            ),
    );
  }

  // ── Visualization ────────────────────────────────────────────────────

  Widget _buildVisualization(Spectral spectral) {
    return Material(
      color: AfColors.surfaceBase,
      borderRadius: AfRadii.borderLg,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AfSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FREQUENCY RESPONSE',
              style: AfTypography.label.copyWith(color: AfColors.textTertiary),
            ),
            const SizedBox(height: AfSpacing.s12),
            SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(18, (i) {
                  final level = _state.levels[i];
                  final barH = 4.0 + ((level + 12) / 24) * 76.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: AnimatedContainer(
                        duration: AfDurations.quick,
                        curve: AfCurves.easeStandard,
                        height: barH,
                        decoration: BoxDecoration(
                          color: _bandColor(level, spectral),
                          borderRadius: AfRadii.borderXs,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Band Sliders ─────────────────────────────────────────────────────

  Widget _buildBandSliders(Spectral spectral) {
    final freqLabels = kEqBands.values.toList();
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      itemCount: 18,
      itemBuilder: (context, i) {
        return SizedBox(
          width: 44,
          child: _BandSlider(
            freq: freqLabels[i],
            value: _state.levels[i],
            activeColor: _bandColor(_state.levels[i], spectral),
            onChanged: (v) => _onBandChanged(i, v),
            onChangeEnd: () {},
          ),
        );
      },
    );
  }
}

// ─── Custom Vertical Band Slider ───────────────────────────────────────────

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.freq,
    required this.value,
    required this.activeColor,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String freq;
  final double value;
  final Color activeColor;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  static const _min = -12.0;
  static const _max = 12.0;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    final dbLabel = _formatDb(value);

    return Semantics(
      label: 'Frequency band $freq, gain $dbLabel',
      value: value.abs() < 0.5 ? 'flat' : (value > 0 ? 'boost' : 'cut'),
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final height = box.size.height;
          final delta = -details.delta.dy / height * (_max - _min);
          onChanged((value + delta).clamp(_min, _max));
        },
        onVerticalDragEnd: (_) => onChangeEnd(),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              const step = 1.0;
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                onChanged((value + step).clamp(_min, _max));
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                onChanged((value - step).clamp(_min, _max));
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s4),
            child: Column(
          children: [
            // ── dB value ──
            Text(
              _formatDb(value),
              style: AfTypography.overline.copyWith(
                color: value.abs() < 0.5 ? AfColors.textTertiary : activeColor,
              ),
            ),
            const SizedBox(height: AfSpacing.s2),

            // ── Slider track ──
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  final w = constraints.maxWidth;
                  final t = ((value - _min) / (_max - _min)).clamp(0.0, 1.0);
                  final thumbY = h * (1 - t);
                  final centerY = h * 0.5;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Track background
                      Positioned(
                        left: w / 2 - 1.5,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 3,
                          decoration: const BoxDecoration(
                            color: AfColors.surfaceHigh,
                            borderRadius: AfRadii.borderPill,
                          ),
                        ),
                      ),
                      // Center marker (0 dB line)
                      Positioned(
                        left: w / 2 - 5,
                        top: centerY - 0.5,
                        child: Container(
                          width: 10,
                          height: 1,
                          color: AfColors.surfaceMax,
                        ),
                      ),
                      // Fill bar from center to value
                      if (value.abs() > 0.5)
                        Positioned(
                          left: w / 2 - 1.5,
                          top: thumbY < centerY ? thumbY : centerY,
                          child: AnimatedContainer(
                            duration: reduced
                                ? Duration.zero
                                : AfDurations.quick,
                            curve: AfCurves.easeStandard,
                            width: 3,
                            height: (thumbY - centerY).abs().clamp(
                              0.0,
                              h * 0.5,
                            ),
                            decoration: BoxDecoration(
                              color: activeColor,
                              borderRadius: AfRadii.borderPill,
                            ),
                          ),
                        ),
                      // Thumb circle
                      Positioned(
                        left: w / 2 - 6,
                        top: thumbY - 6,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: activeColor,
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AfSpacing.s2),

            // ── Frequency label ──
            Text(
              freq,
              style: AfTypography.overline.copyWith(
                color: AfColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  String _formatDb(double v) {
    if (v >= 0) return '+${v.toStringAsFixed(0)}';
    return v.toStringAsFixed(0);
  }
}
