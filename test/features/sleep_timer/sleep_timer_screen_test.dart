import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/sleep_timer/sleep_timer_screen.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Minimal container for SleepTimerScreen: spectral + timer providers.
  ProviderContainer createSleepContainer({
    DateTime? activeTimer,
    Duration? remaining,
  }) {
    return ProviderContainer(
      overrides: [
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),
        appModeProvider.overrideWith(
          () => StateHolder<AppMode?>((ref) => AppMode.local),
        ),
        musicBackendProvider.overrideWith((ref) => null),
        sleepTimerProvider.overrideWith(
          () => StateHolder<DateTime?>((ref) => activeTimer),
        ),
        sleepTimerRemainingProvider.overrideWith(
          () => StateHolder<Duration?>((ref) => remaining),
        ),
      ],
    );
  }

  group('SleepTimerScreen', () {
    testWidgets('renders without crashing', (tester) async {
      final container = createSleepContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SleepTimerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SleepTimerScreen), findsOneWidget);
    });

    testWidgets('displays "Sleep timer" title', (tester) async {
      final container = createSleepContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SleepTimerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sleep timer'), findsOneWidget);
    });

    testWidgets('shows preset chips (5, 10, 15, 30, 45, 60)', (tester) async {
      final container = createSleepContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SleepTimerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('60 min'), findsOneWidget);
    });

    testWidgets('shows "End of track" option', (tester) async {
      final container = createSleepContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SleepTimerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('End of track'), findsOneWidget);
    });

    testWidgets('shows "Pick a time" button initially', (tester) async {
      final container = createSleepContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SleepTimerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pick a time'), findsOneWidget);
    });

    testWidgets('shows description text when no timer active', (tester) async {
      final container = createSleepContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SleepTimerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pause playback after a set time.'), findsOneWidget);
    });

    testWidgets('selecting a preset shows "Set timer" button', (tester) async {
      final container = createSleepContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SleepTimerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the 15 min chip
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();

      expect(find.text('Set timer'), findsOneWidget);
    });

    testWidgets('active timer shows countdown card', (tester) async {
      final target = DateTime.now().add(const Duration(minutes: 30));
      final container = createSleepContainer(
        activeTimer: target,
        remaining: const Duration(minutes: 30),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SleepTimerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Pausing in'), findsOneWidget);
    });
  });
}
