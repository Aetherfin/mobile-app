import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/audio/models/parametric_eq_state.dart';

void main() {
  group('ParametricEqState', () {
    // ── Constructor defaults ──────────────────────────────────────────────
    group('defaults', () {
      test('creates with 18 default bands', () {
        final state = ParametricEqState();
        expect(state.bands.length, 18);
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
    });
  });
}
