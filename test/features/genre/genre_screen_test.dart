import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/genre/genre_screen.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

import '../../helpers/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Minimal container for GenreScreen: spectral + backend + genre albums.
  ProviderContainer createGenreContainer({List<AfAlbum> albums = const []}) {
    return ProviderContainer(
      overrides: [
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),
        musicBackendProvider.overrideWith((ref) => null),
        appModeProvider.overrideWith(
          () => StateHolder<AppMode?>((ref) => AppMode.local),
        ),
        genreAlbumsProvider.overrideWith((ref, arg) async => albums),
      ],
    );
  }

  group('GenreScreen', () {
    testWidgets('renders without crashing', (tester) async {
      final container = createGenreContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GenreScreen(genre: 'Rock')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GenreScreen), findsOneWidget);
    });

    testWidgets('displays genre name in title', (tester) async {
      final container = createGenreContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GenreScreen(genre: 'Jazz')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jazz'), findsWidgets);
    });

    testWidgets('shows album count subtitle when data loaded', (tester) async {
      final albums = createTestAlbumList(count: 3);
      final container = createGenreContainer(albums: albums);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GenreScreen(genre: 'Rock')),
        ),
      );
      await tester.pumpAndSettle();

      // Should show "3 albums" in the subtitle
      expect(find.textContaining('3 albums'), findsOneWidget);
    });

    testWidgets('renders album grid when albums provided', (tester) async {
      final albums = createTestAlbumList(count: 2);
      final container = createGenreContainer(albums: albums);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GenreScreen(genre: 'Rock')),
        ),
      );
      await tester.pumpAndSettle();

      // Albums section header + individual album names
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Album 1'), findsOneWidget);
      expect(find.text('Album 2'), findsOneWidget);
    });

    testWidgets('shows "No albums in this genre" when empty', (tester) async {
      final container = createGenreContainer(albums: const []);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GenreScreen(genre: 'Polka')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No albums in this genre'), findsOneWidget);
    });

    testWidgets('shows "No albums" in subtitle when empty', (tester) async {
      final container = createGenreContainer(albums: const []);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GenreScreen(genre: 'Polka')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No albums'), findsOneWidget);
    });

    testWidgets('artists section renders when artists exist', (tester) async {
      final albums = [
        createTestAlbum(artistName: 'Artist A'),
        createTestAlbum(id: 'album-2', artistName: 'Artist B'),
      ];
      final container = createGenreContainer(albums: albums);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GenreScreen(genre: 'Rock')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Artist A'), findsWidgets);
      expect(find.text('Artist B'), findsWidgets);
    });

    testWidgets('shows correct artist count subtitle', (tester) async {
      final albums = [
        createTestAlbum(artistName: 'A'),
        createTestAlbum(id: 'a2', artistName: 'A'),
        createTestAlbum(id: 'a3', artistName: 'B'),
      ];
      final container = createGenreContainer(albums: albums);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GenreScreen(genre: 'Rock')),
        ),
      );
      await tester.pumpAndSettle();

      // 3 albums, 2 artists (A appears twice but deduped)
      expect(find.textContaining('2 artists'), findsOneWidget);
    });
  });
}
