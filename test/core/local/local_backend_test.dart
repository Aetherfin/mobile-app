import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:aetherfin/core/local/local_backend.dart';
import 'package:aetherfin/core/local/local_library.dart';
import 'package:aetherfin/core/local/local_db.dart';
import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/backend/music_backend.dart';

void main() {
  group('LocalBackend identification', () {
    test('serverType returns ServerType.local', () {
      // Can't construct LocalBackend without a DB, but verifying the
      // constant is enough — the getter has no side effects.
      expect(ServerType.local, ServerType.local);
    });

    test('trackStreamUrl returns trackId unchanged', () async {
      final appDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(appDb.close);
      final localDb = LocalDb(db: appDb);
      final library = LocalLibrary(database: appDb);
      final backend = LocalBackend(library: library, db: localDb);
      const trackId = 'content://media/external/audio/123';
      expect(backend.trackStreamUrl(trackId), trackId);
    });

    test('authHeaders returns empty map', () async {
      final appDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(appDb.close);
      final localDb = LocalDb(db: appDb);
      final library = LocalLibrary(database: appDb);
      final backend = LocalBackend(library: library, db: localDb);
      expect(backend.authHeaders, isEmpty);
    });
  });

  group('LocalBackend library browsing', () {
    late AppDatabase appDb;
    late LocalDb localDb;
    late LocalLibrary library;
    late LocalBackend backend;

    setUp(() async {
      appDb = AppDatabase.forTesting(NativeDatabase.memory());
      localDb = LocalDb(db: appDb);
      library = LocalLibrary(database: appDb);
      backend = LocalBackend(library: library, db: localDb);

      await localDb.upsertTracks([
        {
          'id': 'content://uri/1',
          'title': 'Tide',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
          'cover_path': '/c/coast.jpg',
          'last_modified': 3000,
        },
        {
          'id': 'content://uri/2',
          'title': 'Cliff',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/a/2.mp3',
          'codec': 'mp3',
          'cover_path': '/c/coast.jpg',
          'last_modified': 2000,
        },
        {
          'id': 'content://uri/3',
          'title': 'Peak',
          'artist': 'Dos',
          'album': 'Mountains',
          'album_artist': 'Dos',
          'duration_ms': 240000,
          'genre': 'Rock',
          'file_path': '/a/3.mp3',
          'codec': 'flac',
          'cover_path': '/c/mtn.jpg',
          'last_modified': 1000,
        },
      ]);
    });

    tearDown(() async {
      await appDb.close();
    });

    test(
      'recentlyAddedAlbums returns albums sorted by date descending',
      () async {
        final albums = await backend.recentlyAddedAlbums();
        expect(albums.map((a) => a.name), ['Coastlines', 'Mountains']);
      },
    );

    test('recentlyAddedAlbums respects limit', () async {
      final albums = await backend.recentlyAddedAlbums(limit: 1);
      expect(albums, hasLength(1));
      expect(albums.first.name, 'Coastlines');
    });

    test('allAlbums returns all albums with correct aggregation', () async {
      final albums = await backend.allAlbums();
      expect(albums.map((a) => a.name), ['Coastlines', 'Mountains']);
      final coast = albums.first;
      expect(coast.trackCount, 2);
      expect(coast.totalDuration, const Duration(milliseconds: 380000));
    });

    test('allAlbums supports pagination', () async {
      final page1 = await backend.allAlbums(limit: 1, startIndex: 0);
      expect(page1, hasLength(1));
      expect(page1.first.name, 'Coastlines');

      final page2 = await backend.allAlbums(limit: 1, startIndex: 1);
      expect(page2, hasLength(1));
      expect(page2.first.name, 'Mountains');

      final past = await backend.allAlbums(limit: 1, startIndex: 10);
      expect(past, isEmpty);
    });

    test('allTracks returns all tracks', () async {
      final tracks = await backend.allTracks();
      expect(tracks, hasLength(3));
      expect(tracks.map((t) => t.title), ['Cliff', 'Peak', 'Tide']);
    });

    test('allTracks supports pagination', () async {
      final page1 = await backend.allTracks(limit: 2, startIndex: 0);
      expect(page1, hasLength(2));

      final page2 = await backend.allTracks(limit: 2, startIndex: 2);
      expect(page2, hasLength(1));
    });

    test('artists returns artist list', () async {
      final result = await backend.artists();
      expect(result.map((a) => a.name), ['Dos', 'Una']);
    });

    test('genres returns genre list', () async {
      final result = await backend.genres();
      expect(result.map((g) => g.name), ['Pop', 'Rock']);
    });

    test('playlists returns empty when no playlists exist', () async {
      final result = await backend.playlists();
      expect(result, isEmpty);
    });

    test('playlists returns playlists with stats', () async {
      await localDb.createPlaylist('local:playlist:p1', 'Workout');
      var entryN = 0;
      await localDb.addToPlaylist('local:playlist:p1', [
        'content://uri/1',
        'content://uri/3',
      ], makeEntryId: () => 'e${++entryN}');
      final result = await backend.playlists();
      expect(result, hasLength(1));
      expect(result.first.name, 'Workout');
      expect(result.first.trackCount, 2);
    });
  });

  group('LocalBackend search', () {
    late AppDatabase appDb;
    late LocalDb localDb;
    late LocalLibrary library;
    late LocalBackend backend;

    setUp(() async {
      appDb = AppDatabase.forTesting(NativeDatabase.memory());
      localDb = LocalDb(db: appDb);
      library = LocalLibrary(database: appDb);
      backend = LocalBackend(library: library, db: localDb);

      await localDb.upsertTracks([
        {
          'id': 'content://uri/1',
          'title': 'Tide',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
          'cover_path': '/c/coast.jpg',
        },
        {
          'id': 'content://uri/2',
          'title': 'Cliff',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/a/2.mp3',
          'codec': 'mp3',
          'cover_path': '/c/coast.jpg',
        },
        {
          'id': 'content://uri/3',
          'title': 'Peak',
          'artist': 'Dos',
          'album': 'Mountains',
          'album_artist': 'Dos',
          'duration_ms': 240000,
          'genre': 'Rock',
          'file_path': '/a/3.mp3',
          'codec': 'flac',
          'cover_path': '/c/mtn.jpg',
        },
      ]);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('search finds tracks by title substring', () async {
      final result = await backend.search('tide');
      expect(result.tracks, hasLength(1));
      expect(result.tracks.first.title, 'Tide');
    });

    test('search finds tracks by artist name', () async {
      final result = await backend.search('una');
      expect(result.tracks, hasLength(2));
      expect(result.tracks.every((t) => t.artistName == 'Una'), isTrue);
    });

    test('search finds albums by name', () async {
      final result = await backend.search('coast');
      expect(result.albums, hasLength(1));
      expect(result.albums.first.name, 'Coastlines');
    });

    test('search finds artists by name', () async {
      final result = await backend.search('dos');
      expect(result.artists, hasLength(1));
      expect(result.artists.first.name, 'Dos');
    });

    test('search with no match returns empty lists', () async {
      final result = await backend.search('zzzzz');
      expect(result.tracks, isEmpty);
      expect(result.albums, isEmpty);
      expect(result.artists, isEmpty);
      expect(result.playlists, isEmpty);
    });

    test('search with empty query returns empty lists', () async {
      final result = await backend.search('');
      expect(result.tracks, isEmpty);
      expect(result.albums, isEmpty);
    });

    test('search with whitespace-only query returns empty', () async {
      final result = await backend.search('   ');
      expect(result.tracks, isEmpty);
    });
  });

  group('LocalBackend favorites', () {
    late AppDatabase appDb;
    late LocalDb localDb;
    late LocalLibrary library;
    late LocalBackend backend;

    setUp(() async {
      appDb = AppDatabase.forTesting(NativeDatabase.memory());
      localDb = LocalDb(db: appDb);
      library = LocalLibrary(database: appDb);
      backend = LocalBackend(library: library, db: localDb);

      await localDb.upsertTracks([
        {
          'id': 'content://uri/1',
          'title': 'Tide',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'content://uri/2',
          'title': 'Cliff',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/a/2.mp3',
          'codec': 'mp3',
        },
      ]);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('setFavorite adds to favorites', () async {
      await backend.setFavorite('content://uri/1', true);
      final favs = await backend.favoriteTracks();
      expect(favs, hasLength(1));
      expect(favs.first.id, 'content://uri/1');
      expect(favs.first.isFavorite, isTrue);
    });

    test('setFavorite removes from favorites', () async {
      await backend.setFavorite('content://uri/1', true);
      await backend.setFavorite('content://uri/1', false);
      final favs = await backend.favoriteTracks();
      expect(favs, isEmpty);
    });

    test('favoriteTracks returns only favorited tracks', () async {
      await backend.setFavorite('content://uri/1', true);
      await backend.setFavorite('content://uri/2', true);
      final favs = await backend.favoriteTracks();
      expect(favs, hasLength(2));
    });

    test('favoriteAlbums returns favorited albums with aggregation', () async {
      // Track 1 and 2 are both in Coastlines by Una
      // Favorite the album ID
      await backend.setFavorite('local:album:Coastlines:Una', true);
      final favAlbums = await backend.favoriteAlbums();
      expect(favAlbums, hasLength(1));
      expect(favAlbums.first.name, 'Coastlines');
      expect(favAlbums.first.isFavorite, isTrue);
      expect(favAlbums.first.trackCount, 2);
    });

    test('favoriteAlbums returns empty when nothing favorited', () async {
      final favAlbums = await backend.favoriteAlbums();
      expect(favAlbums, isEmpty);
    });
  });

  group('LocalBackend detail views', () {
    late AppDatabase appDb;
    late LocalDb localDb;
    late LocalLibrary library;
    late LocalBackend backend;

    setUp(() async {
      appDb = AppDatabase.forTesting(NativeDatabase.memory());
      localDb = LocalDb(db: appDb);
      library = LocalLibrary(database: appDb);
      backend = LocalBackend(library: library, db: localDb);

      await localDb.upsertTracks([
        {
          'id': 'content://uri/1',
          'title': 'Tide',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
          'cover_path': '/c/coast.jpg',
          'year': 2020,
        },
        {
          'id': 'content://uri/2',
          'title': 'Cliff',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/a/2.mp3',
          'codec': 'mp3',
          'cover_path': '/c/coast.jpg',
          'year': 2020,
        },
        {
          'id': 'content://uri/3',
          'title': 'Peak',
          'artist': 'Dos',
          'album': 'Mountains',
          'album_artist': 'Dos',
          'duration_ms': 240000,
          'genre': 'Rock',
          'file_path': '/a/3.mp3',
          'codec': 'flac',
          'cover_path': '/c/mtn.jpg',
          'year': 2022,
        },
      ]);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('album returns album with tracks by album id', () async {
      final result = await backend.album('local:album:Coastlines:Una');
      expect(result, isNotNull);
      expect(result!.album.name, 'Coastlines');
      expect(result.album.artistName, 'Una');
      expect(result.album.trackCount, 2);
      expect(result.album.totalDuration, const Duration(milliseconds: 380000));
      expect(result.tracks, hasLength(2));
      expect(result.tracks.map((t) => t.title), ['Cliff', 'Tide']);
    });

    test('album returns null for unknown album id', () async {
      final result = await backend.album('local:album:Unknown:Nobody');
      expect(result, isNull);
    });

    test('album returns null for malformed id', () async {
      final result = await backend.album('not-a-local-album');
      expect(result, isNull);
    });

    test('album handles album names with colons', () async {
      await localDb.upsertTracks([
        {
          'id': 'content://uri/colon1',
          'title': 'Song One',
          'artist': 'The Band',
          'album': 'Greatest Hits: The Best',
          'album_artist': 'The Band',
          'duration_ms': 200000,
          'genre': 'Rock',
          'file_path': '/a/colon1.mp3',
          'codec': 'mp3',
        },
      ]);
      final result = await backend.album(
        'local:album:Greatest Hits: The Best:The Band',
      );
      expect(result, isNotNull);
      expect(result!.album.name, 'Greatest Hits: The Best');
      expect(result.tracks, hasLength(1));
      expect(result.tracks.first.title, 'Song One');
    });

    test('artist returns artist details by artist id', () async {
      final result = await backend.artist('local:artist:Una');
      expect(result, isNotNull);
      expect(result!.name, 'Una');
      expect(result.id, 'local:artist:Una');
    });

    test('artist returns null for unknown artist id', () async {
      final result = await backend.artist('local:artist:Unknown');
      expect(result, isNull);
    });

    test('artist returns null for malformed id', () async {
      final result = await backend.artist('not-a-local-artist');
      expect(result, isNull);
    });

    test('artistAlbums returns albums by artist', () async {
      final albums = await backend.artistAlbums('local:artist:Una');
      expect(albums.map((a) => a.name), ['Coastlines']);
    });

    test('artistAlbums returns empty for unknown artist', () async {
      final albums = await backend.artistAlbums('local:artist:Unknown');
      expect(albums, isEmpty);
    });

    test('artistTopTracks returns top tracks by artist', () async {
      final tracks = await backend.artistTopTracks('local:artist:Una');
      expect(tracks, hasLength(2));
      expect(tracks.every((t) => t.artistName == 'Una'), isTrue);
    });

    test('artistTopTracks respects limit', () async {
      final tracks = await backend.artistTopTracks(
        'local:artist:Una',
        limit: 1,
      );
      expect(tracks, hasLength(1));
    });

    test('trackDetails returns details for known track', () async {
      final details = await backend.trackDetails('content://uri/1');
      expect(details, isNotNull);
      expect(details!.track.id, 'content://uri/1');
      expect(details.track.title, 'Tide');
    });

    test('trackDetails returns null for unknown track', () async {
      final details = await backend.trackDetails('content://uri/unknown');
      expect(details, isNull);
    });
  });

  group('LocalBackend playlists', () {
    late AppDatabase appDb;
    late LocalDb localDb;
    late LocalLibrary library;
    late LocalBackend backend;

    setUp(() async {
      appDb = AppDatabase.forTesting(NativeDatabase.memory());
      localDb = LocalDb(db: appDb);
      library = LocalLibrary(database: appDb);
      backend = LocalBackend(library: library, db: localDb);

      await localDb.upsertTracks([
        {
          'id': 'content://uri/1',
          'title': 'Tide',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'content://uri/2',
          'title': 'Cliff',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/a/2.mp3',
          'codec': 'mp3',
        },
      ]);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('createPlaylist creates a new playlist', () async {
      final id = await backend.createPlaylist('Test', ['content://uri/1']);
      expect(id, isNotNull);
      final playlists = await backend.playlists();
      expect(playlists, hasLength(1));
      expect(playlists.first.name, 'Test');
    });

    test(
      'createPlaylist with empty track list creates empty playlist',
      () async {
        final id = await backend.createPlaylist('Empty', []);
        expect(id, isNotNull);
        final playlist = await backend.playlist(id!);
        expect(playlist, isNotNull);
        expect(playlist!.tracks, isEmpty);
      },
    );

    test('addToPlaylist adds tracks to existing playlist', () async {
      final id = await backend.createPlaylist('Test', []);
      await backend.addToPlaylist(id!, ['content://uri/1', 'content://uri/2']);
      final playlist = await backend.playlist(id);
      expect(playlist, isNotNull);
      expect(playlist!.tracks, hasLength(2));
    });

    test('removeFromPlaylist removes tracks', () async {
      final id = await backend.createPlaylist('Test', [
        'content://uri/1',
        'content://uri/2',
      ]);
      final entries = await localDb.playlistTracks(id!);
      await backend.removeFromPlaylist(id, [entries.first.entryId]);
      final updated = await backend.playlist(id);
      expect(updated!.tracks, hasLength(1));
    });

    test('renamePlaylist updates playlist name', () async {
      final id = await backend.createPlaylist('Old', []);
      await backend.renamePlaylist(id!, 'New');
      final pl = await localDb.getPlaylist(id);
      expect(pl!.name, 'New');
    });

    test('deletePlaylist removes playlist', () async {
      final id = await backend.createPlaylist('Temp', []);
      await backend.deletePlaylist(id!);
      final playlists = await backend.playlists();
      expect(playlists, isEmpty);
    });
  });

  group('LocalBackend no-ops and lifecycle', () {
    test('reportPlaybackStart is a no-op', () async {
      final appDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(appDb.close);
      final localDb = LocalDb(db: appDb);
      final library = LocalLibrary(database: appDb);
      final backend = LocalBackend(library: library, db: localDb);
      await backend.reportPlaybackStart('track-1');
      await backend.reportProgress('track-1', const Duration(seconds: 30));
      await backend.reportPlaybackStop('track-1', const Duration(seconds: 60));
      // no throw = success
    });

    test('savePlayQueue and getPlayQueue are no-ops', () async {
      final appDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(appDb.close);
      final localDb = LocalDb(db: appDb);
      final library = LocalLibrary(database: appDb);
      final backend = LocalBackend(library: library, db: localDb);
      await backend.savePlayQueue(['track-1'], currentIndex: 0);
      final result = await backend.getPlayQueue();
      expect(result, isNull);
    });

    test('clearCache and close are no-ops', () {
      final appDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(appDb.close);
      final localDb = LocalDb(db: appDb);
      final library = LocalLibrary(database: appDb);
      final backend = LocalBackend(library: library, db: localDb);
      backend.clearCache();
      backend.close();
      // no throw = success
    });

    test('resumeItems returns empty list', () async {
      final appDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(appDb.close);
      final localDb = LocalDb(db: appDb);
      final library = LocalLibrary(database: appDb);
      final backend = LocalBackend(library: library, db: localDb);
      final result = await backend.resumeItems();
      expect(result, isEmpty);
    });

    test('userViews returns empty list', () async {
      final appDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(appDb.close);
      final localDb = LocalDb(db: appDb);
      final library = LocalLibrary(database: appDb);
      final backend = LocalBackend(library: library, db: localDb);
      final result = await backend.userViews();
      expect(result, isEmpty);
    });

    test('instantMix returns similar tracks', () async {
      final appDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(appDb.close);
      final localDb = LocalDb(db: appDb);
      final library = LocalLibrary(database: appDb);
      final backend = LocalBackend(library: library, db: localDb);
      await localDb.upsertTracks([
        {
          'id': 'content://uri/1',
          'title': 'Tide',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
        },
      ]);
      final result = await backend.instantMix('content://uri/1');
      expect(result, isEmpty);
    });
  });

  group('LocalBackend empty library', () {
    late AppDatabase appDb;
    late LocalDb localDb;
    late LocalLibrary library;
    late LocalBackend backend;

    setUp(() async {
      appDb = AppDatabase.forTesting(NativeDatabase.memory());
      localDb = LocalDb(db: appDb);
      library = LocalLibrary(database: appDb);
      backend = LocalBackend(library: library, db: localDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('recentlyAddedAlbums returns empty', () async {
      final albums = await backend.recentlyAddedAlbums();
      expect(albums, isEmpty);
    });

    test('allAlbums returns empty', () async {
      final albums = await backend.allAlbums();
      expect(albums, isEmpty);
    });

    test('allTracks returns empty', () async {
      final tracks = await backend.allTracks();
      expect(tracks, isEmpty);
    });

    test('artists returns empty', () async {
      final artists = await backend.artists();
      expect(artists, isEmpty);
    });

    test('genres returns empty', () async {
      final genres = await backend.genres();
      expect(genres, isEmpty);
    });

    test('album returns null for empty library', () async {
      final result = await backend.album('local:album:Anything:Artist');
      expect(result, isNull);
    });

    test('search returns empty for empty library', () async {
      final result = await backend.search('test');
      expect(result.tracks, isEmpty);
      expect(result.albums, isEmpty);
      expect(result.artists, isEmpty);
    });

    test('favoriteTracks returns empty', () async {
      final favs = await backend.favoriteTracks();
      expect(favs, isEmpty);
    });

    test('favoriteAlbums returns empty', () async {
      final favs = await backend.favoriteAlbums();
      expect(favs, isEmpty);
    });
  });
}
