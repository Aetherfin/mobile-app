import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/album/album_screen.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

import '../../helpers/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({ProviderContainer container}) buildAlbumContainer({
    AfAlbum? album,
    List<AfTrack> tracks = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        currentSpectralProvider.overrideWithValue(Spectral.fallback),
        musicBackendProvider.overrideWith((ref) => null),
        appModeProvider.overrideWith(
          () => StateHolder<AppMode?>((ref) => AppMode.local),
        ),
        albumDetailProvider('test-album').overrideWithValue(
          AsyncData<({AfAlbum album, List<AfTrack> tracks})?>(
            album != null ? (album: album, tracks: tracks) : null,
          ),
        ),
      ],
    );
    return (container: container);
  }

  /// Scrolls past the hero artwork.
  Future<void> scrollPastHero(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
  }

  group('AlbumScreen', () {
    // Run non-scroll tests first.
    testWidgets('null album shows "Album not found"', (tester) async {
      final fixture = buildAlbumContainer();
      addTearDown(fixture.container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: AlbumScreen(albumId: 'missing')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Album not found'), findsOneWidget);
    });

    testWidgets('displays album title and artist when loaded', (tester) async {
      final fixture = buildAlbumContainer(
        album: createTestAlbum(name: 'Thriller', artistName: 'Michael Jackson'),
        tracks: [
          createTestTrack(title: 'Wanna Be Startin\' Somethin\''),
          createTestTrack(id: 't2', title: 'Thriller'),
        ],
      );
      addTearDown(fixture.container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: AlbumScreen(albumId: 'test-album')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await scrollPastHero(tester);

      expect(find.text('Thriller'), findsWidgets);
      expect(find.text('Michael Jackson'), findsOneWidget);
    });

    testWidgets('shows track list with correct count', (tester) async {
      final tracks = createTestTrackList(count: 5);
      final fixture = buildAlbumContainer(
        album: createTestAlbum(trackCount: 5),
        tracks: tracks,
      );
      addTearDown(fixture.container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: AlbumScreen(albumId: 'test-album')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await scrollPastHero(tester);

      for (final track in tracks) {
        expect(find.text(track.title), findsOneWidget);
      }
    });

    testWidgets('Play All button exists', (tester) async {
      final fixture = buildAlbumContainer(
        album: createTestAlbum(),
        tracks: createTestTrackList(count: 2),
      );
      addTearDown(fixture.container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: AlbumScreen(albumId: 'test-album')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await scrollPastHero(tester);

      expect(find.text('Play All'), findsOneWidget);
    });

    testWidgets('Shuffle button exists', (tester) async {
      final fixture = buildAlbumContainer(
        album: createTestAlbum(),
        tracks: createTestTrackList(count: 2),
      );
      addTearDown(fixture.container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: AlbumScreen(albumId: 'test-album')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await scrollPastHero(tester);

      expect(find.text('Shuffle'), findsOneWidget);
    });

    testWidgets('track row renders title', (tester) async {
      final fixture = buildAlbumContainer(
        album: createTestAlbum(),
        tracks: [
          createTestTrack(
            title: 'My Song',
            duration: const Duration(minutes: 4, seconds: 30),
          ),
        ],
      );
      addTearDown(fixture.container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: AlbumScreen(albumId: 'test-album')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await scrollPastHero(tester);

      expect(find.text('My Song'), findsOneWidget);
    });
  });
}
