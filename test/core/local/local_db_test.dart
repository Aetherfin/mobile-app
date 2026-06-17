import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.trackById', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        {
          'id': 'content://uri/seed',
          'title': 'Seed',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': '',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/storage/coastlines/1.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'content://uri/other',
          'title': 'Other',
          'artist': 'Dos',
          'album': 'Coastlines',
          'album_artist': '',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/storage/coastlines/2.mp3',
          'codec': 'mp3',
        },
      ]);
    });

    tearDown(() => db.close());

    test('returns the matching track', () async {
      final t = await db.trackById('content://uri/seed');
      expect(t, isNotNull);
      expect(t!.id, 'content://uri/seed');
      expect(t.title, 'Seed');
      expect(t.artistName, 'Una');
    });

    test('returns null for an unknown id', () async {
      final t = await db.trackById('content://uri/missing');
      expect(t, isNull);
    });

    test('returns null on an empty library', () async {
      await db.deleteAllTracks();
      final t = await db.trackById('content://uri/seed');
      expect(t, isNull);
    });
  });

  group('LocalDb.albumByKey', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        {
          'id': 'content://uri/c1',
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
          'id': 'content://uri/c2',
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

    tearDown(() => db.close());

    test('returns one album with full aggregation', () async {
      final a = await db.albumByKey('Coastlines', 'Una');
      expect(a, isNotNull);
      expect(a!.name, 'Coastlines');
      expect(a.artistName, 'Una');
      expect(a.trackCount, 2);
      expect(a.totalDuration, const Duration(milliseconds: 380000));
      expect(a.year, 2020);
      expect(a.imageUrl, 'file:///c/coast.jpg');
    });

    test('returns null for unknown album/artist combo', () async {
      final a = await db.albumByKey('Nope', 'Una');
      expect(a, isNull);
      final b = await db.albumByKey('Coastlines', 'WrongArtist');
      expect(b, isNull);
    });
  });

  group('LocalDb.albumsByArtist', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        {
          'id': 'content://uri/c1',
          'title': 'Tide',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
          'year': 2020,
        },
        {
          'id': 'content://uri/s1',
          'title': 'Dune',
          'artist': 'Una',
          'album': 'Sands',
          'album_artist': 'Una',
          'duration_ms': 240000,
          'genre': 'Folk',
          'file_path': '/a/3.mp3',
          'codec': 'mp3',
          'year': 2018,
        },
      ]);
    });

    tearDown(() => db.close());

    test('returns only albums by the requested artist', () async {
      final r = await db.albumsByArtist('Una');
      expect(r.map((a) => a.name), ['Sands', 'Coastlines']);
      expect(r.first.year, 2018);
      expect(r.last.year, 2020);
    });
  });

  group('LocalDb.albumsByGenre', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        {
          'id': 'content://uri/1',
          'title': 'Sunset Drive',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Various',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/storage/coastlines/1.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'content://uri/3',
          'title': 'Anvil',
          'artist': 'Heavyset',
          'album': 'Heavyset',
          'album_artist': '',
          'duration_ms': 200000,
          'genre': 'Rock',
          'file_path': '/storage/heavyset/1.mp3',
          'codec': 'flac',
        },
      ]);
    });

    tearDown(() => db.close());

    test('returns only albums whose tracks tag the requested genre', () async {
      final pop = await db.albumsByGenre('Pop');
      expect(pop.map((a) => a.name), unorderedEquals(['Coastlines']));

      final rock = await db.albumsByGenre('Rock');
      expect(rock.map((a) => a.name), unorderedEquals(['Heavyset']));
    });
  });

  group('LocalDb.allPlaylistsWithStats', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        {
          'id': 'content://uri/1',
          'title': 'A',
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
          'title': 'B',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/a/2.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'content://uri/3',
          'title': 'C',
          'artist': 'Dos',
          'album': 'Mountains',
          'album_artist': 'Dos',
          'duration_ms': 240000,
          'genre': 'Rock',
          'file_path': '/a/3.mp3',
          'codec': 'mp3',
        },
      ]);
      var n = 0;
      String mkEntry() => 'e${++n}';

      await db.createPlaylist('local:playlist:b', 'B Workout');
      await db.addToPlaylist('local:playlist:b', [
        'content://uri/1',
        'content://uri/3',
      ], makeEntryId: mkEntry);

      await db.createPlaylist('local:playlist:a', 'A Roadtrip');
      await db.addToPlaylist('local:playlist:a', [
        'content://uri/1',
        'content://uri/2',
        'content://uri/3',
      ], makeEntryId: mkEntry);

      await db.createPlaylist('local:playlist:e', 'Empty');
    });

    tearDown(() => db.close());

    test(
      'sorted by name (case-insensitive) and includes empty playlists',
      () async {
        final r = await db.allPlaylistsWithStats();
        expect(r.map((p) => p.name), ['A Roadtrip', 'B Workout', 'Empty']);
      },
    );

    test('computes track count and total duration in one query', () async {
      final r = await db.allPlaylistsWithStats();
      final road = r.firstWhere((p) => p.name == 'A Roadtrip');
      final workout = r.firstWhere((p) => p.name == 'B Workout');
      final empty = r.firstWhere((p) => p.name == 'Empty');

      expect(road.trackCount, 3);
      expect(road.duration, const Duration(milliseconds: 620000));
      expect(workout.trackCount, 2);
      expect(workout.duration, const Duration(milliseconds: 420000));
      expect(empty.trackCount, 0);
      expect(empty.duration, Duration.zero);
    });
  });

  group('LocalDb.artistByName', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        {
          'id': 'content://uri/c1',
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
          'id': 'content://uri/c2',
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
          'id': 'content://uri/s1',
          'title': 'Dune',
          'artist': 'Una',
          'album': 'Sands',
          'album_artist': 'Una',
          'duration_ms': 240000,
          'genre': 'Folk',
          'file_path': '/a/3.mp3',
          'codec': 'mp3',
        },
      ]);
    });

    tearDown(() => db.close());

    test('returns the matching artist with album count', () async {
      final a = await db.artistByName('Una');
      expect(a, isNotNull);
      expect(a!.name, 'Una');
      expect(a.id, 'local:artist:Una');
      expect(a.albumCount, 2);
      expect(a.imageUrl, 'file:///c/coast.jpg');
    });
  });

  group('LocalDb.favoriteAlbums', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        {
          'id': 'content://uri/c1',
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
          'id': 'content://uri/c2',
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

    tearDown(() => db.close());

    test('returns only the favorited albums', () async {
      await db.setFavorite('local:album:Coastlines:Una', true);
      final r = await db.favoriteAlbums();
      expect(r.map((a) => a.name), ['Coastlines']);
      expect(r.first.isFavorite, isTrue);
      expect(r.first.trackCount, 2);
      expect(r.first.totalDuration, const Duration(milliseconds: 380000));
    });
  });

  group('LocalDb search', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        {
          'id': 'content://uri/c1',
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
          'id': 'content://uri/m1',
          'title': 'Peak',
          'artist': 'Dos',
          'album': 'Mountains',
          'album_artist': 'Dos',
          'duration_ms': 240000,
          'genre': 'Rock',
          'file_path': '/a/3.mp3',
          'codec': 'mp3',
          'cover_path': '/c/mtn.jpg',
        },
      ]);
    });

    tearDown(() => db.close());

    group('searchAlbums', () {
      test('matches by album name', () async {
        final r = await db.searchAlbums('coast');
        expect(r.map((a) => a.name), ['Coastlines']);
        expect(r.first.trackCount, 1);
      });
    });

    group('searchPlaylists', () {
      setUp(() async {
        await db.createPlaylist('local:playlist:1', 'Roadtrip 2024');
        var entryIdCounter = 0;
        await db.addToPlaylist('local:playlist:1', [
          'content://uri/c1',
          'content://uri/m1',
        ], makeEntryId: () => 'test_entry_${entryIdCounter++}');
      });

      test('matches by name + computes count/duration in one query', () async {
        final r = await db.searchPlaylists('road');
        expect(r, hasLength(1));
        expect(r.first.name, 'Roadtrip 2024');
        expect(r.first.trackCount, 2);
        expect(r.first.duration, const Duration(milliseconds: 420000));
      });
    });
  });
}
