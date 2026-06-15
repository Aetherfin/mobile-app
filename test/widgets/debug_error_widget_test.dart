import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:aetherfin/widgets/debug_error_widget.dart';

void main() {
  group('DebugErrorWidget', () {
    const testException = 'TestException: something broke';
    final testDetails = FlutterErrorDetails(
      exception: Exception(testException),
      stack: StackTrace.fromString(
        '#0      SomeClass.method (package:aetherfin/some/file.dart:42:12)\n'
        '#1      AnotherClass.build (package:aetherfin/other/file.dart:99:8)\n'
        '#2      nextFrame (dart:ui)\n',
      ),
    );

    /// Wrap with MaterialApp so the widget has inherited context.
    Widget buildTestWidget() =>
        MaterialApp(home: DebugErrorWidget(details: testDetails));

    testWidgets('renders error title', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Aetherfin hit a snag'), findsOneWidget);
    });

    testWidgets('shows copy button', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byIcon(LucideIcons.clipboard), findsOneWidget);
    });

    testWidgets('copy button is tappable without crashing', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(LucideIcons.clipboard));
      await tester.pump();

      // No crash = widget handles missing Scaffold gracefully
      expect(find.byIcon(LucideIcons.clipboard), findsOneWidget);
    });

    testWidgets('shows info text for retry in debug mode', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(
        find.text('Hot reload to retry after fixing the issue.'),
        findsOneWidget,
      );
    });

    testWidgets('has surface canvas background', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final canvasBoxes = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF0A0B0E),
      );
      expect(canvasBoxes, findsAtLeast(1));
    });
  });
}
