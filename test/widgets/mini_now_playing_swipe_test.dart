import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Logarithmic sensitivity function — mirrors _MiniPlayerContentState.
double _logSensitivity(double dx) => dx / (1 + math.exp(-0.05 * dx));

void main() {
  group('logarithmic sensitivity', () {
    test('near-zero input returns near-zero output', () {
      expect(_logSensitivity(0), closeTo(0, 0.01));
    });

    test('small positive input returns dampened output', () {
      expect(_logSensitivity(10), closeTo(6.22, 0.5));
    });

    test('large positive input returns near-linear output', () {
      expect(_logSensitivity(200), closeTo(200, 1));
    });

    test('negative input dampens magnitude (not symmetric)', () {
      expect(_logSensitivity(-50), closeTo(-3.79, 0.5));
    });
  });
}
