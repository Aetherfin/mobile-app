import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/state/app_mode_providers.dart';
import 'package:aetherfin/state/music_backend_providers.dart';
import 'package:aetherfin/state/search_providers.dart';
import 'package:aetherfin/state/state_holder.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockMusicBackend extends Mock implements MusicBackend {}

// ── Helpers ──────────────────────────────────────────────────────────────────

AfTrack _track(String id, {String? title}) => AfTrack(
  id: id,
  title: title ?? 'Track $id',
  artistName: 'Artist',
  albumName: 'Album',
);

AfAlbum _album(String id, {String? name}) => AfAlbum(
  id: id,
  name: name ?? 'Album $id',
  artistName: 'Artist',
  trackCount: 10,
);

AfArtist _artist(String id, {String? name}) =>
    AfArtist(id: id, name: name ?? 'Artist $id');

AfPlaylist _playlist(String id, {String? name}) =>
    AfPlaylist(id: id, name: name ?? 'Playlist $id', trackCount: 5);

ProviderContainer _createContainer({AppMode? appMode, MusicBackend? backend}) {
  return ProviderContainer(
    overrides: [
      appModeProvider.overrideWith(
        () => StateHolder<AppMode?>((ref) => appMode),
      ),
      musicBackendProvider.overrideWithValue(backend),
    ],
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(_track('fallback'));
  });

  group('searchProvider', () {
    test('empty query returns empty results', () async {
      final mockBackend = MockMusicBackend();
      final container = _createContainer(
        appMode: AppMode.server,
        backend: mockBackend,
      );
      addTearDown(container.dispose);

      final result = await container.read(searchProvider('').future);

      expect(result.tracks, isEmpty);
      expect(result.albums, isEmpty);
      verifyNever(() => mockBackend.search(any()));
    });

    test('whitespace-only query returns empty results', () async {
      final mockBackend = MockMusicBackend();
      final container = _createContainer(
        appMode: AppMode.server,
        backend: mockBackend,
      );
      addTearDown(container.dispose);

      final result = await container.read(searchProvider('   ').future);

      expect(result.tracks, isEmpty);
      verifyNever(() => mockBackend.search(any()));
    });

    test('trims whitespace from query before searching', () async {
      final mockBackend = MockMusicBackend();
      when(() => mockBackend.search(any())).thenAnswer(
        (_) async => (
          tracks: <AfTrack>[],
          albums: <AfAlbum>[],
          artists: <AfArtist>[],
          playlists: <AfPlaylist>[],
        ),
      );

      final container = _createContainer(
        appMode: AppMode.server,
        backend: mockBackend,
      );
      addTearDown(container.dispose);

      await container.read(searchProvider('  beatles  ').future);

      verify(() => mockBackend.search('beatles')).called(1);
    });

    test('delegates to backend.search in server mode', () async {
      final mockBackend = MockMusicBackend();
      when(() => mockBackend.search(any())).thenAnswer(
        (_) async => (
          tracks: [_track('1'), _track('2')],
          albums: [_album('a1')],
          artists: [_artist('ar1')],
          playlists: [_playlist('p1')],
        ),
      );

      final container = _createContainer(
        appMode: AppMode.server,
        backend: mockBackend,
      );
      addTearDown(container.dispose);

      final result = await container.read(searchProvider('beatles').future);

      expect(result.tracks, hasLength(2));
      expect(result.albums, hasLength(1));
      expect(result.artists, hasLength(1));
      expect(result.playlists, hasLength(1));
      verify(() => mockBackend.search('beatles')).called(1);
    });

    test('lyricsCacheProvider starts empty', () {
      final container = _createContainer(
        appMode: AppMode.server,
        backend: MockMusicBackend(),
      );
      addTearDown(container.dispose);

      final cache = container.read(lyricsCacheProvider);
      expect(cache, isEmpty);
    });
  });
}
