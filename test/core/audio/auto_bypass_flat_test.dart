import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/player_service.dart';

/// Tests for [autoBypassFlat] — the pre-mpv filter pruner that
/// disables filters whose parameters are at their no-op values, so
/// libmpv doesn't carry dead entries in its `af` chain.
void main() {
  group('autoBypassFlat', () {
    test('bass: enabled stays true when gain is non-zero', () {
      final fx = const AudioEffects().copyWith(
        bass: const BassSettings(enabled: true, g: 6.0),
      );
      final out = autoBypassFlat(fx);
      expect(out.bass!.enabled, isTrue);
      expect(out.bass!.g, 6.0);
    });

    test('bass: enabled flips to false when gain is 0', () {
      final fx = const AudioEffects().copyWith(
        bass: const BassSettings(enabled: true, g: 0.0),
      );
      final out = autoBypassFlat(fx);
      expect(out.bass!.enabled, isFalse);
    });

    test('treble: enabled flips to false when gain is 0', () {
      final fx = const AudioEffects().copyWith(
        treble: const TrebleSettings(enabled: true, g: 0.0),
      );
      final out = autoBypassFlat(fx);
      expect(out.treble!.enabled, isFalse);
    });

    test('superequalizer: enabled stays true when params is non-empty', () {
      final fx = const AudioEffects().copyWith(
        superequalizer: const SuperequalizerSettings(
          enabled: true,
          params: {'1b': 2.0},
        ),
      );
      final out = autoBypassFlat(fx);
      expect(out.superequalizer!.enabled, isTrue);
    });

    test('superequalizer: enabled stays true when a band is cut to 0.0', () {
      // Regression: previously the auto-bypass used `gain != 0.0` to
      // decide whether the EQ was meaningful, which treated a band
      // cut to 0 (full mute) as "flat" and disabled the entire
      // superequalizer. A 0.0 band is a strong user signal — keep it.
      final fx = const AudioEffects().copyWith(
        superequalizer: const SuperequalizerSettings(
          enabled: true,
          params: {'1b': 0.0},
        ),
      );
      final out = autoBypassFlat(fx);
      expect(out.superequalizer!.enabled, isTrue);
    });

    test('superequalizer: enabled flips to false when params is empty', () {
      final fx = const AudioEffects().copyWith(
        superequalizer: const SuperequalizerSettings(enabled: true, params: {}),
      );
      final out = autoBypassFlat(fx);
      expect(out.superequalizer!.enabled, isFalse);
    });

    test(
      'deesser: out-of-range f is clamped to [0,1] so libmpv accepts it',
      () {
        // Regression: the EQ/DSP screen previously exposed deesser.f
        // as a Hz cutoff (2000..12000) but libmpv's `lavfi-deesser`
        // takes a 0..1 ratio. The first toggle of de-esser would
        // submit `f=5500`, libmpv would reject the entire af chain,
        // and Bass/Treble/EQ would silently stop working too. The
        // sanitiser clamps so a stale persisted value cannot poison
        // the chain on next launch.
        final fx = const AudioEffects().copyWith(
          deesser: const DeesserSettings(
            enabled: true,
            f: 5500.0,
            i: 0.5,
            m: 0.5,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.deesser!.f, 1.0);
        expect(out.deesser!.i, 0.5);
        expect(out.deesser!.m, 0.5);
        expect(out.deesser!.enabled, isTrue);
      },
    );

    test('deesser: negative params are clamped to 0', () {
      final fx = const AudioEffects().copyWith(
        deesser: const DeesserSettings(
          enabled: true,
          f: -0.2,
          i: -1.0,
          m: -3.5,
        ),
      );
      final out = autoBypassFlat(fx);
      expect(out.deesser!.f, 0.0);
      expect(out.deesser!.i, 0.0);
      expect(out.deesser!.m, 0.0);
    });

    test('deesser: in-range params pass through unchanged', () {
      final fx = const AudioEffects().copyWith(
        deesser: const DeesserSettings(enabled: true, f: 0.5, i: 0.3, m: 0.75),
      );
      final out = autoBypassFlat(fx);
      expect(out.deesser!.f, 0.5);
      expect(out.deesser!.i, 0.3);
      expect(out.deesser!.m, 0.75);
    });

    test('disabled filters stay disabled', () {
      final fx = const AudioEffects().copyWith(
        bass: const BassSettings(enabled: false, g: 6.0),
        treble: const TrebleSettings(enabled: false, g: 6.0),
        superequalizer: const SuperequalizerSettings(
          enabled: false,
          params: {'1b': 2.0},
        ),
      );
      final out = autoBypassFlat(fx);
      expect(out.bass!.enabled, isFalse);
      expect(out.treble!.enabled, isFalse);
      expect(out.superequalizer!.enabled, isFalse);
    });

    // ── M3: Range validation for all effects ──────────────────────────────
    group('range validation (M3)', () {
      test('compressor threshold clamped to -100..0', () {
        final fx = const AudioEffects().copyWith(
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: 50.0,
            ratio: 4,
            attack: 10,
            release: 100,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.acompressor!.threshold, 0.0);

        final fx2 = const AudioEffects().copyWith(
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: -150.0,
            ratio: 4,
            attack: 10,
            release: 100,
          ),
        );
        final out2 = autoBypassFlat(fx2);
        expect(out2.acompressor!.threshold, -100.0);
      });

      test('compressor ratio clamped to 1..30', () {
        final fx = const AudioEffects().copyWith(
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: -20,
            ratio: 0.5,
            attack: 10,
            release: 100,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.acompressor!.ratio, 1.0);

        final fx2 = const AudioEffects().copyWith(
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: -20,
            ratio: 50.0,
            attack: 10,
            release: 100,
          ),
        );
        final out2 = autoBypassFlat(fx2);
        expect(out2.acompressor!.ratio, 30.0);
      });

      test('compressor attack clamped to 0.1..1000', () {
        final fx = const AudioEffects().copyWith(
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: -20,
            ratio: 4,
            attack: 0.01,
            release: 100,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.acompressor!.attack, 0.1);

        final fx2 = const AudioEffects().copyWith(
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: -20,
            ratio: 4,
            attack: 2000,
            release: 100,
          ),
        );
        final out2 = autoBypassFlat(fx2);
        expect(out2.acompressor!.attack, 1000.0);
      });

      test('compressor release clamped to 0.1..1000', () {
        final fx = const AudioEffects().copyWith(
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: -20,
            ratio: 4,
            attack: 10,
            release: 0.01,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.acompressor!.release, 0.1);

        final fx2 = const AudioEffects().copyWith(
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: -20,
            ratio: 4,
            attack: 10,
            release: 5000,
          ),
        );
        final out2 = autoBypassFlat(fx2);
        expect(out2.acompressor!.release, 1000.0);
      });

      test('gate threshold clamped to -100..0', () {
        final fx = const AudioEffects().copyWith(
          agate: const AgateSettings(
            enabled: true,
            threshold: 10.0,
            ratio: 2,
            attack: 10,
            release: 100,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.agate!.threshold, 0.0);
      });

      test('gate ratio clamped to 1..30', () {
        final fx = const AudioEffects().copyWith(
          agate: const AgateSettings(
            enabled: true,
            threshold: -30,
            ratio: 0.5,
            attack: 10,
            release: 100,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.agate!.ratio, 1.0);
      });

      test('rubberband pitch clamped to 0.5..2.0', () {
        final fx = const AudioEffects().copyWith(
          rubberband: const RubberbandSettings(
            enabled: true,
            pitch: 0.1,
            tempo: 1.0,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.rubberband!.pitch, 0.5);

        final fx2 = const AudioEffects().copyWith(
          rubberband: const RubberbandSettings(
            enabled: true,
            pitch: 5.0,
            tempo: 1.0,
          ),
        );
        final out2 = autoBypassFlat(fx2);
        expect(out2.rubberband!.pitch, 2.0);
      });

      test('rubberband tempo clamped to 0.5..2.0', () {
        final fx = const AudioEffects().copyWith(
          rubberband: const RubberbandSettings(
            enabled: true,
            pitch: 1.0,
            tempo: 0.1,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.rubberband!.tempo, 0.5);

        final fx2 = const AudioEffects().copyWith(
          rubberband: const RubberbandSettings(
            enabled: true,
            pitch: 1.0,
            tempo: 5.0,
          ),
        );
        final out2 = autoBypassFlat(fx2);
        expect(out2.rubberband!.tempo, 2.0);
      });

      test('tremolo frequency clamped to 0.1..50', () {
        final fx = const AudioEffects().copyWith(
          tremolo: const TremoloSettings(enabled: true, f: 0.01, d: 0.5),
        );
        final out = autoBypassFlat(fx);
        expect(out.tremolo!.f, 0.1);

        final fx2 = const AudioEffects().copyWith(
          tremolo: const TremoloSettings(enabled: true, f: 100.0, d: 0.5),
        );
        final out2 = autoBypassFlat(fx2);
        expect(out2.tremolo!.f, 50.0);
      });

      test('tremolo depth clamped to 0..1', () {
        final fx = const AudioEffects().copyWith(
          tremolo: const TremoloSettings(enabled: true, f: 5.0, d: 2.0),
        );
        final out = autoBypassFlat(fx);
        expect(out.tremolo!.d, 1.0);
      });

      test('vibrato frequency clamped to 0.1..50', () {
        final fx = const AudioEffects().copyWith(
          vibrato: const VibratoSettings(enabled: true, f: 0.01, d: 0.5),
        );
        final out = autoBypassFlat(fx);
        expect(out.vibrato!.f, 0.1);

        final fx2 = const AudioEffects().copyWith(
          vibrato: const VibratoSettings(enabled: true, f: 100.0, d: 0.5),
        );
        final out2 = autoBypassFlat(fx2);
        expect(out2.vibrato!.f, 50.0);
      });

      test('vibrato depth clamped to 0..1', () {
        final fx = const AudioEffects().copyWith(
          vibrato: const VibratoSettings(enabled: true, f: 5.0, d: 2.0),
        );
        final out = autoBypassFlat(fx);
        expect(out.vibrato!.d, 1.0);
      });
    });
  });
}
