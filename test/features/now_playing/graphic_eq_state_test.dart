import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/models/graphic_eq_state.dart';

void main() {
  group('GraphicEqState', () {
    // ── Constructor defaults ──────────────────────────────────────────────
    group('defaults', () {
      test('creates with 18 zero-level bands', () {
        final state = GraphicEqState();
        expect(state.levels.length, 18);
        for (final level in state.levels) {
          expect(level, 0.0);
        }
      });

      test('enabled is false by default', () {
        final state = GraphicEqState();
        expect(state.enabled, false);
      });
    });

    // ── JSON round-trip ──────────────────────────────────────────────────
    group('toJson / fromJson', () {
      test('round-trips default state', () {
        final original = GraphicEqState();
        final json = original.toJson();
        final restored = GraphicEqState.fromJson(json);
        expect(restored.levels.length, 18);
        for (var i = 0; i < 18; i++) {
          expect(restored.levels[i], 0.0);
        }
        expect(restored.enabled, false);
      });

      test('round-trips state with non-default levels', () {
        final original = GraphicEqState(
          levels: List.generate(18, (i) => i * 0.5),
          enabled: true,
        );
        final json = original.toJson();
        final restored = GraphicEqState.fromJson(json);
        expect(restored.enabled, true);
        for (var i = 0; i < 18; i++) {
          expect(restored.levels[i], i * 0.5);
        }
      });

      test('round-trips negative levels', () {
        final original = GraphicEqState(
          levels: List.generate(18, (i) => -i * 0.3),
        );
        final json = original.toJson();
        final restored = GraphicEqState.fromJson(json);
        for (var i = 0; i < 18; i++) {
          expect(restored.levels[i], closeTo(-i * 0.3, 0.001));
        }
      });

      test('serializes to valid JSON string', () {
        final state = GraphicEqState(
          levels: [
            1.0,
            2.0,
            3.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
          ],
          enabled: true,
        );
        final jsonString = jsonEncode(state.toJson());
        final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
        expect(decoded['enabled'], true);
        expect(decoded['levels'], isA<List<dynamic>>());
        expect((decoded['levels'] as List).length, 18);
      });

      test('handles missing enabled key gracefully', () {
        final json = {'levels': List.filled(18, 0.0)};
        final state = GraphicEqState.fromJson(json);
        expect(state.enabled, false);
      });

      test('handles missing levels key gracefully', () {
        final json = {'enabled': true};
        final state = GraphicEqState.fromJson(json);
        expect(state.levels.length, 18);
        for (final level in state.levels) {
          expect(level, 0.0);
        }
      });
    });

    // ── toAudioEffects ───────────────────────────────────────────────────
    group('toAudioEffects', () {
      test('maps levels to superequalizer params when enabled', () {
        final state = GraphicEqState(
          levels: List.generate(18, (i) => (i + 1) * 0.5),
          enabled: true,
        );
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer.enabled, true);
        expect(fx.superequalizer.params.length, 18);
      });

      test('maps zero levels to empty params', () {
        final state = GraphicEqState(enabled: true);
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer.enabled, true);
        expect(fx.superequalizer.params, isEmpty);
      });

      test('disables superequalizer when state is disabled', () {
        final state = GraphicEqState(
          levels: List.filled(18, 2.0),
          enabled: false,
        );
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer.enabled, false);
      });

      test('preserves other audio effects', () {
        final state = GraphicEqState(
          levels: List.generate(18, (i) => 1.0),
          enabled: true,
        );
        const original = AudioEffects(
          bass: BassSettings(enabled: true, g: 3.0),
        );
        final fx = state.toAudioEffects(original);
        expect(fx.bass.enabled, true);
        expect(fx.bass.g, 3.0);
      });

      test('converts level dB to superequalizer gain multiplier', () {
        final state = GraphicEqState(
          levels: [
            1.0,
            2.0,
            3.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
          ],
          enabled: true,
        );
        final fx = state.toAudioEffects(const AudioEffects());
        // Band 0 should have a gain value > 1.0 (boosted)
        final band0Gain = fx.superequalizer.params['1b'];
        expect(band0Gain, isNotNull);
        expect(band0Gain!, greaterThan(1.0));
      });
    });

    // ── fromAudioEffects ─────────────────────────────────────────────────
    group('fromAudioEffects', () {
      test('restores levels from superequalizer params', () {
        const fx = AudioEffects(
          superequalizer: SuperequalizerSettings(
            enabled: true,
            params: {'1b': 1.5, '2b': 1.2, '9b': 2.0},
          ),
        );
        final state = GraphicEqState.fromAudioEffects(fx);
        expect(state.enabled, true);
        expect(state.levels[0], closeTo(1.0, 0.1));
        expect(state.levels[8], closeTo(1.5, 0.1));
      });

      test('defaults to disabled when superequalizer is disabled', () {
        const fx = AudioEffects(
          superequalizer: SuperequalizerSettings(enabled: false),
        );
        final state = GraphicEqState.fromAudioEffects(fx);
        expect(state.enabled, false);
      });

      test('handles empty params', () {
        const fx = AudioEffects(
          superequalizer: SuperequalizerSettings(enabled: true, params: {}),
        );
        final state = GraphicEqState.fromAudioEffects(fx);
        expect(state.enabled, true);
        expect(state.levels.every((l) => l == 0.0), true);
      });
    });

    // ── Edge cases ───────────────────────────────────────────────────────
    group('edge cases', () {
      test('handles max boost level (+12 dB)', () {
        final state = GraphicEqState(
          levels: List.filled(18, 12.0),
          enabled: true,
        );
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer.enabled, true);
        for (final gain in fx.superequalizer.params.values) {
          expect(gain, greaterThan(1.0));
        }
      });

      test('handles max cut level (-12 dB)', () {
        final state = GraphicEqState(
          levels: List.filled(18, -12.0),
          enabled: true,
        );
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer.enabled, true);
        for (final gain in fx.superequalizer.params.values) {
          expect(gain, lessThan(1.0));
        }
      });

      test('handles mixed levels', () {
        final levels = List<double>.generate(
          18,
          (i) => (i % 2 == 0) ? 3.0 : -3.0,
        );
        final state = GraphicEqState(levels: levels, enabled: true);
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer.enabled, true);
        expect(fx.superequalizer.params.length, 18);
      });

      test('all levels at zero produce empty params', () {
        final state = GraphicEqState(enabled: true);
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer.params, isEmpty);
      });
    });

    // ── Immutability / copy ──────────────────────────────────────────────
    group('copy', () {
      test('copy creates independent instance', () {
        final original = GraphicEqState(
          levels: List.filled(18, 3.0),
          enabled: true,
        );
        final copy = original.copy();
        copy.levels[0] = 5.0;
        expect(original.levels[0], 3.0);
      });

      test('copy preserves all values', () {
        final original = GraphicEqState(
          levels: List.generate(18, (i) => i * 0.5),
          enabled: true,
        );
        final copy = original.copy();
        expect(copy.enabled, true);
        for (var i = 0; i < 18; i++) {
          expect(copy.levels[i], i * 0.5);
        }
      });
    });
  });
}
