import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/lyrics/lrc_parser.dart';
import 'package:aetherfin/core/local/local_library.dart';
import 'package:aetherfin/state/app_mode_providers.dart';
import 'package:aetherfin/state/local_library_providers.dart';
import 'package:aetherfin/state/music_backend_providers.dart';
import 'package:aetherfin/state/search_providers.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockMusicBackend extends Mock implements MusicBackend {}

class MockLocalLibrary extends Mock implements LocalLibrary {}

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

/// Creates a container with common overrides for search provider tests.
///
/// [appMode] sets the app mode (server vs local).
/// [backend] provides the music backend (null = signed out).
/// [localLibrary] provides the local library mock for local mode.
ProviderContainer _createContainer({
  AppMode? appMode,
  MusicBackend? backend,
  LocalLibrary? localLibrary,
}) {
  final overrides = [
    appModeProvider.overrideWith((ref) => appMode),
    musicBackendProvider.overrideWithValue(backend),
  ];
  if (localLibrary != null) {
    overrides.add(localLibraryProvider.overrideWithValue(localLibrary));
  }
  return ProviderContainer(overrides: overrides);
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
      expect(result.artists, isEmpty);
      expect(result.playlists, isEmpty);

      // Backend should NOT be called for empty queries
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
      expect(result.albums, isEmpty);
      verifyNever(() => mockBackend.search(any()));
    });

    test('no backend returns empty results in server mode', () async {
      final container = _createContainer(
        appMode: AppMode.server,
        backend: null,
      );
      addTearDown(container.dispose);

      final result = await container.read(searchProvider('test query').future);

      expect(result.tracks, isEmpty);
      expect(result.albums, isEmpty);
      expect(result.artists, isEmpty);
      expect(result.playlists, isEmpty);
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
      expect(result.tracks[0].id, '1');
      expect(result.albums, hasLength(1));
      expect(result.albums[0].id, 'a1');
      expect(result.artists, hasLength(1));
      expect(result.playlists, hasLength(1));

      verify(() => mockBackend.search('beatles')).called(1);
    });

    test('delegates to localLibrary.search in local mode', () async {
      final mockLibrary = MockLocalLibrary();
      when(
        () => mockLibrary.search(any()),
      ).thenAnswer((_) async => [_track('local-1'), _track('local-2')]);

      final container = _createContainer(
        appMode: AppMode.local,
        backend: null,
        localLibrary: mockLibrary,
      );
      addTearDown(container.dispose);

      final result = await container.read(searchProvider('jazz').future);

      expect(result.tracks, hasLength(2));
      expect(result.tracks[0].id, 'local-1');
      // Local mode returns only tracks (no albums/artists/playlists)
      expect(result.albums, isEmpty);
      expect(result.artists, isEmpty);
      expect(result.playlists, isEmpty);

      verify(() => mockLibrary.search('jazz')).called(1);
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

    test('backend error propagates as AsyncError', () async {
      final mockBackend = MockMusicBackend();
      when(() => mockBackend.search(any())).thenThrow(Exception('server down'));

      final container = _createContainer(
        appMode: AppMode.server,
        backend: mockBackend,
      );
      addTearDown(container.dispose);

      // In riverpod 3.x, FutureProvider.autoDispose wraps errors from the
      // builder in a ProviderException (which is an Error, not an Exception).
      // The .future getter re-throws whatever the provider settled with.
      expect(
        () => container.read(searchProvider('test').future),
        throwsA(anything),
      );
    });

    test('local library error propagates as AsyncError', () async {
      final mockLibrary = MockLocalLibrary();
      when(
        () => mockLibrary.search(any()),
      ).thenThrow(Exception('db corrupted'));

      final container = _createContainer(
        appMode: AppMode.local,
        backend: null,
        localLibrary: mockLibrary,
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(searchProvider('test').future),
        throwsA(anything),
      );
    });
  });

  // ── M2: Lyrics cache ──────────────────────────────────────────────────────
  group('lyricsCacheProvider', () {
    test('starts empty', () {
      final container = _createContainer(
        appMode: AppMode.server,
        backend: MockMusicBackend(),
      );
      addTearDown(container.dispose);

      final cache = container.read(lyricsCacheProvider);
      expect(cache, isEmpty);
    });

    test('can store and retrieve cached lyrics', () {
      final container = _createContainer(
        appMode: AppMode.server,
        backend: MockMusicBackend(),
      );
      addTearDown(container.dispose);

      const result = LyricsResult(lrc: Lrc(), source: LyricsSource.server);

      // Populate cache
      container.read(lyricsCacheProvider.notifier).state = {'track1': result};

      // Verify cache hit
      final cache = container.read(lyricsCacheProvider);
      expect(cache['track1'], result);
      expect(cache.length, 1);
    });

    test('cache persists across reads (not autoDispose)', () {
      final container = _createContainer(
        appMode: AppMode.server,
        backend: MockMusicBackend(),
      );
      addTearDown(container.dispose);

      const result = LyricsResult(lrc: Lrc(), source: LyricsSource.netease);

      // Populate cache
      container.read(lyricsCacheProvider.notifier).state = {'track1': result};

      // Read again — cache should still have the entry
      final cache = container.read(lyricsCacheProvider);
      expect(cache['track1'], result);
    });
  });
}
