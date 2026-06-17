import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/utils/audio_scales.dart';

void main() {
  group('AudioScales', () {
    group('freqToNormalized', () {
      test('20 Hz maps to 0.0', () {
        expect(AudioScales.freqToNormalized(20), closeTo(0.0, 1e-10));
      });

      test('20000 Hz maps to 1.0', () {
        expect(AudioScales.freqToNormalized(20000), closeTo(1.0, 1e-10));
      });

      test('clamps below 20 Hz to 0.0', () {
        expect(AudioScales.freqToNormalized(10), 0.0);
      });

      test('clamps above 20000 Hz to 1.0', () {
        expect(AudioScales.freqToNormalized(50000), 1.0);
      });
    });

    group('normalizedToFreq', () {
      test('round-trips through freqToNormalized', () {
        const freqs = [20.0, 50.0, 100.0, 500.0, 1000.0, 5000.0, 20000.0];
        for (final freq in freqs) {
          final normalized = AudioScales.freqToNormalized(freq);
          final roundTripped = AudioScales.normalizedToFreq(normalized);
          expect(roundTripped, closeTo(freq, 0.01));
        }
      });

      test('clamps below 0.0 to 20 Hz', () {
        expect(AudioScales.normalizedToFreq(-0.5), closeTo(20, 1e-10));
      });
    });

    group('dB / multiplier conversion', () {
      test('0 dB = 1.0 multiplier', () {
        expect(AudioScales.dbToMultiplier(0), closeTo(1.0, 1e-10));
      });

      test('-6 dB ≈ 0.5 multiplier', () {
        expect(AudioScales.dbToMultiplier(-6), closeTo(0.5, 0.01));
      });

      test('+6 dB ≈ 2.0 multiplier', () {
        expect(AudioScales.dbToMultiplier(6), closeTo(2.0, 0.01));
      });

      test('round-trips multiplier → dB → multiplier', () {
        const multipliers = [0.25, 0.5, 0.707, 1.0, 1.414, 2.0, 4.0];
        for (final m in multipliers) {
          final db = AudioScales.multiplierToDb(m);
          final roundTripped = AudioScales.dbToMultiplier(db);
          expect(roundTripped, closeTo(m, 1e-6));
        }
      });
    });

    group('dB ↔ Y coordinate mapping', () {
      const height = 200.0;
      const dbRange = 12.0;

      test('0 dB maps to center', () {
        expect(AudioScales.dbToY(0, height, dbRange: dbRange), height / 2);
      });

      test('round-trips through yToDb', () {
        const dbs = [-12.0, -6.0, 0.0, 3.0, 6.0, 12.0];
        for (final db in dbs) {
          final y = AudioScales.dbToY(db, height, dbRange: dbRange);
          final roundTripped = AudioScales.yToDb(y, height, dbRange: dbRange);
          expect(roundTripped, closeTo(db, 1e-10));
        }
      });
    });
  });
}
