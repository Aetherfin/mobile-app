import 'package:aetherfin/utils/glow_effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlowEffects', () {
    group('glowPaints', () {
      test('returns 3 paint layers (outer, inner, core)', () {
        final paints = GlowEffects.glowPaints(Colors.blue);
        expect(paints, hasLength(3));
        expect(paints[0].strokeWidth, greaterThan(paints[1].strokeWidth));
        expect(paints[1].strokeWidth, greaterThan(paints[2].strokeWidth));
      });

      test('outer glow has lowest opacity', () {
        final paints = GlowEffects.glowPaints(Colors.blue);
        expect(paints[0].color.a, lessThan(paints[1].color.a));
        expect(paints[1].color.a, lessThan(paints[2].color.a));
      });

      test('core paint has full opacity', () {
        final paints = GlowEffects.glowPaints(Colors.blue);
        expect(paints[2].color.a, closeTo(1.0, 0.01));
      });
    });

    group('bandNodePaints', () {
      test('returns list of paints for node layers', () {
        final paints = GlowEffects.bandNodePaints(
          const Color(0xFFFF0000),
          isActive: false,
          isHovered: false,
        );
        expect(paints.length, greaterThanOrEqualTo(3));
      });

      test('active node has larger radius paint', () {
        final activePaints = GlowEffects.bandNodePaints(
          const Color(0xFFFF0000),
          isActive: true,
        );
        final inactivePaints = GlowEffects.bandNodePaints(
          const Color(0xFFFF0000),
          isActive: false,
        );
        expect(
          activePaints[1].strokeWidth,
          greaterThanOrEqualTo(inactivePaints[1].strokeWidth),
        );
      });
    });
  });

  group('BiquadEQ', () {
    test('returns 0 dB at center frequency with 0 dB gain', () {
      final mag = BiquadEQ.peakingEqMagnitude(
        freq: 1000,
        f0: 1000,
        gainDb: 0,
        q: 1.0,
      );
      expect(mag, closeTo(0.0, 0.1));
    });
  });
}
