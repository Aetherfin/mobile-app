import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show AudioEffects;

import '../../core/audio/player_settings_store.dart';
import '../../design_tokens/tokens.dart';
import '../../utils/display_error.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/press_scale.dart';
import '../../state/providers.dart';
import 'eq_band_logic.dart';
import 'eq_dsp_sections.dart';
import 'eq_dsp_widgets.dart';
import 'eq_preset_manager.dart';

class EqDspScreen extends ConsumerStatefulWidget {
  const EqDspScreen({super.key});

  @override
  ConsumerState<EqDspScreen> createState() => _EqDspScreenState();
}

class _EqDspScreenState extends ConsumerState<EqDspScreen> {
  final EqDspState _s = EqDspState();
  int? _openSection;
  final ScrollAbsorbController _scrollCtrl = ScrollAbsorbController();
  String? _activePreset;
  Map<String, EqPreset> _userPresets = {};

  @override
  void initState() {
    super.initState();
    _loadFxState();
    _loadMasterState();
    _loadPresets();
  }

  void _loadFxState() {
    final fx = ref.read(playerServiceProvider).audioEffects;
    _s.loadFromAudioEffects(fx);
  }

  Future<void> _loadMasterState() async {
    final enabled = await PlayerSettingsStore.loadDspMasterEnabled();
    if (mounted && enabled != _s.masterEnabled) {
      setState(() => _s.masterEnabled = enabled);
    }
  }

  Future<void> _loadPresets() async {
    final presets = await EqPresetManager.loadUserPresets();
    if (mounted) {
      setState(() => _userPresets = presets);
    }
  }

  // ── Apply / Reset ────────────────────────────────────────────────────────

  Future<void> _apply() async {
    if (!_s.masterEnabled) return;
    final svc = ref.read(playerServiceProvider);
    try {
      await Future.wait([
        svc.updateBass((b) => b.copyWith(enabled: _s.bass != 0, g: _s.bass)),
        svc.updateTreble(
          (t) => t.copyWith(enabled: _s.treble != 0, g: _s.treble),
        ),
        svc.updateLoudnorm((ln) => ln.copyWith(enabled: _s.loudnorm)),
        svc.updateAcompressor(
          (c) => c.copyWith(
            enabled: _s.compressor,
            threshold: _s.compThreshold,
            ratio: _s.compRatio,
            attack: _s.compAttack,
            release: _s.compRelease,
          ),
        ),
        svc.updateRubberband(
          (r) => r.copyWith(
            enabled: _s.rubberbandEnabled,
            pitch: _s.pitch,
            tempo: _s.tempo,
          ),
        ),
        svc.updateCrossfeed(
          (c) =>
              c.copyWith(enabled: _s.crossfeed, strength: _s.crossfeedStrength),
        ),
        svc.updateStereowiden(
          (sw) =>
              sw.copyWith(enabled: _s.stereoWiden, delay: _s.stereoWidenDelay),
        ),
        svc.updateAexciter(
          (e) => e.copyWith(enabled: _s.exciter, amount: _s.exciterAmount),
        ),
        svc.updateCrystalizer(
          (c) =>
              c.copyWith(enabled: _s.crystalizer, i: _s.crystalizerIntensity),
        ),
        svc.updateVirtualbass(
          (v) =>
              v.copyWith(enabled: _s.virtualBass, cutoff: _s.virtualBassCutoff),
        ),
        svc.updateAgate(
          (g) => g.copyWith(
            enabled: _s.gate,
            threshold: _s.gateThreshold,
            ratio: _s.gateRatio,
            attack: _s.gateAttack,
            release: _s.gateRelease,
          ),
        ),
        svc.updateDeesser(
          (d) => d.copyWith(
            enabled: _s.deesser,
            i: _s.deesserIntensity,
            m: _s.deesserMix,
            f: _s.deesserFreq,
          ),
        ),
        svc.updateAecho(
          (e) => e.copyWith(
            enabled: _s.echoEnabled,
            in_gain: _s.echoInGain,
            out_gain: _s.echoOutGain,
            delays: _s.echoDelays,
            decays: _s.echoDecays,
          ),
        ),
        svc.updateAphaser(
          (p) => p.copyWith(
            enabled: _s.phaser,
            in_gain: _s.phaserInGain,
            out_gain: _s.phaserOutGain,
            delay: _s.phaserDelay,
            decay: _s.phaserDecay,
            speed: _s.phaserSpeed,
          ),
        ),
        svc.updateFlanger(
          (f) => f.copyWith(
            enabled: _s.flanger,
            delay: _s.flangerDelay,
            depth: _s.flangerDepth,
            regen: _s.flangerRegen,
            width: _s.flangerWidth,
            speed: _s.flangerSpeed,
          ),
        ),
        svc.updateChorus(
          (c) => c.copyWith(
            enabled: _s.chorus,
            in_gain: _s.chorusInGain,
            out_gain: _s.chorusOutGain,
            delays: _s.chorusDelays,
            decays: _s.chorusDecays,
            speeds: _s.chorusSpeeds,
            depths: _s.chorusDepths,
          ),
        ),
        svc.updateTremolo(
          (t) => t.copyWith(
            enabled: _s.tremolo,
            f: _s.tremoloFreq,
            d: _s.tremoloDepth,
          ),
        ),
        svc.updateVibrato(
          (v) => v.copyWith(
            enabled: _s.vibrato,
            f: _s.vibratoFreq,
            d: _s.vibratoDepth,
          ),
        ),
        svc.updateAcrusher(
          (c) => c.copyWith(
            enabled: _s.crusher,
            bits: _s.crusherBits,
            mix: _s.crusherMix,
            samples: _s.crusherSamples,
          ),
        ),
      ]);
      await PlayerSettingsStore.saveAudioEffects(svc.audioEffects);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Failed to apply'))),
        );
      }
    }
  }

  void _resetAll() {
    showBlurDialog<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset all effects?', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text(
            'This will restore all DSP settings to their defaults.',
            style: AfTypography.bodyMedium,
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  if (context.canPop()) context.pop();
                },
                child: const Text('Cancel'),
              ),
              Focus(
                autofocus: true,
                child: TextButton(
                  onPressed: () {
                    if (context.canPop()) context.pop();
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
      _s.reset();
      _openSection = null;
      _activePreset = null;
    });
    unawaited(
      ref.read(playerServiceProvider).setAudioEffects(const AudioEffects()),
    );
    unawaited(PlayerSettingsStore.saveAudioEffects(const AudioEffects()));
    unawaited(EqPresetManager.saveActivePreset(null));
  }

  void _applyPreset(String name, EqPreset preset) {
    setState(() {
      _activePreset = name;
      EqPresetManager.applyPresetToState(_s, preset);
    });
    unawaited(_apply());
    unawaited(EqPresetManager.saveActivePreset(name));
  }

  Future<void> _deletePreset(String name) async {
    await EqPresetManager.deletePreset(name);
    setState(() {
      _userPresets.remove(name);
      if (_activePreset == name) _activePreset = null;
    });
  }

  // ── Field change callback ────────────────────────────────────────────────

  void _onFieldChanged(String field, dynamic value) {
    _s.setField(field, value);
    _activePreset = null;
  }

  // ── Master toggle handler ────────────────────────────────────────────────

  void _onMasterChanged(bool v) {
    setState(() => _s.masterEnabled = v);
    unawaited(PlayerSettingsStore.saveDspMasterEnabled(v));
    if (v) {
      unawaited(_apply());
    } else {
      final svc = ref.read(playerServiceProvider);
      unawaited(svc.setAudioEffects(const AudioEffects()));
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        title: const Text('Equalizer & DSP'),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: _resetAll,
            child: Text(
              'Reset all',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.semanticError,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ScrollAbsorbNotification(
            controller: _scrollCtrl,
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
                vertical: AfSpacing.s8,
              ),
              children: [
                EqMasterBanner(
                  enabled: _s.masterEnabled,
                  onChanged: _onMasterChanged,
                ),
                const SizedBox(height: AfSpacing.s12),
                eqSectionLabel('EQ Presets'),
                eqCard([
                  EqPresetManager.buildPresetChips(
                    activePreset: _activePreset,
                    userPresets: _userPresets,
                    ref: ref,
                    onApply: _applyPreset,
                    onDelete: (name) => EqPresetManager.showDeleteDialog(
                      context: context,
                      name: name,
                      onConfirm: () => _deletePreset(name),
                    ),
                  ),
                ]),
                const SizedBox(height: AfSpacing.s16),
                // ── EQ navigation cards ─────────────────────────────────────
                _buildNavigationCard(
                  context: context,
                  title: 'Graphic EQ',
                  subtitle: '18-band',
                  icon: LucideIcons.slidersHorizontal,
                  onTap: () => context.push('/graphic-eq'),
                ),
                const SizedBox(height: AfSpacing.s8),
                _buildNavigationCard(
                  context: context,
                  title: 'Parametric EQ',
                  subtitle: '18-band',
                  icon: LucideIcons.activity,
                  onTap: () => context.push('/parametric-eq'),
                ),
                const SizedBox(height: AfSpacing.s16),
                ..._buildAccordionSections(),
                const SizedBox(height: AfSpacing.s24),
              ],
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _scrollCtrl,
            builder: (_, active, _) => active
                ? const Positioned.fill(
                    child: AbsorbPointer(child: SizedBox.expand()),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ── Accordion Sections ──────────────────────────────────────────────────

  List<Widget> _buildAccordionSections() {
    final sections = [
      _buildAccordion(
        0,
        'Tone',
        null,
        EqToneSection(
          bass: _s.bass,
          treble: _s.treble,
          onBassChanged: (v) => setState(() {
            _s.bass = v;
            _activePreset = null;
          }),
          onTrebleChanged: (v) => setState(() {
            _s.treble = v;
            _activePreset = null;
          }),
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        1,
        'Dynamics',
        _s.dynamicsCount > 0 ? _s.dynamicsCount : null,
        EqDynamicsSection(
          loudnorm: _s.loudnorm,
          compressor: _s.compressor,
          compThreshold: _s.compThreshold,
          compRatio: _s.compRatio,
          compAttack: _s.compAttack,
          compRelease: _s.compRelease,
          gate: _s.gate,
          gateThreshold: _s.gateThreshold,
          gateRatio: _s.gateRatio,
          gateAttack: _s.gateAttack,
          gateRelease: _s.gateRelease,
          deesser: _s.deesser,
          deesserIntensity: _s.deesserIntensity,
          deesserMix: _s.deesserMix,
          deesserFreq: _s.deesserFreq,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        4,
        'Echo / Delay',
        _s.echoEnabled ? 1 : null,
        EqEchoSection(
          echoEnabled: _s.echoEnabled,
          echoInGain: _s.echoInGain,
          echoOutGain: _s.echoOutGain,
          echoDelays: _s.echoDelays,
          echoDecays: _s.echoDecays,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        5,
        'Pitch & Tempo',
        _s.rubberbandEnabled ? 1 : null,
        EqPitchSection(
          rubberbandEnabled: _s.rubberbandEnabled,
          pitch: _s.pitch,
          tempo: _s.tempo,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        6,
        'Spatial',
        (_s.crossfeed || _s.stereoWiden) ? 1 : null,
        EqSpatialSection(
          crossfeed: _s.crossfeed,
          crossfeedStrength: _s.crossfeedStrength,
          stereoWiden: _s.stereoWiden,
          stereoWidenDelay: _s.stereoWidenDelay,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        7,
        'Modulation',
        _s.modulationCount > 0 ? _s.modulationCount : null,
        EqModulationSection(
          phaser: _s.phaser,
          phaserInGain: _s.phaserInGain,
          phaserOutGain: _s.phaserOutGain,
          phaserDelay: _s.phaserDelay,
          phaserDecay: _s.phaserDecay,
          phaserSpeed: _s.phaserSpeed,
          flanger: _s.flanger,
          flangerDelay: _s.flangerDelay,
          flangerDepth: _s.flangerDepth,
          flangerRegen: _s.flangerRegen,
          flangerWidth: _s.flangerWidth,
          flangerSpeed: _s.flangerSpeed,
          chorus: _s.chorus,
          chorusInGain: _s.chorusInGain,
          chorusOutGain: _s.chorusOutGain,
          chorusDelays: _s.chorusDelays,
          chorusDecays: _s.chorusDecays,
          chorusSpeeds: _s.chorusSpeeds,
          chorusDepths: _s.chorusDepths,
          tremolo: _s.tremolo,
          tremoloFreq: _s.tremoloFreq,
          tremoloDepth: _s.tremoloDepth,
          vibrato: _s.vibrato,
          vibratoFreq: _s.vibratoFreq,
          vibratoDepth: _s.vibratoDepth,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        8,
        'Creative',
        _s.creativeCount > 0 ? _s.creativeCount : null,
        EqCreativeSection(
          exciter: _s.exciter,
          exciterAmount: _s.exciterAmount,
          crystalizer: _s.crystalizer,
          crystalizerIntensity: _s.crystalizerIntensity,
          virtualBass: _s.virtualBass,
          virtualBassCutoff: _s.virtualBassCutoff,
          crusher: _s.crusher,
          crusherBits: _s.crusherBits,
          crusherMix: _s.crusherMix,
          crusherSamples: _s.crusherSamples,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
    ];

    return sections
        .map(
          (child) => RepaintBoundary(
            child: Opacity(
              opacity: _s.masterEnabled ? 1.0 : 0.4,
              child: AbsorbPointer(absorbing: !_s.masterEnabled, child: child),
            ),
          ),
        )
        .toList();
  }

  Widget _buildAccordion(int index, String label, int? badge, Widget content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s12),
      child: EqAccordionSection(
        label: label,
        isOpen: _openSection == index,
        badgeCount: badge,
        onTap: () => setState(() {
          _openSection = _openSection == index ? null : index;
        }),
        child: content,
      ),
    );
  }

  // ── Navigation card helper ──────────────────────────────────────────────

  Widget _buildNavigationCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: PressScale(
        onTap: onTap,
        child: InkWell(
          borderRadius: AfRadii.borderSm,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s12,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AfColors.accentPrimary.withValues(alpha: 0.15),
                  AfColors.accentPrimary.withValues(alpha: 0.05),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: AfRadii.borderSm,
              border: Border.all(
                color: AfColors.accentPrimary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: AfIconSizes.sm, color: AfColors.accentPrimary),
                const SizedBox(width: AfSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AfTypography.titleSmall.copyWith(
                          color: AfColors.accentPrimary,
                        ),
                      ),
                      const SizedBox(height: AfSpacing.s2),
                      Text(
                        subtitle,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: AfIconSizes.xs,
                  color: AfColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
