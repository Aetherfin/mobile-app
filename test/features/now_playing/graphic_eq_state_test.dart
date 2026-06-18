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

    // ── toAudioEffects ───────────────────────────────────────────────────
    group('toAudioEffects', () {
      test('maps levels to superequalizer params when enabled', () {
        final state = GraphicEqState(
          levels: List.generate(18, (i) => (i + 1) * 0.5),
          enabled: true,
        );
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer!.enabled, true);
        expect(fx.superequalizer!.params.length, 18);
      });

      test('maps zero levels to empty params', () {
        final state = GraphicEqState(enabled: true);
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer!.enabled, true);
        expect(fx.superequalizer!.params, isEmpty);
      });

      test('disables superequalizer when state is disabled', () {
        final state = GraphicEqState(
          levels: List.filled(18, 2.0),
          enabled: false,
        );
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer!.enabled, false);
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
        final band0Gain = fx.superequalizer!.params['1b'];
        expect(band0Gain, isNotNull);
        expect(band0Gain!, greaterThan(1.0));
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
        expect(fx.superequalizer!.enabled, true);
        for (final gain in fx.superequalizer!.params.values) {
          expect(gain, greaterThan(1.0));
        }
      });

      test('handles max cut level (-12 dB)', () {
        final state = GraphicEqState(
          levels: List.filled(18, -12.0),
          enabled: true,
        );
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer!.enabled, true);
        for (final gain in fx.superequalizer!.params.values) {
          expect(gain, lessThan(1.0));
        }
      });
    });
  });
}
