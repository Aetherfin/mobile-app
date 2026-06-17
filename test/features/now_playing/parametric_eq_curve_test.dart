import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/features/now_playing/parametric_band.dart';
import 'package:aetherfin/features/now_playing/parametric_eq_curve.dart';

void main() {
  group('ParametricEqCurvePainter', () {
    late List<ParametricBand> bands;

    setUp(() {
      bands = ParametricBand.defaultBands();
    });

    test('xToFrequency converts position 0 to 20 Hz', () {
      expect(ParametricEqCurvePainter.xToFrequency(0, 400), closeTo(20, 0.1));
    });

    test('xToFrequency converts position 1.0 to 20000 Hz', () {
      final freq = ParametricEqCurvePainter.xToFrequency(400, 400);
      expect(freq, closeTo(20000, 1));
    });

    test('xToFrequency returns correct logarithmic values', () {
      final freq = ParametricEqCurvePainter.xToFrequency(200, 400);
      expect(freq, greaterThan(200));
      expect(freq, lessThan(1000));
    });

    test('frequencyToX converts 20 Hz to position 0', () {
      expect(ParametricEqCurvePainter.frequencyToX(20, 400), closeTo(0, 0.1));
    });

    test('frequencyToX converts 20000 Hz to position width', () {
      expect(
        ParametricEqCurvePainter.frequencyToX(20000, 400),
        closeTo(400, 0.1),
      );
    });

    test('peakingEqGain returns 0 at center frequency', () {
      final gain = ParametricEqCurvePainter.peakingEqGain(1000, 1000, 6, 1.0);
      expect(gain, closeTo(6.0, 0.1));
    });

    test('peakingEqGain returns near 0 far from center frequency', () {
      final gain = ParametricEqCurvePainter.peakingEqGain(20, 1000, 6, 1.0);
      expect(gain.abs(), lessThan(0.5));
    });

    test('peakingEqGain returns 0 for zero gain', () {
      final gain = ParametricEqCurvePainter.peakingEqGain(1000, 1000, 0, 1.0);
      expect(gain, 0.0);
    });

    test('calculateResponse returns correct length', () {
      final response = ParametricEqCurvePainter.calculateResponse(bands, 400);
      expect(response.length, 400);
    });

    test('calculateResponse returns zeros for flat bands', () {
      final response = ParametricEqCurvePainter.calculateResponse(bands, 100);
      for (final g in response) {
        expect(g, 0.0);
      }
    });

    test('calculateResponse returns boost for boosted band', () {
      bands = List.generate(5, ParametricBand.defaultAt);
      bands[2] = const ParametricBand(frequency: 910, gain: 6.0, q: 1.0);
      final response = ParametricEqCurvePainter.calculateResponse(bands, 400);
      final centerIdx = ParametricEqCurvePainter.frequencyToX(910, 400).toInt();
      expect(response[centerIdx], greaterThan(3.0));
    });

    test('calculateResponse returns cut for cut band', () {
      bands = List.generate(5, ParametricBand.defaultAt);
      bands[2] = const ParametricBand(frequency: 910, gain: -6.0, q: 1.0);
      final response = ParametricEqCurvePainter.calculateResponse(bands, 400);
      final centerIdx = ParametricEqCurvePainter.frequencyToX(910, 400).toInt();
      expect(response[centerIdx], lessThan(-3.0));
    });

    test('calculateResponse clamps to ±24 dB', () {
      bands = List.generate(5, ParametricBand.defaultAt);
      bands[2] = const ParametricBand(frequency: 910, gain: 24.0, q: 1.0);
      final response = ParametricEqCurvePainter.calculateResponse(bands, 400);
      for (final g in response) {
        expect(g, lessThanOrEqualTo(24.0));
        expect(g, greaterThanOrEqualTo(-24.0));
      }
    });
  });
}
