import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aetherfin/core/smart_playlist/smart_playlist_db.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/smart_playlist/smart_playlist_edit_screen.dart';
import 'package:aetherfin/state/providers.dart';

class MockSmartPlaylistDb extends Mock implements SmartPlaylistDb {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createContainer({SmartPlaylistDb? db}) {
    return ProviderContainer(
      overrides: [
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),
        smartPlaylistDbProvider.overrideWithValue(db ?? MockSmartPlaylistDb()),
      ],
    );
  }

  group('SmartPlaylistEditScreen', () {
    testWidgets('renders without crashing in create mode', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistEditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SmartPlaylistEditScreen), findsOneWidget);
    });

    testWidgets('shows "New Smart Playlist" title in create mode', (
      tester,
    ) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistEditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Smart Playlist'), findsOneWidget);
    });

    testWidgets('name field is present', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistEditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsAtLeastNWidgets(1));
    });

    testWidgets('add rule button exists', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistEditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add rule'), findsOneWidget);
    });

    testWidgets('match mode segmented button (All/Any) exists', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistEditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Any'), findsOneWidget);
    });

    testWidgets('save button exists', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistEditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('back button exists', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistEditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('section labels are visible', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistEditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Match mode'), findsOneWidget);
      expect(find.text('Rules'), findsOneWidget);
      expect(find.text('Sort & limit'), findsOneWidget);
    });
  });
}
