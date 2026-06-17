import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/features/now_playing/parametric_presets.dart';

void main() {
  group('kParametricPresets', () {
    test('has at least 6 built-in presets', () {
      expect(kParametricPresets.length, greaterThanOrEqualTo(6));
    });

    test('contains Flat preset', () {
      expect(kParametricPresets.containsKey('Flat'), true);
    });

    test('Flat preset has all zero gains', () {
      final flat = kParametricPresets['Flat']!;
      for (final band in flat.bands) {
        expect(band.gain, 0.0);
      }
    });

    test('Flat preset has 10 bands', () {
      final flat = kParametricPresets['Flat']!;
      expect(flat.bands.length, 10);
    });

    test('all presets have valid gain values', () {
      for (final entry in kParametricPresets.entries) {
        for (final band in entry.value.bands) {
          expect(band.gain, greaterThanOrEqualTo(-24));
          expect(band.gain, lessThanOrEqualTo(24));
        }
      }
    });

    test('all presets have valid band frequencies', () {
      for (final entry in kParametricPresets.entries) {
        for (final band in entry.value.bands) {
          expect(band.frequency, greaterThanOrEqualTo(20));
          expect(band.frequency, lessThanOrEqualTo(20000));
        }
      }
    });
  });
}
