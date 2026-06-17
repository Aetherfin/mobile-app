import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/models/parametric_eq_state.dart';

void main() {
  group('BandType', () {
    group('serialization', () {
      test('toJsonString returns correct string for each type', () {
        expect(BandType.peak.toJsonString(), 'peak');
        expect(BandType.lowShelf.toJsonString(), 'low_shelf');
        expect(BandType.highShelf.toJsonString(), 'high_shelf');
        expect(BandType.lowCut.toJsonString(), 'low_cut');
        expect(BandType.highCut.toJsonString(), 'high_cut');
      });

      test('fromJsonString parses correct type', () {
        expect(BandType.fromJsonString('peak'), BandType.peak);
        expect(BandType.fromJsonString('low_shelf'), BandType.lowShelf);
        expect(BandType.fromJsonString('high_shelf'), BandType.highShelf);
        expect(BandType.fromJsonString('low_cut'), BandType.lowCut);
        expect(BandType.fromJsonString('high_cut'), BandType.highCut);
      });

      test('fromJsonString returns null for unknown type', () {
        expect(BandType.fromJsonString('unknown'), isNull);
        expect(BandType.fromJsonString(''), isNull);
      });
    });
  });

  group('ParametricEqState', () {
    // ── Constructor defaults ──────────────────────────────────────────────
    group('defaults', () {
      test('creates with 18 default bands', () {
        final state = ParametricEqState();
        expect(state.bands.length, 18);
      });

      test('all bands default to peak type', () {
        final state = ParametricEqState();
        for (final band in state.bands) {
          expect(band.type, BandType.peak);
        }
      });

      test('all bands default to disabled', () {
        final state = ParametricEqState();
        for (final band in state.bands) {
          expect(band.enabled, false);
        }
      });

      test('ISO 1/3 octave frequency spacing', () {
        final state = ParametricEqState();
        expect(state.bands[0].frequency, 25.0);
        expect(state.bands[1].frequency, 31.5);
        expect(state.bands.last.frequency, closeTo(20000.0, 1.0));
      });

      test('maxBands is 18', () {
        expect(ParametricEqState.maxBands, 18);
      });
    });

    // ── setBand / addBand ────────────────────────────────────────────────
    group('setBand / addBand', () {
      test('setBand replaces band at index', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 100.0,
            gain: 3.0,
            q: 1.0,
            type: BandType.peak,
            enabled: true,
          ),
        );
        expect(state.bands[0].frequency, 100.0);
        expect(state.bands[0].gain, 3.0);
        expect(state.bands[0].enabled, true);
      });

      test('addBand adds new enabled band with defaults', () {
        final state = ParametricEqState();
        final initialCount = state.bands.length;
        state.addBand();
        expect(state.bands.length, initialCount + 1);
        expect(state.bands.last.enabled, true);
        expect(state.bands.last.type, BandType.peak);
      });

      test('removeBand removes band at index', () {
        final state = ParametricEqState();
        final initialCount = state.bands.length;
        state.removeBand(0);
        expect(state.bands.length, initialCount - 1);
      });

      test('removeBand does nothing when only 1 band remains', () {
        final state = ParametricEqState();
        state.bands.removeRange(1, state.bands.length);
        state.removeBand(0);
        expect(state.bands.length, 1);
      });

      test('toggleBand enables/disables band', () {
        final state = ParametricEqState();
        expect(state.bands[0].enabled, false);
        state.toggleBand(0);
        expect(state.bands[0].enabled, true);
        state.toggleBand(0);
        expect(state.bands[0].enabled, false);
      });
    });

    // ── JSON round-trip ──────────────────────────────────────────────────
    group('toJson / fromJson', () {
      test('round-trips default state', () {
        final original = ParametricEqState();
        final json = original.toJson();
        final restored = ParametricEqState.fromJson(json);
        expect(restored.bands.length, 18);
      });

      test('round-trips with modified bands', () {
        final original = ParametricEqState();
        original.setBand(
          0,
          const ParametricEqBand(
            frequency: 100.0,
            gain: 5.0,
            q: 2.0,
            type: BandType.lowShelf,
            enabled: true,
          ),
        );
        original.setBand(
          5,
          const ParametricEqBand(
            frequency: 1000.0,
            gain: -3.0,
            q: 1.5,
            type: BandType.highCut,
            enabled: true,
          ),
        );

        final json = original.toJson();
        final restored = ParametricEqState.fromJson(json);

        expect(restored.bands[0].frequency, 100.0);
        expect(restored.bands[0].gain, 5.0);
        expect(restored.bands[0].q, 2.0);
        expect(restored.bands[0].type, BandType.lowShelf);
        expect(restored.bands[0].enabled, true);

        expect(restored.bands[5].frequency, 1000.0);
        expect(restored.bands[5].gain, -3.0);
        expect(restored.bands[5].type, BandType.highCut);
      });

      test('serializes to valid JSON string', () {
        final state = ParametricEqState();
        final jsonStr = jsonEncode(state.toJson());
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        expect(decoded['bands'], isA<List<dynamic>>());
        expect((decoded['bands'] as List).length, 18);
      });

      test('handles missing type in JSON gracefully', () {
        final json = {
          'bands': [
            {'frequency': 1000, 'gain': 3.0, 'q': 1.0, 'enabled': true},
          ],
        };
        final state = ParametricEqState.fromJson(json);
        expect(state.bands[0].type, BandType.peak);
      });

      test('handles empty bands list', () {
        final json = {'bands': []};
        final state = ParametricEqState.fromJson(json);
        expect(state.bands, isEmpty);
      });
    });

    // ── toLavfiStrings ───────────────────────────────────────────────────
    group('toLavfiStrings', () {
      test('generates lavfi strings for enabled bands only', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 3.0,
            q: 1.0,
            type: BandType.peak,
            enabled: true,
          ),
        );
        state.setBand(
          1,
          const ParametricEqBand(
            frequency: 2000,
            gain: -2.0,
            q: 0.7,
            type: BandType.peak,
            enabled: false,
          ),
        );

        final lavfi = state.toLavfiStrings();
        expect(lavfi.length, 1);
        expect(lavfi[0], contains('1000'));
      });

      test('peak type generates lavfi-equalizer', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 3.0,
            q: 1.0,
            type: BandType.peak,
            enabled: true,
          ),
        );

        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], startsWith('lavfi-equalizer='));
        expect(lavfi[0], contains('f=1000'));
        expect(lavfi[0], contains('g=3'));
      });

      test('lowShelf type generates lavfi-bass', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 200,
            gain: 6.0,
            q: 0.7,
            type: BandType.lowShelf,
            enabled: true,
          ),
        );

        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], startsWith('lavfi-bass='));
        expect(lavfi[0], contains('f=200'));
        expect(lavfi[0], contains('g=6'));
      });

      test('highShelf type generates lavfi-treble', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 8000,
            gain: 4.0,
            q: 0.7,
            type: BandType.highShelf,
            enabled: true,
          ),
        );

        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], startsWith('lavfi-treble='));
        expect(lavfi[0], contains('f=8000'));
        expect(lavfi[0], contains('g=4'));
      });

      test('lowCut type generates lavfi-highpass without gain', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 80,
            gain: 0.0,
            q: 0.707,
            type: BandType.lowCut,
            enabled: true,
          ),
        );

        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], startsWith('lavfi-highpass='));
        expect(lavfi[0], contains('f=80'));
        expect(lavfi[0], isNot(contains('g=')));
      });

      test('highCut type generates lavfi-lowpass without gain', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 12000,
            gain: 0.0,
            q: 0.707,
            type: BandType.highCut,
            enabled: true,
          ),
        );

        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], startsWith('lavfi-lowpass='));
        expect(lavfi[0], contains('f=12000'));
        expect(lavfi[0], isNot(contains('g=')));
      });

      test('skips bands with near-zero gain', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 0.03,
            q: 1.0,
            type: BandType.peak,
            enabled: true,
          ),
        );

        final lavfi = state.toLavfiStrings();
        expect(lavfi, isEmpty);
      });

      test('returns empty list when no bands enabled', () {
        final state = ParametricEqState();
        expect(state.toLavfiStrings(), isEmpty);
      });
    });

    // ── toAudioEffects ───────────────────────────────────────────────────
    group('toAudioEffects', () {
      test('injects lavfi strings into custom filters', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 3.0,
            q: 1.0,
            type: BandType.peak,
            enabled: true,
          ),
        );

        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.custom.length, 1);
        expect(fx.custom[0], contains('lavfi-equalizer'));
      });

      test('preserves existing custom filters', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 3.0,
            q: 1.0,
            type: BandType.peak,
            enabled: true,
          ),
        );

        const existing = AudioEffects(custom: ['existing-filter']);
        final fx = state.toAudioEffects(existing);
        expect(fx.custom.length, 2);
        expect(fx.custom, contains('existing-filter'));
      });

      test('preserves other audio effects', () {
        final state = ParametricEqState();
        const existing = AudioEffects(
          bass: BassSettings(enabled: true, g: 5.0),
        );
        final fx = state.toAudioEffects(existing);
        expect(fx.bass.enabled, true);
        expect(fx.bass.g, 5.0);
      });

      test('empty custom when no enabled bands', () {
        final state = ParametricEqState();
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.custom, isEmpty);
      });
    });

    // ── fromCustomFilters ────────────────────────────────────────────────
    group('fromCustomFilters', () {
      test('parses lavfi-equalizer strings', () {
        final state = ParametricEqState.fromCustomFilters([
          'lavfi-equalizer=f=1000:t=q:w=1.0:g=3.0',
          'lavfi-equalizer=f=2000:t=q:w=0.7:g=-2.0',
        ]);
        expect(state.bands.length, 2);
        expect(state.bands[0].frequency, 1000);
        expect(state.bands[0].gain, 3.0);
        expect(state.bands[0].q, 1.0);
        expect(state.bands[0].type, BandType.peak);
        expect(state.bands[1].frequency, 2000);
        expect(state.bands[1].gain, -2.0);
      });

      test('parses lavfi-bass as lowShelf', () {
        final state = ParametricEqState.fromCustomFilters([
          'lavfi-bass=f=200:t=q:w=0.7:g=6',
        ]);
        expect(state.bands.length, 1);
        expect(state.bands[0].type, BandType.lowShelf);
        expect(state.bands[0].frequency, 200);
        expect(state.bands[0].gain, 6.0);
      });

      test('parses lavfi-treble as highShelf', () {
        final state = ParametricEqState.fromCustomFilters([
          'lavfi-treble=f=8000:t=q:w=0.7:g=4',
        ]);
        expect(state.bands.length, 1);
        expect(state.bands[0].type, BandType.highShelf);
        expect(state.bands[0].frequency, 8000);
      });

      test('parses lavfi-highpass as lowCut', () {
        final state = ParametricEqState.fromCustomFilters([
          'lavfi-highpass=f=80:t=q:w=0.707',
        ]);
        expect(state.bands.length, 1);
        expect(state.bands[0].type, BandType.lowCut);
        expect(state.bands[0].frequency, 80);
      });

      test('parses lavfi-lowpass as highCut', () {
        final state = ParametricEqState.fromCustomFilters([
          'lavfi-lowpass=f=12000:t=q:w=0.707',
        ]);
        expect(state.bands.length, 1);
        expect(state.bands[0].type, BandType.highCut);
        expect(state.bands[0].frequency, 12000);
      });

      test('skips unknown filter strings', () {
        final state = ParametricEqState.fromCustomFilters([
          'unknown-filter=value',
          'lavfi-equalizer=f=1000:t=q:w=1.0:g=3.0',
        ]);
        expect(state.bands.length, 1);
      });

      test('handles empty list by falling back to default state', () {
        final state = ParametricEqState.fromCustomFilters([]);
        // When no parametric EQ filters are found, falls back to the
        // default 18-band state so the UI always has bands to display.
        expect(state.bands, hasLength(ParametricEqState.maxBands));
      });
    });

    // ── Edge cases / boundaries ──────────────────────────────────────────
    group('edge cases', () {
      test('handles minimum frequency (20 Hz)', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 20.0,
            gain: 3.0,
            q: 0.3,
            type: BandType.peak,
            enabled: true,
          ),
        );
        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], contains('f=20'));
      });

      test('handles maximum frequency (20000 Hz)', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 20000,
            gain: 3.0,
            q: 12.0,
            type: BandType.peak,
            enabled: true,
          ),
        );
        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], contains('f=20000'));
      });

      test('handles minimum Q (0.3)', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 3.0,
            q: 0.3,
            type: BandType.peak,
            enabled: true,
          ),
        );
        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], contains('w=0.3'));
      });

      test('handles maximum Q (12.0)', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 3.0,
            q: 12.0,
            type: BandType.peak,
            enabled: true,
          ),
        );
        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], contains('w=12'));
      });

      test('handles max gain (+12 dB)', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 12.0,
            q: 1.0,
            type: BandType.peak,
            enabled: true,
          ),
        );
        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], contains('g=12'));
      });

      test('handles max negative gain (-24 dB)', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: -24.0,
            q: 1.0,
            type: BandType.peak,
            enabled: true,
          ),
        );
        final lavfi = state.toLavfiStrings();
        expect(lavfi[0], contains('g=-24'));
      });

      test('gain of exactly 0.05 is active', () {
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 0.05,
            q: 1.0,
            type: BandType.peak,
            enabled: true,
          ),
        );
        final lavfi = state.toLavfiStrings();
        expect(lavfi, isNotEmpty);
      });
    });

    // ── Persistence round-trip ───────────────────────────────────────────
    group('persistence round-trip', () {
      test('toAudioEffects -> fromCustomFilters preserves bands', () {
        final original = ParametricEqState();
        original.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 3.0,
            q: 1.5,
            type: BandType.peak,
            enabled: true,
          ),
        );
        original.setBand(
          1,
          const ParametricEqBand(
            frequency: 200,
            gain: 6.0,
            q: 0.7,
            type: BandType.lowShelf,
            enabled: true,
          ),
        );

        final fx = original.toAudioEffects(const AudioEffects());
        final restored = ParametricEqState.fromCustomFilters(fx.custom);

        expect(restored.bands.length, 2);
        expect(restored.bands[0].frequency, 1000);
        expect(restored.bands[0].gain, 3.0);
        expect(restored.bands[0].type, BandType.peak);
        expect(restored.bands[1].type, BandType.lowShelf);
        expect(restored.bands[1].frequency, 200);
      });
    });
  });
}
