import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/features/now_playing/eq_band_logic.dart';

void main() {
  group('EqDspState (DSP-only, no EQ)', () {
    late EqDspState state;

    setUp(() {
      state = EqDspState();
    });

    // ── DSP fields preserved ──────────────────────────────────────────────
    group('DSP fields preserved', () {
      test('has masterEnabled', () {
        expect(state.masterEnabled, true);
      });

      test('has tone fields (bass/treble)', () {
        expect(state.bass, 0);
        expect(state.treble, 0);
      });

      test('has dynamics fields', () {
        expect(state.loudnorm, false);
        expect(state.compressor, false);
        expect(state.compThreshold, 0.1);
        expect(state.compRatio, 4.0);
        expect(state.compAttack, 20.0);
        expect(state.compRelease, 250.0);
      });
    });

    // ── toAudioEffects (no EQ) ────────────────────────────────────────────
    group('toAudioEffects', () {
      test('includes bass/treble', () {
        state.bass = 3.0;
        state.treble = -2.0;
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.bass.enabled, true);
        expect(fx.bass.g, 3.0);
        expect(fx.treble.enabled, true);
        expect(fx.treble.g, -2.0);
      });

      test('includes dynamics', () {
        state.loudnorm = true;
        state.compressor = true;
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.loudnorm.enabled, true);
        expect(fx.acompressor.enabled, true);
      });
    });

    // ── loadFromAudioEffects (no EQ) ──────────────────────────────────────
    group('loadFromAudioEffects', () {
      test('loads DSP fields from AudioEffects', () {
        const fx = AudioEffects(
          bass: BassSettings(enabled: true, g: 5.0),
          treble: TrebleSettings(enabled: true, g: -3.0),
          loudnorm: LoudnormSettings(enabled: true),
          acompressor: AcompressorSettings(enabled: true, threshold: 0.2),
          rubberband: RubberbandSettings(enabled: true, pitch: 1.2, tempo: 0.9),
        );
        state.loadFromAudioEffects(fx);
        expect(state.bass, 5.0);
        expect(state.treble, -3.0);
        expect(state.loudnorm, true);
        expect(state.compressor, true);
        expect(state.compThreshold, 0.2);
        expect(state.rubberbandEnabled, true);
        expect(state.pitch, 1.2);
        expect(state.tempo, 0.9);
      });

      test('ignores superequalizer settings', () {
        const fx = AudioEffects(
          superequalizer: SuperequalizerSettings(
            enabled: true,
            params: {'1b': 2.0, '2b': 1.5},
          ),
        );
        state.loadFromAudioEffects(fx);
        // Verify the output still has no superequalizer (DSP state doesn't own it)
        final out = state.toAudioEffects(const AudioEffects());
        expect(out.superequalizer.enabled, false);
        expect(out.superequalizer.params, isEmpty);
      });
    });

    // ── setField (no EQ cases) ────────────────────────────────────────────
    group('setField', () {
      test('sets DSP fields', () {
        state.setField('bass', 5.0);
        state.setField('treble', -3.0);
        state.setField('loudnorm', true);
        state.setField('compressor', true);
        state.setField('echoEnabled', true);
        state.setField('phaser', true);
        state.setField('crusher', true);

        expect(state.bass, 5.0);
        expect(state.treble, -3.0);
        expect(state.loudnorm, true);
        expect(state.compressor, true);
        expect(state.echoEnabled, true);
        expect(state.phaser, true);
        expect(state.crusher, true);
      });
    });

    // ── Typed setters (m1) ────────────────────────────────────────────────
    group('typed setters (m1)', () {
      test('setBass sets bass value', () {
        state.setBass(5.0);
        expect(state.bass, 5.0);
      });

      test('setTreble sets treble value', () {
        state.setTreble(-3.0);
        expect(state.treble, -3.0);
      });

      test('setCompressor sets compressor value', () {
        state.setCompressor(true);
        expect(state.compressor, true);
      });

      test('setLoudnorm sets loudnorm value', () {
        state.setLoudnorm(true);
        expect(state.loudnorm, true);
      });
    });

    // ── reset (no EQ) ─────────────────────────────────────────────────────
    group('reset', () {
      test('resets DSP fields to defaults', () {
        state.bass = 5.0;
        state.treble = -3.0;
        state.loudnorm = true;
        state.compressor = true;
        state.phaser = true;
        state.crusher = true;
        state.reset();

        expect(state.bass, 0);
        expect(state.treble, 0);
        expect(state.loudnorm, false);
        expect(state.compressor, false);
        expect(state.phaser, false);
        expect(state.crusher, false);
      });
    });

    // ── Badge counts ─────────────────────────────────────────────────────
    group('badge counts', () {
      test('has dynamicsCount', () {
        state.loudnorm = true;
        state.compressor = true;
        expect(state.dynamicsCount, 2);
      });

      test('has creativeCount', () {
        state.exciter = true;
        state.crystalizer = true;
        state.virtualBass = true;
        state.crusher = true;
        expect(state.creativeCount, 4);
      });
    });
  });
}
