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
  });
}
