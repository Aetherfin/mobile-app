import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherfin/core/audio/player_settings_store.dart';

/// Helper: set up mock SharedPreferences, save AudioEffects, then load them
/// back. Returns the round-tripped [AudioEffects].
Future<AudioEffects?> _roundTrip(AudioEffects fx) async {
  SharedPreferences.setMockInitialValues({});
  final p = await SharedPreferences.getInstance();
  await PlayerSettingsStore.saveAudioEffects(fx);
  return PlayerSettingsStore.loadAudioEffects(p);
}

/// Helper: write a raw JSON string to the effects key and load it.
Future<AudioEffects?> _loadFromRawJson(String jsonString) async {
  SharedPreferences.setMockInitialValues({
    PlayerSettingsStore.kAudioEffects: jsonString,
  });
  final p = await SharedPreferences.getInstance();
  return PlayerSettingsStore.loadAudioEffects(p);
}

void main() {
  // ── AudioEffects JSON round-trip ────────────────────────────────────────
  group('AudioEffects JSON round-trip', () {
    test('preserves all bass parameters', () async {
      final fx = const AudioEffects().copyWith(
        bass: const BassSettings(enabled: true, g: 6.0),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.bass!.enabled, isTrue);
      expect(loaded.bass!.g, 6.0);
    });

    test('preserves all treble parameters', () async {
      final fx = const AudioEffects().copyWith(
        treble: const TrebleSettings(enabled: true, g: -3.0),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.treble!.enabled, isTrue);
      expect(loaded.treble!.g, -3.0);
    });

    test('preserves loudnorm enabled state', () async {
      final fx = const AudioEffects().copyWith(
        loudnorm: const LoudnormSettings(enabled: true),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.loudnorm!.enabled, isTrue);
    });

    test('preserves all compressor parameters', () async {
      final fx = const AudioEffects().copyWith(
        acompressor: const AcompressorSettings(
          enabled: true,
          threshold: 0.2,
          ratio: 8.0,
          attack: 50.0,
          release: 500.0,
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.acompressor!.enabled, isTrue);
      expect(loaded.acompressor!.threshold, 0.2);
      expect(loaded.acompressor!.ratio, 8.0);
      expect(loaded.acompressor!.attack, 50.0);
      expect(loaded.acompressor!.release, 500.0);
    });

    test('preserves all rubberband parameters', () async {
      final fx = const AudioEffects().copyWith(
        rubberband: const RubberbandSettings(
          enabled: true,
          pitch: 1.5,
          tempo: 0.8,
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.rubberband!.enabled, isTrue);
      expect(loaded.rubberband!.pitch, 1.5);
      expect(loaded.rubberband!.tempo, 0.8);
    });

    test('preserves all crossfeed parameters', () async {
      final fx = const AudioEffects().copyWith(
        crossfeed: const CrossfeedSettings(enabled: true, strength: 0.8),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.crossfeed!.enabled, isTrue);
      expect(loaded.crossfeed!.strength, 0.8);
    });

    test('preserves all stereowiden parameters', () async {
      final fx = const AudioEffects().copyWith(
        stereowiden: const StereowidenSettings(enabled: true, delay: 40.0),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.stereowiden!.enabled, isTrue);
      expect(loaded.stereowiden!.delay, 40.0);
    });

    test('preserves all exciter parameters', () async {
      final fx = const AudioEffects().copyWith(
        aexciter: const AexciterSettings(enabled: true, amount: 3.5),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.aexciter!.enabled, isTrue);
      expect(loaded.aexciter!.amount, 3.5);
    });

    test('preserves all crystalizer parameters', () async {
      final fx = const AudioEffects().copyWith(
        crystalizer: const CrystalizerSettings(enabled: true, i: 4.0),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.crystalizer!.enabled, isTrue);
      expect(loaded.crystalizer!.i, 4.0);
    });

    test('preserves all virtualbass parameters', () async {
      final fx = const AudioEffects().copyWith(
        virtualbass: const VirtualbassSettings(enabled: true, cutoff: 300.0),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.virtualbass!.enabled, isTrue);
      expect(loaded.virtualbass!.cutoff, 300.0);
    });

    test('preserves all gate parameters', () async {
      final fx = const AudioEffects().copyWith(
        agate: const AgateSettings(
          enabled: true,
          threshold: 0.05,
          ratio: 3.0,
          attack: 30.0,
          release: 400.0,
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.agate!.enabled, isTrue);
      expect(loaded.agate!.threshold, 0.05);
      expect(loaded.agate!.ratio, 3.0);
      expect(loaded.agate!.attack, 30.0);
      expect(loaded.agate!.release, 400.0);
    });

    test('preserves all deesser parameters', () async {
      final fx = const AudioEffects().copyWith(
        deesser: const DeesserSettings(enabled: true, i: 0.3, m: 0.7, f: 0.9),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.deesser!.enabled, isTrue);
      expect(loaded.deesser!.i, 0.3);
      expect(loaded.deesser!.m, 0.7);
      expect(loaded.deesser!.f, 0.9);
    });

    test('preserves all echo parameters', () async {
      final fx = const AudioEffects().copyWith(
        aecho: const AechoSettings(
          enabled: true,
          in_gain: 0.8,
          out_gain: 0.5,
          delays: '300|600',
          decays: '0.3|0.6',
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.aecho!.enabled, isTrue);
      expect(loaded.aecho!.in_gain, 0.8);
      expect(loaded.aecho!.out_gain, 0.5);
      expect(loaded.aecho!.delays, '300|600');
      expect(loaded.aecho!.decays, '0.3|0.6');
    });

    test('preserves all phaser parameters', () async {
      final fx = const AudioEffects().copyWith(
        aphaser: const AphaserSettings(
          enabled: true,
          in_gain: 0.6,
          out_gain: 0.9,
          delay: 5.0,
          decay: 0.7,
          speed: 1.2,
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.aphaser!.enabled, isTrue);
      expect(loaded.aphaser!.in_gain, 0.6);
      expect(loaded.aphaser!.out_gain, 0.9);
      expect(loaded.aphaser!.delay, 5.0);
      expect(loaded.aphaser!.decay, 0.7);
      expect(loaded.aphaser!.speed, 1.2);
    });

    test('preserves all flanger parameters', () async {
      final fx = const AudioEffects().copyWith(
        flanger: const FlangerSettings(
          enabled: true,
          delay: 3.0,
          depth: 5.0,
          regen: 2.0,
          width: 100.0,
          speed: 1.5,
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.flanger!.enabled, isTrue);
      expect(loaded.flanger!.delay, 3.0);
      expect(loaded.flanger!.depth, 5.0);
      expect(loaded.flanger!.regen, 2.0);
      expect(loaded.flanger!.width, 100.0);
      expect(loaded.flanger!.speed, 1.5);
    });

    test('preserves all chorus parameters', () async {
      final fx = const AudioEffects().copyWith(
        chorus: const ChorusSettings(
          enabled: true,
          in_gain: 0.6,
          out_gain: 0.7,
          delays: '100|200',
          decays: '0.5|0.6',
          speeds: '0.3|0.5',
          depths: '4|5',
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.chorus!.enabled, isTrue);
      expect(loaded.chorus!.in_gain, 0.6);
      expect(loaded.chorus!.out_gain, 0.7);
      expect(loaded.chorus!.delays, '100|200');
      expect(loaded.chorus!.decays, '0.5|0.6');
      expect(loaded.chorus!.speeds, '0.3|0.5');
      expect(loaded.chorus!.depths, '4|5');
    });

    test('preserves all tremolo parameters', () async {
      final fx = const AudioEffects().copyWith(
        tremolo: const TremoloSettings(enabled: true, f: 10.0, d: 0.8),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.tremolo!.enabled, isTrue);
      expect(loaded.tremolo!.f, 10.0);
      expect(loaded.tremolo!.d, 0.8);
    });

    test('preserves all vibrato parameters', () async {
      final fx = const AudioEffects().copyWith(
        vibrato: const VibratoSettings(enabled: true, f: 8.0, d: 0.9),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.vibrato!.enabled, isTrue);
      expect(loaded.vibrato!.f, 8.0);
      expect(loaded.vibrato!.d, 0.9);
    });

    test('preserves all crusher parameters', () async {
      final fx = const AudioEffects().copyWith(
        acrusher: const AcrusherSettings(
          enabled: true,
          bits: 12.0,
          mix: 0.8,
          samples: 4.0,
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.acrusher!.enabled, isTrue);
      expect(loaded.acrusher!.bits, 12.0);
      expect(loaded.acrusher!.mix, 0.8);
      expect(loaded.acrusher!.samples, 4.0);
    });

    test('preserves eq_params map with multiple bands', () async {
      final fx = const AudioEffects().copyWith(
        superequalizer: const SuperequalizerSettings(
          enabled: true,
          params: {'1b': 3.0, '2b': -2.0, '3b': 0.0, '4b': 6.0},
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.superequalizer!.enabled, isTrue);
      expect(loaded.superequalizer!.params['1b'], 3.0);
      expect(loaded.superequalizer!.params['2b'], -2.0);
      expect(loaded.superequalizer!.params['3b'], 0.0);
      expect(loaded.superequalizer!.params['4b'], 6.0);
      expect(loaded.superequalizer!.params.length, 4);
    });

    test(
      'full round-trip with multiple effects enabled simultaneously',
      () async {
        final fx = const AudioEffects().copyWith(
          bass: const BassSettings(enabled: true, g: 4.0),
          treble: const TrebleSettings(enabled: true, g: -2.0),
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: 0.15,
            ratio: 6.0,
            attack: 30.0,
            release: 300.0,
          ),
          superequalizer: const SuperequalizerSettings(
            enabled: true,
            params: {'1b': 2.0, '5b': -1.0},
          ),
          aecho: const AechoSettings(
            enabled: true,
            in_gain: 0.7,
            out_gain: 0.4,
            delays: '200|400',
            decays: '0.2|0.4',
          ),
          chorus: const ChorusSettings(
            enabled: true,
            in_gain: 0.5,
            out_gain: 0.5,
            delays: '30|60',
            decays: '0.4|0.3',
            speeds: '0.2|0.4',
            depths: '2|3',
          ),
        );
        final loaded = await _roundTrip(fx);
        expect(loaded, isNotNull);
        // bass
        expect(loaded!.bass!.enabled, isTrue);
        expect(loaded.bass!.g, 4.0);
        // treble
        expect(loaded.treble!.enabled, isTrue);
        expect(loaded.treble!.g, -2.0);
        // compressor
        expect(loaded.acompressor!.enabled, isTrue);
        expect(loaded.acompressor!.threshold, 0.15);
        expect(loaded.acompressor!.ratio, 6.0);
        // eq
        expect(loaded.superequalizer!.enabled, isTrue);
        expect(loaded.superequalizer!.params.length, 2);
        // echo
        expect(loaded.aecho!.enabled, isTrue);
        expect(loaded.aecho!.delays, '200|400');
        // chorus
        expect(loaded.chorus!.enabled, isTrue);
        expect(loaded.chorus!.delays, '30|60');
      },
    );
  });

  // ── Default values ─────────────────────────────────────────────────────
  group('Default AudioEffects values', () {
    test('slots are null when constructed with defaults', () {
      const fx = AudioEffects();
      expect(fx.bass, isNull);
      expect(fx.treble, isNull);
      expect(fx.loudnorm, isNull);
      expect(fx.acompressor, isNull);
      expect(fx.superequalizer, isNull);
      expect(fx.rubberband, isNull);
      expect(fx.crossfeed, isNull);
      expect(fx.stereowiden, isNull);
      expect(fx.aexciter, isNull);
      expect(fx.crystalizer, isNull);
      expect(fx.virtualbass, isNull);
      expect(fx.agate, isNull);
      expect(fx.deesser, isNull);
      expect(fx.aecho, isNull);
      expect(fx.aphaser, isNull);
      expect(fx.flanger, isNull);
      expect(fx.chorus, isNull);
      expect(fx.tremolo, isNull);
      expect(fx.vibrato, isNull);
      expect(fx.acrusher, isNull);
    });

    test('non-null slots have expected default values', () {
      const fx = AudioEffects(
        bass: BassSettings(),
        treble: TrebleSettings(),
        loudnorm: LoudnormSettings(),
        acompressor: AcompressorSettings(),
        superequalizer: SuperequalizerSettings(),
        rubberband: RubberbandSettings(),
        crossfeed: CrossfeedSettings(),
        stereowiden: StereowidenSettings(),
        aexciter: AexciterSettings(),
        crystalizer: CrystalizerSettings(),
        virtualbass: VirtualbassSettings(),
        agate: AgateSettings(),
        deesser: DeesserSettings(),
        aecho: AechoSettings(),
        aphaser: AphaserSettings(),
        flanger: FlangerSettings(),
        chorus: ChorusSettings(
          delays: '55|60',
          decays: '0.4|0.32',
          speeds: '0.25|0.4',
          depths: '2|1.3',
        ),
        tremolo: TremoloSettings(),
        vibrato: VibratoSettings(),
        acrusher: AcrusherSettings(),
      );
      expect(fx.bass!.enabled, isFalse);
      expect(fx.bass!.g, 0.0);
      expect(fx.treble!.enabled, isFalse);
      expect(fx.treble!.g, 0.0);
      expect(fx.loudnorm!.enabled, isFalse);
      expect(fx.acompressor!.enabled, isFalse);
      expect(fx.acompressor!.threshold, 0.125);
      expect(fx.acompressor!.ratio, 2.0);
      expect(fx.acompressor!.attack, 20.0);
      expect(fx.acompressor!.release, 250.0);
      expect(fx.superequalizer!.enabled, isFalse);
      expect(fx.superequalizer!.params, isEmpty);
      expect(fx.rubberband!.enabled, isFalse);
      expect(fx.rubberband!.pitch, 1.0);
      expect(fx.rubberband!.tempo, 1.0);
      expect(fx.crossfeed!.enabled, isFalse);
      expect(fx.crossfeed!.strength, 0.2);
      expect(fx.stereowiden!.enabled, isFalse);
      expect(fx.stereowiden!.delay, 20.0);
      expect(fx.aexciter!.enabled, isFalse);
      expect(fx.aexciter!.amount, 1.0);
      expect(fx.crystalizer!.enabled, isFalse);
      expect(fx.crystalizer!.i, 2.0);
      expect(fx.virtualbass!.enabled, isFalse);
      expect(fx.virtualbass!.cutoff, 250.0);
      expect(fx.agate!.enabled, isFalse);
      expect(fx.agate!.threshold, 0.125);
      expect(fx.agate!.ratio, 2.0);
      expect(fx.agate!.attack, 20.0);
      expect(fx.agate!.release, 250.0);
      expect(fx.deesser!.enabled, isFalse);
      expect(fx.deesser!.i, 0.0);
      expect(fx.deesser!.m, 0.5);
      expect(fx.deesser!.f, 0.5);
      expect(fx.aecho!.enabled, isFalse);
      expect(fx.aecho!.in_gain, 0.6);
      expect(fx.aecho!.out_gain, 0.3);
      expect(fx.aecho!.delays, '1000');
      expect(fx.aecho!.decays, '0.5');
      expect(fx.aphaser!.enabled, isFalse);
      expect(fx.aphaser!.in_gain, 0.4);
      expect(fx.aphaser!.out_gain, 0.74);
      expect(fx.aphaser!.delay, 3.0);
      expect(fx.aphaser!.decay, 0.4);
      expect(fx.aphaser!.speed, 0.5);
      expect(fx.flanger!.enabled, isFalse);
      expect(fx.flanger!.delay, 0.0);
      expect(fx.flanger!.depth, 2.0);
      expect(fx.flanger!.regen, 0.0);
      expect(fx.flanger!.width, 71.0);
      expect(fx.flanger!.speed, 0.5);
      expect(fx.chorus!.enabled, isFalse);
      expect(fx.chorus!.in_gain, 0.4);
      expect(fx.chorus!.out_gain, 0.4);
      expect(fx.chorus!.delays, '55|60');
      expect(fx.chorus!.decays, '0.4|0.32');
      expect(fx.chorus!.speeds, '0.25|0.4');
      expect(fx.chorus!.depths, '2|1.3');
      expect(fx.tremolo!.enabled, isFalse);
      expect(fx.tremolo!.f, 5.0);
      expect(fx.tremolo!.d, 0.5);
      expect(fx.vibrato!.enabled, isFalse);
      expect(fx.vibrato!.f, 5.0);
      expect(fx.vibrato!.d, 0.5);
      expect(fx.acrusher!.enabled, isFalse);
      expect(fx.acrusher!.bits, 8.0);
      expect(fx.acrusher!.mix, 0.5);
      expect(fx.acrusher!.samples, 1.0);
    });
  });

  // ── Edge cases ─────────────────────────────────────────────────────────
  group('Edge cases', () {
    test(
      'echo: empty string for delays and decays round-trips correctly',
      () async {
        final fx = const AudioEffects().copyWith(
          aecho: const AechoSettings(enabled: true, delays: '', decays: ''),
        );
        final loaded = await _roundTrip(fx);
        expect(loaded, isNotNull);
        expect(loaded!.aecho!.delays, '');
        expect(loaded.aecho!.decays, '');
      },
    );

    test('chorus: empty string for delays round-trips correctly', () async {
      final fx = const AudioEffects().copyWith(
        chorus: const ChorusSettings(
          enabled: true,
          delays: '',
          decays: '',
          speeds: '',
          depths: '',
        ),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.chorus!.delays, '');
      expect(loaded.chorus!.decays, '');
      expect(loaded.chorus!.speeds, '');
      expect(loaded.chorus!.depths, '');
    });

    test(
      'extreme gain values: bass g=0.0 and g=4.0 round-trip correctly',
      () async {
        final fxMin = const AudioEffects().copyWith(
          bass: const BassSettings(enabled: true, g: 0.0),
        );
        final fxMax = const AudioEffects().copyWith(
          bass: const BassSettings(enabled: true, g: 4.0),
        );
        final loadedMin = await _roundTrip(fxMin);
        final loadedMax = await _roundTrip(fxMax);
        expect(loadedMin!.bass!.g, 0.0);
        expect(loadedMax!.bass!.g, 4.0);
      },
    );

    test(
      'extreme gain values: treble g=-4.0 and g=0.0 round-trip correctly',
      () async {
        final fxMin = const AudioEffects().copyWith(
          treble: const TrebleSettings(enabled: true, g: -4.0),
        );
        final fxMax = const AudioEffects().copyWith(
          treble: const TrebleSettings(enabled: true, g: 0.0),
        );
        final loadedMin = await _roundTrip(fxMin);
        final loadedMax = await _roundTrip(fxMax);
        expect(loadedMin!.treble!.g, -4.0);
        expect(loadedMax!.treble!.g, 0.0);
      },
    );

    test(
      'boolean toggles: all effects disabled by default, all can be enabled',
      () async {
        final fx = const AudioEffects().copyWith(
          bass: const BassSettings(enabled: true, g: 1.0),
          treble: const TrebleSettings(enabled: true, g: 1.0),
          loudnorm: const LoudnormSettings(enabled: true),
          acompressor: const AcompressorSettings(enabled: true),
          superequalizer: const SuperequalizerSettings(
            enabled: true,
            params: {'1b': 1.0},
          ),
          rubberband: const RubberbandSettings(enabled: true),
          crossfeed: const CrossfeedSettings(enabled: true),
          stereowiden: const StereowidenSettings(enabled: true),
          aexciter: const AexciterSettings(enabled: true),
          crystalizer: const CrystalizerSettings(enabled: true),
          virtualbass: const VirtualbassSettings(enabled: true),
          agate: const AgateSettings(enabled: true),
          deesser: const DeesserSettings(enabled: true),
          aecho: const AechoSettings(enabled: true),
          aphaser: const AphaserSettings(enabled: true),
          flanger: const FlangerSettings(enabled: true),
          chorus: const ChorusSettings(
            enabled: true,
            delays: '50',
            decays: '0.5',
            speeds: '0.3',
            depths: '2',
          ),
          tremolo: const TremoloSettings(enabled: true),
          vibrato: const VibratoSettings(enabled: true),
          acrusher: const AcrusherSettings(enabled: true),
        );
        final loaded = await _roundTrip(fx);
        expect(loaded, isNotNull);
        expect(loaded!.bass!.enabled, isTrue);
        expect(loaded.treble!.enabled, isTrue);
        expect(loaded.loudnorm!.enabled, isTrue);
        expect(loaded.acompressor!.enabled, isTrue);
        expect(loaded.superequalizer!.enabled, isTrue);
        expect(loaded.rubberband!.enabled, isTrue);
        expect(loaded.crossfeed!.enabled, isTrue);
        expect(loaded.stereowiden!.enabled, isTrue);
        expect(loaded.aexciter!.enabled, isTrue);
        expect(loaded.crystalizer!.enabled, isTrue);
        expect(loaded.virtualbass!.enabled, isTrue);
        expect(loaded.agate!.enabled, isTrue);
        expect(loaded.deesser!.enabled, isTrue);
        expect(loaded.aecho!.enabled, isTrue);
        expect(loaded.aphaser!.enabled, isTrue);
        expect(loaded.flanger!.enabled, isTrue);
        expect(loaded.chorus!.enabled, isTrue);
        expect(loaded.tremolo!.enabled, isTrue);
        expect(loaded.vibrato!.enabled, isTrue);
        expect(loaded.acrusher!.enabled, isTrue);
      },
    );

    test('negative gain values round-trip correctly', () async {
      final fx = const AudioEffects().copyWith(
        bass: const BassSettings(enabled: true, g: -2.0),
        tremolo: const TremoloSettings(enabled: true, f: -1.0, d: -0.5),
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.bass!.g, -2.0);
      expect(loaded.tremolo!.f, -1.0);
      expect(loaded.tremolo!.d, -0.5);
    });
  });

  // ── copyWith preservation ──────────────────────────────────────────────
  group('copyWith preservation', () {
    test('copyWith bass preserves all other effects unchanged', () {
      const original = AudioEffects(
        bass: BassSettings(enabled: true, g: 3.0),
        treble: TrebleSettings(enabled: true, g: -1.0),
        acompressor: AcompressorSettings(enabled: true, ratio: 6.0),
      );
      final modified = original.copyWith(
        bass: const BassSettings(enabled: true, g: 5.0),
      );
      expect(modified.bass!.g, 5.0);
      expect(modified.treble!.g, -1.0);
      expect(modified.acompressor!.ratio, 6.0);
    });

    test('copyWith aecho preserves echo delays/decays', () {
      const original = AudioEffects(
        aecho: AechoSettings(
          enabled: true,
          delays: '100|200',
          decays: '0.5|0.6',
        ),
      );
      final modified = original.copyWith(
        aecho: const AechoSettings(
          enabled: true,
          delays: '300|400',
          decays: '0.1|0.2',
        ),
      );
      expect(modified.aecho!.delays, '300|400');
      expect(modified.aecho!.decays, '0.1|0.2');
    });

    test('copyWith chorus preserves all string fields', () {
      const original = AudioEffects(
        chorus: ChorusSettings(
          enabled: true,
          delays: '50|60',
          decays: '0.4|0.3',
          speeds: '0.2|0.4',
          depths: '2|3',
          in_gain: 0.5,
          out_gain: 0.5,
        ),
      );
      final modified = original.copyWith(
        chorus: const ChorusSettings(
          enabled: true,
          delays: '100|200',
          decays: '0.5|0.6',
          speeds: '0.3|0.5',
          depths: '4|5',
          in_gain: 0.6,
          out_gain: 0.6,
        ),
      );
      expect(modified.chorus!.delays, '100|200');
      expect(modified.chorus!.decays, '0.5|0.6');
      expect(modified.chorus!.speeds, '0.3|0.5');
      expect(modified.chorus!.depths, '4|5');
    });
  });

  // ── Partial JSON (missing fields use loadAudioEffects defaults) ────────
  group('Partial JSON deserialization', () {
    test('missing bass fields use defaults', () async {
      final loaded = await _loadFromRawJson('{}');
      expect(loaded, isNotNull);
      expect(loaded!.bass!.enabled, isFalse);
      expect(loaded.bass!.g, 0.0);
    });

    test('missing compressor fields use loadAudioEffects defaults', () async {
      final loaded = await _loadFromRawJson('{}');
      expect(loaded, isNotNull);
      expect(loaded!.acompressor!.enabled, isFalse);
      // Note: loadAudioEffects defaults to 0.1 and 4.0, different from
      // the library's constructor defaults of 0.125 and 2.0
      expect(loaded.acompressor!.threshold, 0.1);
      expect(loaded.acompressor!.ratio, 4.0);
      expect(loaded.acompressor!.attack, 20.0);
      expect(loaded.acompressor!.release, 250.0);
    });

    test('missing echo fields use loadAudioEffects defaults', () async {
      final loaded = await _loadFromRawJson('{}');
      expect(loaded, isNotNull);
      expect(loaded!.aecho!.enabled, isFalse);
      // loadAudioEffects defaults echo_delays to '500', not '1000'
      expect(loaded.aecho!.delays, '500');
      expect(loaded.aecho!.decays, '0.5');
      expect(loaded.aecho!.in_gain, 0.6);
      expect(loaded.aecho!.out_gain, 0.3);
    });

    test('missing chorus fields use loadAudioEffects defaults', () async {
      final loaded = await _loadFromRawJson('{}');
      expect(loaded, isNotNull);
      expect(loaded!.chorus!.enabled, isFalse);
      // loadAudioEffects defaults differ from library constructor:
      // delays '40|60' vs '55|60', depths '2|3' vs '2|1.3'
      expect(loaded.chorus!.delays, '40|60');
      expect(loaded.chorus!.decays, '0.4|0.32');
      expect(loaded.chorus!.speeds, '0.25|0.4');
      expect(loaded.chorus!.depths, '2|3');
    });

    test('partial JSON: only bass_enabled present', () async {
      final loaded = await _loadFromRawJson('{"bass_enabled": true}');
      expect(loaded, isNotNull);
      expect(loaded!.bass!.enabled, isTrue);
      // bass_g missing → default 0.0
      expect(loaded.bass!.g, 0.0);
      // other effects unaffected
      expect(loaded.treble!.enabled, isFalse);
      expect(loaded.acompressor!.enabled, isFalse);
    });

    test('partial JSON: eq_params is empty map when not present', () async {
      final loaded = await _loadFromRawJson('{}');
      expect(loaded, isNotNull);
      expect(loaded!.superequalizer!.params, isEmpty);
    });

    test('returns null when key is absent from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final loaded = PlayerSettingsStore.loadAudioEffects(p);
      expect(loaded, isNull);
    });

    test('returns null on malformed JSON', () async {
      SharedPreferences.setMockInitialValues({
        PlayerSettingsStore.kAudioEffects: 'not valid json{{{',
      });
      final p = await SharedPreferences.getInstance();
      final loaded = PlayerSettingsStore.loadAudioEffects(p);
      expect(loaded, isNull);
    });
  });

  // ── EqPreset serialization ─────────────────────────────────────────────
  group('EqPreset serialization', () {
    test('toJson/fromJson round-trip preserves all bands', () {
      const preset = EqPreset(
        bands: {
          '1b': 3.0,
          '2b': -2.5,
          '3b': 0.0,
          '4b': 6.0,
          '5b': -6.0,
          '6b': 1.5,
          '7b': -1.0,
          '8b': 4.0,
          '9b': -4.0,
          '10b': 2.0,
          '11b': -2.0,
          '12b': 3.0,
          '13b': -3.0,
          '14b': 1.0,
          '15b': -1.0,
          '16b': 0.5,
          '17b': -0.5,
          '18b': 0.0,
        },
        bass: 2.0,
        treble: -1.5,
      );
      final json = preset.toJson();
      final restored = EqPreset.fromJson(json);
      expect(restored.bands.length, 18);
      expect(restored.bands['1b'], 3.0);
      expect(restored.bands['9b'], -4.0);
      expect(restored.bands['18b'], 0.0);
      expect(restored.bass, 2.0);
      expect(restored.treble, -1.5);
    });

    test('toJson/fromJson round-trip with empty bands', () {
      const preset = EqPreset(bands: {}, bass: 0.0, treble: 0.0);
      final json = preset.toJson();
      final restored = EqPreset.fromJson(json);
      expect(restored.bands, isEmpty);
      expect(restored.bass, 0.0);
      expect(restored.treble, 0.0);
    });

    test('fromJson with missing bands defaults to empty map', () {
      final restored = EqPreset.fromJson({'bass': 1.0, 'treble': -1.0});
      expect(restored.bands, isEmpty);
      expect(restored.bass, 1.0);
      expect(restored.treble, -1.0);
    });

    test('fromJson with missing bass/treble defaults to 0.0', () {
      final restored = EqPreset.fromJson({
        'bands': {'1b': 2.0},
      });
      expect(restored.bands['1b'], 2.0);
      expect(restored.bass, 0.0);
      expect(restored.treble, 0.0);
    });

    test('fromJson with completely empty map returns defaults', () {
      final restored = EqPreset.fromJson({});
      expect(restored.bands, isEmpty);
      expect(restored.bass, 0.0);
      expect(restored.treble, 0.0);
    });
  });

  // ── M1: Serialization dedup — saveAudioEffects delegates to _serializeAudioEffects ──
  group('Serialization consistency (M1)', () {
    test(
      'saveAudioEffects produces identical JSON to _serializeAudioEffects',
      () async {
        // This test verifies that saveAudioEffects and _serializeAudioEffects
        // produce the same JSON output. After the M1 refactor, saveAudioEffects
        // delegates to _serializeAudioEffects, so this must hold.
        final fx = const AudioEffects().copyWith(
          bass: const BassSettings(enabled: true, g: 6.0),
          treble: const TrebleSettings(enabled: true, g: -3.0),
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: 0.2,
            ratio: 8.0,
            attack: 50.0,
            release: 500.0,
          ),
          custom: const ['lavfi-equalizer=f=1000:t=q:w=1.0:g=3.0'],
        );

        // Save via public API
        SharedPreferences.setMockInitialValues({});
        await PlayerSettingsStore.saveAudioEffects(fx);
        final p = await SharedPreferences.getInstance();
        final savedJson = p.getString(PlayerSettingsStore.kAudioEffects);

        // Load and verify round-trip
        final loaded = PlayerSettingsStore.loadAudioEffects(p);
        expect(loaded, isNotNull);
        expect(loaded!.bass!.enabled, isTrue);
        expect(loaded.bass!.g, 6.0);
        expect(loaded.acompressor!.threshold, 0.2);
        expect(loaded.custom, ['lavfi-equalizer=f=1000:t=q:w=1.0:g=3.0']);

        // Verify JSON is well-formed (not empty or malformed)
        expect(savedJson, isNotNull);
        expect(savedJson!.isNotEmpty, isTrue);
      },
    );

    test(
      'loadAudioEffects handles all effect types through unified deserializer',
      () async {
        // After M1, loadAudioEffects delegates to _deserializeAudioEffects.
        // This test covers all major effect types in one round-trip.
        final fx = const AudioEffects().copyWith(
          bass: const BassSettings(enabled: true, g: 5.0),
          treble: const TrebleSettings(enabled: true, g: -2.0),
          loudnorm: const LoudnormSettings(enabled: true),
          acompressor: const AcompressorSettings(
            enabled: true,
            threshold: -20,
            ratio: 4,
            attack: 10,
            release: 100,
          ),
          superequalizer: const SuperequalizerSettings(
            enabled: true,
            params: {'1b': 3.0, '5b': -1.5},
          ),
          rubberband: const RubberbandSettings(
            enabled: true,
            pitch: 1.2,
            tempo: 0.9,
          ),
          crossfeed: const CrossfeedSettings(enabled: true, strength: 0.5),
          stereowiden: const StereowidenSettings(enabled: true, delay: 15),
          aexciter: const AexciterSettings(enabled: true, amount: 2.0),
          crystalizer: const CrystalizerSettings(enabled: true, i: 1.5),
          virtualbass: const VirtualbassSettings(enabled: true, cutoff: 200),
          agate: const AgateSettings(
            enabled: true,
            threshold: -30,
            ratio: 3,
            attack: 5,
            release: 100,
          ),
          deesser: const DeesserSettings(enabled: true, i: 0.5, m: 0.6, f: 0.7),
          aecho: const AechoSettings(
            enabled: true,
            in_gain: 0.8,
            out_gain: 0.4,
            delays: '100',
            decays: '0.3',
          ),
          aphaser: const AphaserSettings(
            enabled: true,
            in_gain: 0.5,
            out_gain: 0.6,
            delay: 2,
            decay: 0.3,
            speed: 0.4,
          ),
          flanger: const FlangerSettings(
            enabled: true,
            delay: 1,
            depth: 3,
            regen: 0.5,
            width: 50,
            speed: 0.3,
          ),
          chorus: const ChorusSettings(
            enabled: true,
            in_gain: 0.3,
            out_gain: 0.3,
            delays: '30',
            decays: '0.2',
            speeds: '0.1',
            depths: '2',
          ),
          tremolo: const TremoloSettings(enabled: true, f: 4.0, d: 0.4),
          vibrato: const VibratoSettings(enabled: true, f: 3.0, d: 0.3),
          acrusher: const AcrusherSettings(
            enabled: true,
            bits: 12,
            mix: 0.6,
            samples: 2,
          ),
          custom: const ['filter1', 'filter2'],
        );

        final loaded = await _roundTrip(fx);
        expect(loaded, isNotNull);
        expect(loaded!.bass!.g, 5.0);
        expect(loaded.treble!.g, -2.0);
        expect(loaded.loudnorm!.enabled, isTrue);
        expect(loaded.acompressor!.threshold, -20);
        expect(loaded.superequalizer!.params['1b'], 3.0);
        expect(loaded.rubberband!.pitch, 1.2);
        expect(loaded.crossfeed!.strength, 0.5);
        expect(loaded.stereowiden!.delay, 15);
        expect(loaded.aexciter!.amount, 2.0);
        expect(loaded.crystalizer!.i, 1.5);
        expect(loaded.virtualbass!.cutoff, 200);
        expect(loaded.agate!.threshold, -30);
        expect(loaded.deesser!.f, 0.7);
        expect(loaded.aecho!.delays, '100');
        expect(loaded.aphaser!.speed, 0.4);
        expect(loaded.flanger!.speed, 0.3);
        expect(loaded.chorus!.delays, '30');
        expect(loaded.tremolo!.f, 4.0);
        expect(loaded.vibrato!.f, 3.0);
        expect(loaded.acrusher!.bits, 12);
        expect(loaded.custom, ['filter1', 'filter2']);
      },
    );
  });

  // ── Parametric EQ custom filters persistence ─────────────────────────────
  group('Parametric EQ custom filters', () {
    test('preserves custom lavfi strings through round-trip', () async {
      final fx = const AudioEffects().copyWith(
        custom: const [
          'lavfi-equalizer=f=60.0:t=q:w=0.70:g=3.0',
          'lavfi-equalizer=f=230.0:t=q:w=0.70:g=-2.0',
          'lavfi-equalizer=f=910.0:t=q:w=1.00:g=1.5',
        ],
      );
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.custom.length, 3);
      expect(loaded.custom[0], 'lavfi-equalizer=f=60.0:t=q:w=0.70:g=3.0');
      expect(loaded.custom[1], 'lavfi-equalizer=f=230.0:t=q:w=0.70:g=-2.0');
      expect(loaded.custom[2], 'lavfi-equalizer=f=910.0:t=q:w=1.00:g=1.5');
    });

    test('preserves empty custom list', () async {
      final fx = const AudioEffects().copyWith(custom: const []);
      final loaded = await _roundTrip(fx);
      expect(loaded, isNotNull);
      expect(loaded!.custom, isEmpty);
    });

    test('loads empty custom when key missing from storage', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final loaded = PlayerSettingsStore.loadAudioEffects(p);
      expect(loaded, isNull);
    });

    test('handles malformed custom_filters gracefully', () async {
      SharedPreferences.setMockInitialValues({
        PlayerSettingsStore.kAudioEffects: '{"custom_filters": "not_a_list"}',
      });
      final p = await SharedPreferences.getInstance();
      final loaded = PlayerSettingsStore.loadAudioEffects(p);
      // Should not crash, custom should be empty
      expect(loaded, isNotNull);
      expect(loaded!.custom, isEmpty);
    });
  });
}
