import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Motion tokens — non-negotiable §4.2', () {
    test('exactly five duration tiers exist', () {
      final tiers = {
        AfDurations.instant,
        AfDurations.quick,
        AfDurations.standard,
        AfDurations.expressive,
        AfDurations.long,
      };
      expect(tiers, hasLength(5));
    });

    test('durations match the spec exactly — no 200/300/500 ms', () {
      expect(AfDurations.instant.inMilliseconds, 80);
      expect(AfDurations.quick.inMilliseconds, 160);
      expect(AfDurations.standard.inMilliseconds, 240);
      expect(AfDurations.expressive.inMilliseconds, 400);
      expect(AfDurations.long.inMilliseconds, 600);
    });

    test('exactly five easing curves are exposed', () {
      // Linear is intentionally the same Curves.linear instance, but we
      // still expose it under our token namespace so audio-coupled UIs
      // import from a single surface.
      expect(const [
        AfCurves.easeStandard,
        AfCurves.easeEmphasized,
        AfCurves.easeOut,
        AfCurves.easeIn,
        AfCurves.linear,
      ], hasLength(5));
    });
  });

  group('Color tokens — non-negotiable §4.1', () {
    test('indigo scale uses exact spec hex values', () {
      // Spot-check the anchors documented in aetherfin-design.md §2.
      expect(AfColors.indigo50.toARGB32(),  0xFFEEF2FF);
      expect(AfColors.indigo600.toARGB32(), 0xFF4F46E5);
      expect(AfColors.indigo900.toARGB32(), 0xFF1E1B4B);
      expect(AfColors.surfaceCanvas.toARGB32(), 0xFF08090C);
      expect(AfColors.surfaceRaised.toARGB32(), 0xFF1C202B);
    });
  });

  group('Spacing — non-negotiable §4.1', () {
    test('48dp minimum hit target everywhere', () {
      expect(AfSpacing.minHitTarget, 48);
    });
    test('floating mini-player is 56dp tall, 12dp side margin, 16dp gap', () {
      expect(AfSpacing.miniPlayerHeight, 56);
      expect(AfSpacing.miniPlayerSideMargin, 12);
      expect(AfSpacing.miniPlayerNavGap, 16);
    });
  });
}
