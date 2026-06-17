import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/smart_playlist/smart_playlist_model.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/playlist/playlist_list_screen.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createContainer({
    List<AfPlaylist> playlists = const [],
    AppMode? mode,
  }) {
    return ProviderContainer(
      overrides: [
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),
        appModeProvider.overrideWith(
          () => StateHolder<AppMode?>((ref) => mode),
        ),
        musicBackendProvider.overrideWith((ref) => null),
        allPlaylistsProvider.overrideWith((ref) => playlists),
        smartPlaylistsProvider.overrideWith((ref) => const <SmartPlaylist>[]),
      ],
    );
  }

  group('PlaylistListScreen', () {
    testWidgets('renders without crashing', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlaylistListScreen), findsOneWidget);
    });

    testWidgets('shows title "Playlists"', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Playlists'), findsOneWidget);
    });

    testWidgets('empty state when no playlists', (tester) async {
      final container = createContainer(playlists: const []);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No playlists yet'), findsOneWidget);
    });

    testWidgets('lists playlist cards when data provided', (tester) async {
      final playlists = [
        const AfPlaylist(id: 'pl-1', name: 'My Favorites', trackCount: 12),
        const AfPlaylist(id: 'pl-2', name: 'Workout Mix', trackCount: 25),
      ];
      final container = createContainer(playlists: playlists);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Favorites'), findsOneWidget);
      expect(find.text('Workout Mix'), findsOneWidget);
    });

    testWidgets('import M3U button exists', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Import M3U'), findsOneWidget);
    });

    testWidgets('shows "My Playlists" section when playlists exist', (
      tester,
    ) async {
      final playlists = [
        const AfPlaylist(id: 'pl-1', name: 'Chill Vibes', trackCount: 8),
      ];
      final container = createContainer(playlists: playlists);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PlaylistListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Playlists'), findsOneWidget);
    });
  });
}
