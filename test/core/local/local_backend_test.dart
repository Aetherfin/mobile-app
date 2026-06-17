import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:aetherfin/core/local/local_backend.dart';
import 'package:aetherfin/core/local/local_library.dart';
import 'package:aetherfin/core/local/local_db.dart';
import 'package:aetherfin/core/local/app_database.dart';


void main() {
  group('LocalBackend identification', () {
    test('trackStreamUrl returns trackId unchanged', () async {
      final appDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(appDb.close);
      final localDb = LocalDb(db: appDb);
      final library = LocalLibrary(database: appDb);
      final backend = LocalBackend(library: library, db: localDb);
      const trackId = 'content://media/external/audio/123';
      expect(backend.trackStreamUrl(trackId), trackId);
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

    test('allAlbums returns all albums with correct aggregation', () async {
      final albums = await backend.allAlbums();
      expect(albums.map((a) => a.name), ['Coastlines', 'Mountains']);
      final coast = albums.first;
      expect(coast.trackCount, 2);
      expect(coast.totalDuration, const Duration(milliseconds: 380000));
    });

    test('allTracks returns all tracks', () async {
      final tracks = await backend.allTracks();
      expect(tracks, hasLength(3));
      expect(tracks.map((t) => t.title), ['Cliff', 'Peak', 'Tide']);
    });

    test('artists returns artist list', () async {
      final result = await backend.artists();
      expect(result.map((a) => a.name), ['Dos', 'Una']);
    });

    test('genres returns genre list', () async {
      final result = await backend.genres();
      expect(result.map((g) => g.name), ['Pop', 'Rock']);
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

    test('addToPlaylist adds tracks to existing playlist', () async {
      final id = await backend.createPlaylist('Test', []);
      await backend.addToPlaylist(id!, ['content://uri/1', 'content://uri/2']);
      final playlist = await backend.playlist(id);
      expect(playlist, isNotNull);
      expect(playlist!.tracks, hasLength(2));
    });

    test('deletePlaylist removes playlist', () async {
      final id = await backend.createPlaylist('Temp', []);
      await backend.deletePlaylist(id!);
      final playlists = await backend.playlists();
      expect(playlists, isEmpty);
    });
  });
}
