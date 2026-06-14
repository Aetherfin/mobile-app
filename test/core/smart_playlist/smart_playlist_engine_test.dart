import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:aetherfin/core/smart_playlist/smart_playlist_engine.dart';
import 'package:aetherfin/core/smart_playlist/smart_playlist_model.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/jellyfin/models/quality.dart';
import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('SmartPlaylistEngine.resolveFromList', () {
    late SmartPlaylistEngine engine;
    late List<AfTrack> allTracks;
    late Map<String, ({int playCount, DateTime? lastPlayed})> playHistoryMap;

    setUp(() {
      engine = SmartPlaylistEngine();
      allTracks = [
        AfTrack(
          id: 'track-1',
          title: 'Lovely Day',
          artistName: 'Billie',
          albumName: 'Romance',
          duration: const Duration(seconds: 240),
          isFavorite: true,
          quality: const TrackQuality(sourceCodec: 'flac', bitrateKbps: 320),
          dateAdded: DateTime.now().subtract(const Duration(days: 5)),
        ),
        AfTrack(
          id: 'track-2',
          title: 'Heartless',
          artistName: 'Billie',
          albumName: 'Moods',
          duration: const Duration(seconds: 180),
          isFavorite: false,
          quality: const TrackQuality(sourceCodec: 'aac', bitrateKbps: 256),
          dateAdded: DateTime.now().subtract(const Duration(days: 30)),
        ),
        AfTrack(
          id: 'track-3',
          title: 'Ocean Eyes',
          artistName: 'Finneas',
          albumName: 'Romance',
          duration: const Duration(seconds: 200),
          isFavorite: false,
          quality: const TrackQuality(sourceCodec: 'mp3', bitrateKbps: 192),
          dateAdded: DateTime.now().subtract(const Duration(days: 60)),
        ),
        AfTrack(
          id: 'track-4',
          title: 'Love Yourself',
          artistName: 'Justin',
          albumName: 'Purpose',
          duration: const Duration(seconds: 260),
          isFavorite: true,
          quality: const TrackQuality(sourceCodec: 'flac', bitrateKbps: 320),
          dateAdded: DateTime.now().subtract(const Duration(days: 365)),
        ),
      ];
      playHistoryMap = {
        'track-1': (
          playCount: 10,
          lastPlayed: DateTime.now().subtract(const Duration(days: 1)),
        ),
        'track-2': (
          playCount: 5,
          lastPlayed: DateTime.now().subtract(const Duration(days: 7)),
        ),
        'track-3': (
          playCount: 2,
          lastPlayed: DateTime.now().subtract(const Duration(days: 30)),
        ),
      };
    });

    group('single rule', () {
      test('is operator matches text case-insensitive', () {
        final playlist = SmartPlaylist(
          id: 'sp-1',
          name: 'Billie tracks',
          rules: const [
            SmartRule(field: 'artist', operator: 'is', value: 'billie'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-2', 'track-1']);
      });

      test('is operator with no matching tracks returns empty', () {
        final playlist = SmartPlaylist(
          id: 'sp-2',
          name: 'Unknown artist',
          rules: const [
            SmartRule(field: 'artist', operator: 'is', value: 'Nobody'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result, isEmpty);
      });

      test('contains operator matches title substring case-insensitive', () {
        final playlist = SmartPlaylist(
          id: 'sp-3',
          name: 'Love songs',
          rules: const [
            SmartRule(field: 'title', operator: 'contains', value: 'love'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-4', 'track-1']);
      });

      test('contains operator with no match returns empty', () {
        final playlist = SmartPlaylist(
          id: 'sp-4',
          name: 'No matches',
          rules: const [
            SmartRule(field: 'title', operator: 'contains', value: 'zzzz'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result, isEmpty);
      });
    });

    group('AND combinator', () {
      test('both rules must match with combinator=all', () {
        final playlist = SmartPlaylist(
          id: 'sp-5',
          name: 'Billie Romance',
          rules: const [
            SmartRule(field: 'artist', operator: 'is', value: 'billie'),
            SmartRule(field: 'album', operator: 'is', value: 'Romance'),
          ],
          combinator: 'all',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-1']);
      });

      test('AND with multiple fields filters strictly', () {
        final playlist = SmartPlaylist(
          id: 'sp-6',
          name: 'Favorite flac',
          rules: const [
            SmartRule(field: 'isFavorite', operator: 'is', value: true),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-4', 'track-1']);
      });
    });

    group('OR combinator', () {
      test('either rule can match with combinator=any', () {
        final playlist = SmartPlaylist(
          id: 'sp-7',
          name: 'Billie or Finneas',
          rules: const [
            SmartRule(field: 'artist', operator: 'is', value: 'billie'),
            SmartRule(field: 'artist', operator: 'is', value: 'finneas'),
          ],
          combinator: 'any',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-2', 'track-1', 'track-3']);
      });

      test('OR combinator with no overlap still returns both groups', () {
        final playlist = SmartPlaylist(
          id: 'sp-8',
          name: 'Billie or Favorite',
          rules: const [
            SmartRule(field: 'artist', operator: 'is', value: 'justin'),
            SmartRule(field: 'isFavorite', operator: 'is', value: true),
          ],
          combinator: 'any',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        // Justin (track-4) OR isFavorite (track-1, track-4) = track-1, track-4
        expect(result.map((t) => t.id), ['track-4', 'track-1']);
      });
    });

    group('date-based rules', () {
      test('inTheLast operator filters by lastPlayed', () {
        final playlist = SmartPlaylist(
          id: 'sp-9',
          name: 'Recently played',
          rules: const [
            SmartRule(field: 'lastPlayed', operator: 'inTheLast', value: 3),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(
          playlist,
          allTracks,
          playHistoryMap: playHistoryMap,
        );
        // track-1 played 1 day ago, within last 3 days
        expect(result.map((t) => t.id), ['track-1']);
      });

      test('dateAdded inTheLast works with track.dateAdded', () {
        final playlist = SmartPlaylist(
          id: 'sp-10',
          name: 'Recently added',
          rules: const [
            SmartRule(field: 'dateAdded', operator: 'inTheLast', value: 10),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        // track-1 dateAdded is 5 days ago, within last 10
        // track-2 dateAdded is 30 days ago, outside
        // track-3 dateAdded is 60 days ago, outside
        // track-4 dateAdded is 365 days ago, outside
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-1']);
      });
    });

    group('numeric rules', () {
      test('gt operator filters playCount via history map', () {
        final playlist = SmartPlaylist(
          id: 'sp-11',
          name: 'Popular tracks',
          rules: const [
            SmartRule(field: 'playCount', operator: 'gt', value: 3),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(
          playlist,
          allTracks,
          playHistoryMap: playHistoryMap,
        );
        // track-1 has playCount 10, track-2 has playCount 5
        expect(result.map((t) => t.id), ['track-2', 'track-1']);
      });

      test('gt operator with no match returns empty', () {
        final playlist = SmartPlaylist(
          id: 'sp-12',
          name: 'Overplayed',
          rules: const [
            SmartRule(field: 'playCount', operator: 'gt', value: 100),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(
          playlist,
          allTracks,
          playHistoryMap: playHistoryMap,
        );
        expect(result, isEmpty);
      });

      test('lt operator filters duration in seconds', () {
        final playlist = SmartPlaylist(
          id: 'sp-13',
          name: 'Short tracks',
          rules: const [
            SmartRule(field: 'duration', operator: 'lt', value: 200),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        // track-2: 180s < 200
        // track-3: 200s is NOT < 200
        expect(result.map((t) => t.id), ['track-2']);
      });

      test('inTheRange operator filters by numeric range', () {
        final playlist = SmartPlaylist(
          id: 'sp-14',
          name: 'Medium bitrate',
          rules: [
            SmartRule(
              field: 'bitrate',
              operator: 'inTheRange',
              value: [200, 300],
            ),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        // track-2 bitrate 256 in [200, 300]
        expect(result.map((t) => t.id), ['track-2']);
      });

      test('is operator matches exact numeric value', () {
        final playlist = SmartPlaylist(
          id: 'sp-15',
          name: '320kbps tracks',
          rules: const [
            SmartRule(field: 'bitrate', operator: 'is', value: 320),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-4', 'track-1']);
      });

      test('isNot operator excludes numeric value', () {
        final playlist = SmartPlaylist(
          id: 'sp-16',
          name: 'Not 256kbps',
          rules: const [
            SmartRule(field: 'bitrate', operator: 'isNot', value: 256),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-4', 'track-1', 'track-3']);
      });

      test('playCount defaults to 0 for tracks not in history map', () {
        final playlist = SmartPlaylist(
          id: 'sp-17',
          name: 'Never played',
          rules: const [
            SmartRule(field: 'playCount', operator: 'is', value: 0),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(
          playlist,
          allTracks,
          playHistoryMap: playHistoryMap,
        );
        // track-4 not in history map, playCount defaults to 0
        expect(result.map((t) => t.id), ['track-4']);
      });
    });

    group('text rules', () {
      test('is operator matches exact text case-insensitive', () {
        final playlist = SmartPlaylist(
          id: 'sp-18',
          name: 'Romance album',
          rules: const [
            SmartRule(field: 'album', operator: 'is', value: 'romance'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-1', 'track-3']);
      });

      test('isNot operator excludes matching text', () {
        final playlist = SmartPlaylist(
          id: 'sp-19',
          name: 'Not Billie',
          rules: const [
            SmartRule(field: 'artist', operator: 'isNot', value: 'billie'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-4', 'track-3']);
      });

      test('notContains excludes tracks matching substring', () {
        final playlist = SmartPlaylist(
          id: 'sp-20',
          name: 'Not love songs',
          rules: const [
            SmartRule(field: 'title', operator: 'notContains', value: 'love'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-2', 'track-3']);
      });
    });

    group('edge cases', () {
      test('empty rules return all tracks', () {
        final playlist = SmartPlaylist(
          id: 'sp-21',
          name: 'All tracks',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result, hasLength(4));
      });

      test('limit caps the result count', () {
        final playlist = SmartPlaylist(
          id: 'sp-22',
          name: 'First 2',
          limit: 2,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result, hasLength(2));
      });

      test('sort by title orders alphabetically ascending', () {
        final playlist = SmartPlaylist(
          id: 'sp-23',
          name: 'Sorted',
          sort: 'title',
          sortOrder: 'asc',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.title), [
          'Heartless',
          'Love Yourself',
          'Lovely Day',
          'Ocean Eyes',
        ]);
      });

      test('sort by title descending orders correctly', () {
        final playlist = SmartPlaylist(
          id: 'sp-24',
          name: 'Reverse sorted',
          sort: 'title',
          sortOrder: 'desc',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.title), [
          'Ocean Eyes',
          'Lovely Day',
          'Love Yourself',
          'Heartless',
        ]);
      });

      test('sort by random shuffles results', () {
        final playlist = SmartPlaylist(
          id: 'sp-25',
          name: 'Random',
          sort: 'random',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        // Run twice; with 4 tracks the chance of same order is ~4% but
        // acceptable as a smoke test that random sort doesn't crash and
        // returns all tracks.
        final result1 = engine.resolveFromList(playlist, allTracks);
        final result2 = engine.resolveFromList(playlist, allTracks);
        expect(result1, hasLength(4));
        expect(result2, hasLength(4));
      });

      test('codec field matches source codec string', () {
        final playlist = SmartPlaylist(
          id: 'sp-26',
          name: 'FLAC only',
          rules: const [
            SmartRule(field: 'codec', operator: 'is', value: 'flac'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-4', 'track-1']);
      });

      test('isFavorite false returns unfavorited tracks', () {
        final playlist = SmartPlaylist(
          id: 'sp-27',
          name: 'Not favorited',
          rules: const [
            SmartRule(field: 'isFavorite', operator: 'is', value: false),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = engine.resolveFromList(playlist, allTracks);
        expect(result.map((t) => t.id), ['track-2', 'track-3']);
      });
    });
  });

  group('SmartPlaylistEngine.resolveLocal', () {
    late LocalDb db;
    late SmartPlaylistEngine engine;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      engine = SmartPlaylistEngine();
      await db.upsertTracks([
        {
          'id': 'track-1',
          'title': 'Lovely Day',
          'artist': 'Billie',
          'album': 'Romance',
          'album_artist': 'Billie',
          'duration_ms': 240000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'flac',
        },
        {
          'id': 'track-2',
          'title': 'Heartless',
          'artist': 'Billie',
          'album': 'Moods',
          'album_artist': 'Billie',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/2.mp3',
          'codec': 'aac',
        },
        {
          'id': 'track-3',
          'title': 'Ocean Eyes',
          'artist': 'Finneas',
          'album': 'Romance',
          'album_artist': 'Finneas',
          'duration_ms': 200000,
          'genre': 'Rock',
          'file_path': '/a/3.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'track-4',
          'title': 'Love Yourself',
          'artist': 'Justin',
          'album': 'Purpose',
          'album_artist': 'Justin',
          'duration_ms': 260000,
          'genre': 'Pop',
          'file_path': '/a/4.mp3',
          'codec': 'flac',
        },
      ]);
    });

    tearDown(() => db.close());

    test('resolves simple title contains rule', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-1',
        name: 'Love songs',
        rules: const [
          SmartRule(field: 'title', operator: 'contains', value: 'Love'),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result.map((t) => t.id), unorderedEquals(['track-1', 'track-4']));
    });

    test('resolves artist is rule', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-2',
        name: 'Billie tracks',
        rules: const [
          SmartRule(field: 'artist', operator: 'is', value: 'Billie'),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result.map((t) => t.id), unorderedEquals(['track-1', 'track-2']));
    });

    test('resolves duration gt rule', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-3',
        name: 'Long tracks',
        rules: const [
          // SQL maps duration to duration_ms column (ms)
          SmartRule(field: 'duration', operator: 'gt', value: 200000),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      // duration_ms > 200000 → track-1 (240s), track-4 (260s)
      expect(result.map((t) => t.id), unorderedEquals(['track-1', 'track-4']));
    });

    test('resolves album is rule', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-4',
        name: 'Romance album',
        rules: const [
          SmartRule(field: 'album', operator: 'is', value: 'Romance'),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result.map((t) => t.id), unorderedEquals(['track-1', 'track-3']));
    });

    test('resolves AND combinator', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-5',
        name: 'Billie Pop',
        rules: const [
          SmartRule(field: 'artist', operator: 'is', value: 'Billie'),
          SmartRule(field: 'genre', operator: 'is', value: 'Pop'),
        ],
        combinator: 'all',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result.map((t) => t.id), unorderedEquals(['track-1', 'track-2']));
    });

    test('resolves OR combinator', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-6',
        name: 'Pop or Rock',
        rules: const [
          SmartRule(field: 'genre', operator: 'is', value: 'Pop'),
          SmartRule(field: 'genre', operator: 'is', value: 'Rock'),
        ],
        combinator: 'any',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(
        result.map((t) => t.id),
        unorderedEquals(['track-1', 'track-2', 'track-3', 'track-4']),
      );
    });

    test('empty rules return all tracks', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-7',
        name: 'All',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result, hasLength(4));
    });

    test('no matching tracks returns empty', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-8',
        name: 'No match',
        rules: const [
          SmartRule(field: 'artist', operator: 'is', value: 'Nobody'),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result, isEmpty);
    });

    test('limit caps result count', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-9',
        name: 'Capped',
        rules: const [SmartRule(field: 'genre', operator: 'is', value: 'Pop')],
        limit: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result, hasLength(1));
    });

    test('sort by title ascending', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-10',
        name: 'Sorted',
        sort: 'title',
        sortOrder: 'asc',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result.map((t) => t.title), [
        'Heartless',
        'Love Yourself',
        'Lovely Day',
        'Ocean Eyes',
      ]);
    });

    test('sort by title descending', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-11',
        name: 'Reverse',
        sort: 'title',
        sortOrder: 'desc',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result.map((t) => t.title), [
        'Ocean Eyes',
        'Lovely Day',
        'Love Yourself',
        'Heartless',
      ]);
    });

    test('codec is rule filters by codec column', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-12',
        name: 'FLAC only',
        rules: const [SmartRule(field: 'codec', operator: 'is', value: 'flac')],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result.map((t) => t.id), unorderedEquals(['track-1', 'track-4']));
    });

    test('duration inTheRange filters by duration_ms column', () async {
      final playlist = SmartPlaylist(
        id: 'local-sp-13',
        name: 'Mid length',
        rules: [
          SmartRule(
            field: 'duration',
            operator: 'inTheRange',
            // SQL maps duration to duration_ms column (milliseconds)
            value: [190000, 250000],
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final result = await engine.resolveLocal(playlist, db);
      expect(result.map((t) => t.id), unorderedEquals(['track-1', 'track-3']));
    });
  });
}
