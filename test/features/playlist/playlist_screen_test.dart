import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/playlist/playlist_screen.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createFixture({
    ({AfPlaylist playlist, List<AfTrack> tracks})? detail,
  }) {
    return ProviderContainer(
      overrides: [
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),
        musicBackendProvider.overrideWith((ref) => null),
        currentTrackProvider.overrideWith(
          () => StateHolder<AfTrack?>((ref) => null),
        ),
        playlistDetailProvider.overrideWith((ref, id) async => detail),
      ],
    );
  }

  group('PlaylistScreen', () {
    testWidgets('renders loading skeleton initially', (tester) async {
      final fixture = createFixture();
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture,
          child: const MaterialApp(home: PlaylistScreen(playlistId: 'test-pl')),
        ),
      );
      // pump once — async provider still loading, shows PlaylistSkeleton
      await tester.pump();

      expect(find.byType(PlaylistScreen), findsOneWidget);
    });

    testWidgets('displays playlist name when loaded', (tester) async {
      final detail = (
        playlist: const AfPlaylist(
          id: 'pl-1',
          name: 'My Favorites',
          trackCount: 3,
        ),
        tracks: <AfTrack>[],
      );
      final fixture = createFixture(detail: detail);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture,
          child: const MaterialApp(home: PlaylistScreen(playlistId: 'pl-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Favorites'), findsWidgets);
    });

    testWidgets('shows track count in header', (tester) async {
      final detail = (
        playlist: const AfPlaylist(id: 'pl-1', name: 'Rock Mix', trackCount: 5),
        tracks: List.generate(
          5,
          (i) => AfTrack(
            id: 't-$i',
            title: 'Track $i',
            artistName: 'Artist',
            albumName: 'Album',
            duration: const Duration(minutes: 3),
          ),
        ),
      );
      final fixture = createFixture(detail: detail);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture,
          child: const MaterialApp(home: PlaylistScreen(playlistId: 'pl-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('5 tracks'), findsOneWidget);
    });

    testWidgets('play button exists', (tester) async {
      const detail = (
        playlist: AfPlaylist(id: 'pl-1', name: 'Test', trackCount: 1),
        tracks: [
          AfTrack(
            id: 't-1',
            title: 'Song',
            artistName: 'Artist',
            albumName: 'Album',
            duration: Duration(minutes: 3),
          ),
        ],
      );
      final fixture = createFixture(detail: detail);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture,
          child: const MaterialApp(home: PlaylistScreen(playlistId: 'pl-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('shuffle button exists', (tester) async {
      const detail = (
        playlist: AfPlaylist(id: 'pl-1', name: 'Test', trackCount: 1),
        tracks: [
          AfTrack(
            id: 't-1',
            title: 'Song',
            artistName: 'Artist',
            albumName: 'Album',
            duration: Duration(minutes: 3),
          ),
        ],
      );
      final fixture = createFixture(detail: detail);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture,
          child: const MaterialApp(home: PlaylistScreen(playlistId: 'pl-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shuffle'), findsOneWidget);
    });

    testWidgets('null playlist shows "not found"', (tester) async {
      final fixture = createFixture(detail: null);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture,
          child: const MaterialApp(home: PlaylistScreen(playlistId: 'missing')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Playlist not found'), findsOneWidget);
    });

    testWidgets('track list renders when data provided', (tester) async {
      const detail = (
        playlist: AfPlaylist(id: 'pl-1', name: 'Songs', trackCount: 2),
        tracks: [
          AfTrack(
            id: 't-1',
            title: 'First Song',
            artistName: 'Artist A',
            albumName: 'Album A',
            duration: Duration(minutes: 3),
          ),
          AfTrack(
            id: 't-2',
            title: 'Second Song',
            artistName: 'Artist B',
            albumName: 'Album B',
            duration: Duration(minutes: 4),
          ),
        ],
      );
      final fixture = createFixture(detail: detail);
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture,
          child: const MaterialApp(home: PlaylistScreen(playlistId: 'pl-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('First Song'), findsOneWidget);
      expect(find.text('Second Song'), findsOneWidget);
    });
  });
}
