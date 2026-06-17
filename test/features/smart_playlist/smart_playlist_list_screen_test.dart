import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/smart_playlist/smart_playlist_model.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/smart_playlist/smart_playlist_list_screen.dart';
import 'package:aetherfin/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createContainer({List<SmartPlaylist>? playlists}) {
    return ProviderContainer(
      overrides: [
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),
        smartPlaylistsProvider.overrideWith(
          (ref) => playlists ?? const <SmartPlaylist>[],
        ),
      ],
    );
  }

  group('SmartPlaylistListScreen', () {
    testWidgets('renders without crashing', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SmartPlaylistListScreen), findsOneWidget);
    });

    testWidgets('shows title "Smart Playlists"', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Smart Playlists'), findsOneWidget);
    });

    testWidgets('empty state when no playlists', (tester) async {
      final container = createContainer(playlists: const []);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No smart playlists yet'), findsOneWidget);
    });

    testWidgets('FAB button exists for creating new', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('lists playlist cards when data provided', (tester) async {
      final playlists = [
        SmartPlaylist(
          id: 'sp-1',
          name: 'Favorite Rock',
          rules: const [
            SmartRule(field: 'genre', operator: 'is', value: 'Rock'),
          ],
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
        ),
        SmartPlaylist(
          id: 'sp-2',
          name: 'Recent Jazz',
          rules: const [
            SmartRule(field: 'genre', operator: 'is', value: 'Jazz'),
          ],
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
        ),
      ];
      final container = createContainer(playlists: playlists);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Favorite Rock'), findsOneWidget);
      expect(find.text('Recent Jazz'), findsOneWidget);
    });

    testWidgets('shows rule summary for each playlist', (tester) async {
      final playlists = [
        SmartPlaylist(
          id: 'sp-1',
          name: 'Rock Only',
          rules: const [
            SmartRule(field: 'genre', operator: 'is', value: 'Rock'),
          ],
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
        ),
      ];
      final container = createContainer(playlists: playlists);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SmartPlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Genre is Rock'), findsOneWidget);
    });
  });
}
