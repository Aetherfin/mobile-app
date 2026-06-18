import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherfin/core/audio/player_settings_store.dart';
import 'package:aetherfin/core/audio/models/graphic_eq_state.dart';
import 'package:aetherfin/core/audio/models/parametric_eq_state.dart';

void main() {
  group('C2: Unified persistence', () {
    // ── Migration from split keys ──────────────────────────────────────────
    group('migrateSplitKeys', () {
      test('reconstructs combined state from split keys', () async {
        // Set up split keys as if user had saved on each sub-screen
        final graphicEq = GraphicEqState(
          levels: List.generate(18, (i) => i * 0.5),
          enabled: true,
        );
        final parametricEq = ParametricEqState();
        parametricEq.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 5.0,
            q: 2.0,
            type: BandType.peak,
            enabled: true,
          ),
        );
        const dspFx = AudioEffects(
          bass: BassSettings(enabled: true, g: 5.0),
          loudnorm: LoudnormSettings(enabled: true),
        );

        SharedPreferences.setMockInitialValues({
          'af.dsp_state_json': jsonEncode(
            PlayerSettingsStore.testSerializeAudioEffects(dspFx),
          ),
          'af.graphic_eq_json': jsonEncode(graphicEq.toJson()),
          'af.parametric_eq_json': jsonEncode(parametricEq.toJson()),
        });
        final p = await SharedPreferences.getInstance();

        // Run migration
        await PlayerSettingsStore.migrateSplitKeys(p);

        // Verify split keys are removed
        expect(p.getString('af.dsp_state_json'), isNull);
        expect(p.getString('af.graphic_eq_json'), isNull);
        expect(p.getString('af.parametric_eq_json'), isNull);

        // Verify combined key exists
        final combinedJson = p.getString('af.audio_effects_json');
        expect(combinedJson, isNotNull);

        // Verify combined state has all fields
        final combined = PlayerSettingsStore.loadAudioEffects(p);
        expect(combined, isNotNull);
        expect(combined!.bass!.enabled, isTrue);
        expect(combined.bass!.g, 5.0);
        expect(combined.loudnorm!.enabled, isTrue);
        // Graphic EQ preserved in superequalizer
        expect(combined.superequalizer!.enabled, isTrue);
        expect(combined.superequalizer!.params, isNotEmpty);
        // Parametric EQ preserved in custom filters
        expect(combined.custom, isNotEmpty);
      });

      test('does nothing when no split keys exist', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();

        await PlayerSettingsStore.migrateSplitKeys(p);

        expect(p.getString('af.audio_effects_json'), isNull);
        expect(p.getString('af.dsp_state_json'), isNull);
        expect(p.getString('af.graphic_eq_json'), isNull);
        expect(p.getString('af.parametric_eq_json'), isNull);
      });

      test('does not overwrite existing combined key', () async {
        // Set up both combined and split keys
        final existingFx = {
          'bass_g': 3.0,
          'bass_enabled': true,
          'custom_filters': <String>[],
        };

        SharedPreferences.setMockInitialValues({
          'af.audio_effects_json': jsonEncode(existingFx),
          'af.dsp_state_json': '{"bass_g": 5.0, "bass_enabled": true}',
          'af.graphic_eq_json':
              '{"levels": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], "enabled": true}',
          'af.parametric_eq_json': '{"bands": []}',
        });
        final p = await SharedPreferences.getInstance();

        await PlayerSettingsStore.migrateSplitKeys(p);

        // Combined key should still have original value (not overwritten)
        final combined = PlayerSettingsStore.loadAudioEffects(p);
        expect(combined, isNotNull);
        expect(combined!.bass!.g, 3.0);

        // Split keys should be removed
        expect(p.getString('af.dsp_state_json'), isNull);
        expect(p.getString('af.graphic_eq_json'), isNull);
        expect(p.getString('af.parametric_eq_json'), isNull);
      });

      test('migration is idempotent', () async {
        SharedPreferences.setMockInitialValues({
          'af.dsp_state_json': '{"bass_g": 5.0, "bass_enabled": true}',
          'af.graphic_eq_json':
              '{"levels": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], "enabled": false}',
          'af.parametric_eq_json': '{"bands": []}',
        });
        final p = await SharedPreferences.getInstance();

        await PlayerSettingsStore.migrateSplitKeys(p);
        await PlayerSettingsStore.migrateSplitKeys(p);

        // Should not crash and split keys should be gone
        expect(p.getString('af.dsp_state_json'), isNull);
        expect(p.getString('af.graphic_eq_json'), isNull);
        expect(p.getString('af.parametric_eq_json'), isNull);
      });
    });

    // ── Unified key for all sub-screens ────────────────────────────────────
    group('unified key saves', () {
      test('graphic EQ state round-trips through unified key', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();

        // Simulate what graphic_eq_screen does after C2:
        // 1. Load current effects from unified key
        // 2. Merge graphic EQ into current
        // 3. Save merged result back to unified key
        const current = AudioEffects();
        final graphicEq = GraphicEqState(
          levels: List.generate(18, (i) => i * 0.5),
          enabled: true,
        );
        final merged = graphicEq.toAudioEffects(current);

        await PlayerSettingsStore.saveAudioEffects(merged);
        final loaded = PlayerSettingsStore.loadAudioEffects(p);

        expect(loaded, isNotNull);
        expect(loaded!.superequalizer!.enabled, isTrue);
        expect(loaded.superequalizer!.params.isNotEmpty, isTrue);
      });

      test('parametric EQ state round-trips through unified key', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();

        const current = AudioEffects();
        final parametricEq = ParametricEqState();
        parametricEq.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 5.0,
            q: 2.0,
            type: BandType.peak,
            enabled: true,
          ),
        );
        final merged = parametricEq.toAudioEffects(current);

        await PlayerSettingsStore.saveAudioEffects(merged);
        final loaded = PlayerSettingsStore.loadAudioEffects(p);

        expect(loaded, isNotNull);
        expect(loaded!.custom, isNotEmpty);
      });

      test('DSP state round-trips through unified key', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();

        const fx = AudioEffects(
          bass: BassSettings(enabled: true, g: 5.0),
          treble: TrebleSettings(enabled: true, g: -3.0),
          loudnorm: LoudnormSettings(enabled: true),
        );

        await PlayerSettingsStore.saveAudioEffects(fx);
        final loaded = PlayerSettingsStore.loadAudioEffects(p);

        expect(loaded, isNotNull);
        expect(loaded!.bass!.enabled, isTrue);
        expect(loaded.bass!.g, 5.0);
        expect(loaded.treble!.enabled, isTrue);
        expect(loaded.treble!.g, -3.0);
        expect(loaded.loudnorm!.enabled, isTrue);
      });
    });
  });
}
