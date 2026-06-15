import 'package:aetherfin/widgets/spring_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper: find the innermost Transform inside a SpringChip.
/// SpringChip's tree: GestureDetector → AnimatedBuilder → Transform → AnimatedContainer
Transform _findChipTransform(WidgetTester tester) {
  final candidates = tester.widgetList<Transform>(
    find.descendant(
      of: find.byType(SpringChip),
      matching: find.byType(Transform),
    ),
  );
  return candidates.last;
}

void main() {
  group('SpringChip', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpringChip(label: 'Albums', isSelected: false, onTap: _noop),
          ),
        ),
      );
      expect(find.text('Albums'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpringChip(
              label: 'Songs',
              isSelected: false,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Songs'));
      expect(tapped, isTrue);
    });

    testWidgets('scales down on press', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpringChip(label: 'Artists', isSelected: false, onTap: _noop),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Artists')),
      );
      // Pump several frames with explicit duration so spring simulation ticks
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final matrix = _findChipTransform(tester).transform;
      // Spring is animating from 1.0 toward 0.92 — scale < 1.0
      expect(matrix[0], lessThan(1.0));

      await gesture.up();
    });

    testWidgets('scales up when selected', (tester) async {
      var selected = false;
      late void Function() toggle;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                toggle = () => setState(() => selected = !selected);
                return SpringChip(
                  label: 'Genres',
                  isSelected: selected,
                  onTap: toggle,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      // Let initial spring settle at 1.0
      await tester.pump(const Duration(milliseconds: 500));

      // Directly toggle isSelected to true (no press animation)
      toggle();
      // Pump enough frames for the spring to move from 1.0 toward 1.05
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final matrix = _findChipTransform(tester).transform;
      // Spring has moved from 1.0 toward 1.05 — scale > 1.0
      expect(matrix[0], greaterThan(1.0));
    });

    testWidgets('transitions color when selected', (tester) async {
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SpringChip(
                  label: 'Songs',
                  isSelected: selected,
                  onTap: () => setState(() => selected = true),
                  selectedColor: Colors.red,
                  unselectedColor: Colors.grey,
                );
              },
            ),
          ),
        ),
      );

      // Unselected state
      var container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(SpringChip),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((container.decoration as BoxDecoration).color, Colors.grey);

      // Tap to select
      await tester.tap(find.text('Songs'));
      await tester.pump(const Duration(milliseconds: 200));

      container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(SpringChip),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((container.decoration as BoxDecoration).color, Colors.red);
    });

    testWidgets('applies default colors when not provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpringChip(label: 'Test', isSelected: true, onTap: _noop),
          ),
        ),
      );

      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(SpringChip),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.borderRadius, isNotNull);
    });

    testWidgets('press then release restores scale to 1.0 when unselected', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpringChip(label: 'Test', isSelected: false, onTap: _noop),
          ),
        ),
      );

      // Press down
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Test')),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_findChipTransform(tester).transform[0], lessThan(1.0));

      // Release — spring returns to 1.0
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_findChipTransform(tester).transform[0], closeTo(1.0, 0.05));
    });
  });
}

void _noop() {}
