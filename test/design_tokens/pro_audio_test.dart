import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/design_tokens/pro_audio.dart';

void main() {
  group('ProAudioColors', () {
    group('EQ curve', () {
      test('curveActive is gold #FFD700', () {
        expect(ProAudioColors.curveActive.toARGB32(), 0xFFFFD700);
      });

      test('curveGlow is 20% gold', () {
        expect(ProAudioColors.curveGlow.toARGB32(), 0x33FFD700);
      });

      test('curveInactive is 30% white', () {
        expect(ProAudioColors.curveInactive.toARGB32(), 0x4DFFFFFF);
      });
    });

    group('band colors (frequency-coded)', () {
      test('bandLow is red', () {
        const c = ProAudioColors.bandLow;
        expect(c.r, greaterThan(c.b));
        expect(c.r, greaterThan(c.g));
      });

      test('bandHigh is blue', () {
        const c = ProAudioColors.bandHigh;
        expect(c.b, greaterThan(c.r));
        expect(c.b, greaterThan(c.g));
      });
    });

    group('meter zones', () {
      test('meterGreen, meterYellow, meterRed are distinct', () {
        expect(ProAudioColors.meterGreen, isNot(ProAudioColors.meterYellow));
        expect(ProAudioColors.meterYellow, isNot(ProAudioColors.meterRed));
        expect(ProAudioColors.meterGreen, isNot(ProAudioColors.meterRed));
      });
    });

    group('state colors', () {
      test('activeNode is white', () {
        expect(ProAudioColors.activeNode.toARGB32(), 0xFFFFFFFF);
      });

      test('accentFocus is light blue', () {
        expect(ProAudioColors.accentFocus.toARGB32(), 0xFF64B5F6);
      });
    });
  });

  group('ProAudioTypography', () {
    test('readout uses JetBrains Mono 13px', () {
      const style = ProAudioTypography.readout;
      expect(style.fontFamily, 'JetBrains Mono');
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w500);
    });
  });
}
