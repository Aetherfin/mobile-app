import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/now_playing/backgrounds/blur_background.dart';
import 'package:aetherfin/features/now_playing/backgrounds/gradient_background.dart';
import 'package:aetherfin/features/now_playing/backgrounds/glow_background.dart';
import 'package:aetherfin/features/now_playing/backgrounds/solid_background.dart';
import 'package:aetherfin/state/settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testEnergy = Color(0xFF2E6FA8);

  Widget wrapInApp(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox.expand(child: child)),
  );

  group('GradientBackground', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        wrapInApp(
          const GradientBackground(
            energy: testEnergy,
            child: Text('gradient content'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('gradient content'), findsOneWidget);
    });

    testWidgets('renders Container with gradient decoration', (tester) async {
      await tester.pumpWidget(
        wrapInApp(
          const GradientBackground(energy: testEnergy, child: SizedBox()),
        ),
      );
      await tester.pump();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GradientBackground),
          matching: find.byType(Container),
        ),
      );
      expect(container.decoration, isA<BoxDecoration>());
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());
    });
  });

  group('BlurBackground', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        wrapInApp(
          const BlurBackground(energy: testEnergy, child: Text('blur content')),
        ),
      );
      await tester.pump();

      expect(find.text('blur content'), findsOneWidget);
    });

    testWidgets('contains BackdropFilter for blur effect', (tester) async {
      await tester.pumpWidget(
        wrapInApp(const BlurBackground(energy: testEnergy, child: SizedBox())),
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('wraps in RepaintBoundary for performance', (tester) async {
      await tester.pumpWidget(
        wrapInApp(const BlurBackground(energy: testEnergy, child: SizedBox())),
      );
      await tester.pump();

      // BlurBackground contains a RepaintBoundary as direct child
      expect(
        find.descendant(
          of: find.byType(BlurBackground),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
    });
  });

  group('GlowBackground', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        wrapInApp(
          const GlowBackground(energy: testEnergy, child: Text('glow content')),
        ),
      );
      await tester.pump();

      expect(find.text('glow content'), findsOneWidget);
    });

    testWidgets('has animation controller for pulse effect', (tester) async {
      await tester.pumpWidget(
        wrapInApp(const GlowBackground(energy: testEnergy, child: SizedBox())),
      );
      await tester.pump();

      // GlowBackground uses AnimatedBuilder which indicates animation
      expect(
        find.descendant(
          of: find.byType(GlowBackground),
          matching: find.byType(AnimatedBuilder),
        ),
        findsOneWidget,
      );
    });
  });

  group('SolidBackground', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        wrapInApp(
          const SolidBackground(
            energy: testEnergy,
            child: Text('solid content'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('solid content'), findsOneWidget);
    });

    testWidgets('renders Container with solid color', (tester) async {
      await tester.pumpWidget(
        wrapInApp(const SolidBackground(energy: testEnergy, child: SizedBox())),
      );
      await tester.pump();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(SolidBackground),
          matching: find.byType(Container),
        ),
      );
      expect(container.color, isNotNull);
      expect(container.color, isNot(AfColors.surfaceCanvas));
    });
  });

  group('PlayerBackgroundStyle enum', () {
    test('has all 5 expected values', () {
      const values = PlayerBackgroundStyle.values;
      expect(values.length, 5);
      expect(values, contains(PlayerBackgroundStyle.gradient));
      expect(values, contains(PlayerBackgroundStyle.blur));
      expect(values, contains(PlayerBackgroundStyle.glow));
      expect(values, contains(PlayerBackgroundStyle.solid));
      expect(values, contains(PlayerBackgroundStyle.blurGradient));
    });
  });
}
