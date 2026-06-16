import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';
import 'package:aetherfin/core/local/local_library.dart';
import 'package:aetherfin/core/smart_playlist/smart_playlist_engine.dart';
import 'package:aetherfin/core/smart_playlist/smart_playlist_model.dart';
import 'package:aetherfin/core/audio/play_actions.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/local/queue_history_repository.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

class MockPlayerService extends Mock implements AfPlayerService {}

class MockMusicBackend extends Mock implements MusicBackend {}

class MockQueueHistoryRepository extends Mock
    implements QueueHistoryRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AfTrack(id: '', title: '', artistName: '', albumName: ''),
    );
    registerFallbackValue('');
  });

  group('SmartPlaylists Play History Rules', () {
    late LocalDb db;
    late SmartPlaylistEngine engine;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      engine = SmartPlaylistEngine();

      // Seed track library
      await db.upsertTracks([
        {
          'id': 'track-1',
          'title': 'Track One',
          'artist': 'Una',
          'album': 'First',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'track-2',
          'title': 'Track Two',
          'artist': 'Dos',
          'album': 'Second',
          'album_artist': 'Dos',
          'duration_ms': 240000,
          'genre': 'Rock',
          'file_path': '/a/2.mp3',
          'codec': 'flac',
        },
      ]);

      // Seed play history
      // track-1 played twice (not skipped)
      // track-2 played once but skipped, played once not skipped
      final appDb = db.db;
      await appDb
          .into(appDb.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: 'track-1',
              playedAt: DateTime.now()
                  .subtract(const Duration(days: 5))
                  .millisecondsSinceEpoch,
              skipped: const Value(false),
            ),
          );
      await appDb
          .into(appDb.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: 'track-1',
              playedAt: DateTime.now()
                  .subtract(const Duration(days: 2))
                  .millisecondsSinceEpoch,
              skipped: const Value(false),
            ),
          );
      await appDb
          .into(appDb.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: 'track-2',
              playedAt: DateTime.now()
                  .subtract(const Duration(days: 1))
                  .millisecondsSinceEpoch,
              skipped: const Value(true), // skipped
            ),
          );
      await appDb
          .into(appDb.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: 'track-2',
              playedAt: DateTime.now().millisecondsSinceEpoch,
              skipped: const Value(false), // not skipped
            ),
          );
    });

    tearDown(() => db.close());

    test('resolveLocal resolves playCount rules correctly', () async {
      final playlist = SmartPlaylist(
        id: 'smart-1',
        name: 'Highly Played Pop',
        rules: [const SmartRule(field: 'playCount', operator: 'gt', value: 1)],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final tracks = await engine.resolveLocal(playlist, db);
      expect(tracks, hasLength(1));
      expect(tracks.first.id, 'track-1');
    });

    test('resolveLocal resolves lastPlayed rule correctly', () async {
      final playlist = SmartPlaylist(
        id: 'smart-2',
        name: 'Played recently',
        rules: [
          const SmartRule(field: 'lastPlayed', operator: 'inTheLast', value: 3),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final tracks = await engine.resolveLocal(playlist, db);
      expect(tracks.map((t) => t.id), containsAll(['track-1', 'track-2']));
    });

    test(
      'resolveFromList resolves playCount rules correctly with history map',
      () {
        final playlist = SmartPlaylist(
          id: 'smart-3',
          name: 'Client Side Smart',
          rules: [
            const SmartRule(field: 'playCount', operator: 'gt', value: 1),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final allTracks = [
          const AfTrack(
            id: 'track-1',
            title: 'T1',
            artistName: 'A1',
            albumName: 'AL1',
          ),
          const AfTrack(
            id: 'track-2',
            title: 'T2',
            artistName: 'A2',
            albumName: 'AL2',
          ),
        ];

        final playHistoryMap = {
          'track-1': (
            playCount: 2,
            lastPlayed: DateTime.now().subtract(const Duration(days: 2)),
          ),
          'track-2': (playCount: 1, lastPlayed: DateTime.now()),
        };

        final tracks = engine.resolveFromList(
          playlist,
          allTracks,
          playHistoryMap: playHistoryMap,
        );
        expect(tracks, hasLength(1));
        expect(tracks.first.id, 'track-1');
      },
    );
  });

  group('Skip-Filtering Autoplay recommendations', () {
    test('playInstantMix filters recently skipped tracks', () async {
      final mockSvc = MockPlayerService();
      final mockBackend = MockMusicBackend();
      final mockHistoryRepo = MockQueueHistoryRepository();
      final localDb = LocalDb(
        db: AppDatabase.forTesting(NativeDatabase.memory()),
      );

      const seed = AfTrack(
        id: 'seed-track',
        title: 'Seed Track',
        artistName: 'Test Artist',
        albumName: 'Test Album',
        artistId: 'artist-1',
        albumId: 'album-1',
      );

      // Seed a skip for 'track-2' inside the database
      final appDb = localDb.db;
      await appDb
          .into(appDb.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: 'track-2',
              playedAt: DateTime.now().millisecondsSinceEpoch,
              skipped: const Value(true),
            ),
          );

      when(
        () => mockBackend.instantMix(any(), limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async => [
          const AfTrack(
            id: 'track-1',
            title: 'Track 1',
            artistName: 'Test Artist',
            albumName: 'Test Album',
          ),
          const AfTrack(
            id: 'track-2',
            title: 'Track 2',
            artistName: 'Test Artist',
            albumName: 'Test Album',
          ),
          const AfTrack(
            id: 'track-3',
            title: 'Track 3',
            artistName: 'Test Artist',
            albumName: 'Test Album',
          ),
        ],
      );
      when(() => mockBackend.search(any())).thenAnswer(
        (_) async => (
          tracks: <AfTrack>[],
          albums: <AfAlbum>[],
          artists: <AfArtist>[],
          playlists: <AfPlaylist>[],
        ),
      );
      when(() => mockBackend.album(any())).thenAnswer((_) async => null);

      // We backfill up to 10 tracks to keep it simple, seeding extra top tracks
      when(
        () =>
            mockBackend.artistTopTracks('artist-1', limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async => [
          const AfTrack(
            id: 'track-4',
            title: 'Track 4',
            artistName: 'Test Artist',
            albumName: 'Test Album',
          ),
          const AfTrack(
            id: 'track-5',
            title: 'Track 5',
            artistName: 'Test Artist',
            albumName: 'Test Album',
          ),
          const AfTrack(
            id: 'track-6',
            title: 'Track 6',
            artistName: 'Test Artist',
            albumName: 'Test Album',
          ),
          const AfTrack(
            id: 'track-7',
            title: 'Track 7',
            artistName: 'Test Artist',
            albumName: 'Test Album',
          ),
          const AfTrack(
            id: 'track-8',
            title: 'Track 8',
            artistName: 'Test Artist',
            albumName: 'Test Album',
          ),
          const AfTrack(
            id: 'track-9',
            title: 'Track 9',
            artistName: 'Test Artist',
            albumName: 'Test Album',
          ),
        ],
      );

      List<AfTrack>? playedQueue;
      when(
        () => mockSvc.playQueue(
          any(),
          startIndex: any(named: 'startIndex'),
          resolveStreamUrl: any(named: 'resolveStreamUrl'),
          streamHeaders: any(named: 'streamHeaders'),
        ),
      ).thenAnswer((invocation) async {
        playedQueue = invocation.positionalArguments[0] as List<AfTrack>;
      });
      when(() => mockSvc.isShuffleEnabled).thenReturn(false);
      when(() => mockSvc.currentTrack).thenReturn(seed);

      List<AfTrack>? appendedQueue;
      when(
        () => mockSvc.appendQueue(
          any(),
          resolveStreamUrl: any(named: 'resolveStreamUrl'),
        ),
      ).thenAnswer((invocation) async {
        appendedQueue = invocation.positionalArguments[0] as List<AfTrack>;
      });

      when(
        () => mockHistoryRepo.save(
          trackIds: any(named: 'trackIds'),
          sourceLabel: any(named: 'sourceLabel'),
          sourceType: any(named: 'sourceType'),
          sourceId: any(named: 'sourceId'),
        ),
      ).thenAnswer((_) async {});

      final localLib = LocalLibrary(database: localDb.db);
      final container = ProviderContainer(
        overrides: [
          musicBackendProvider.overrideWithValue(mockBackend),
          queueHistoryRepositoryProvider.overrideWithValue(mockHistoryRepo),
          playerServiceProvider.overrideWithValue(mockSvc),
          appModeProvider.overrideWith(
            () => StateHolder<AppMode?>((ref) => AppMode.local),
          ),
          localLibraryProvider.overrideWithValue(localLib),
          initialAuthProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(localDb.close);

      final actions = container.read(playActionsProvider);
      await actions.playInstantMix(seed, wait: true);

      expect(playedQueue, isNotNull);
      // seed-track is included
      expect(playedQueue!.any((t) => t.id == 'seed-track'), isTrue);

      final fullQueue = [...playedQueue!, ...?appendedQueue];
      // track-1 is included
      expect(fullQueue.any((t) => t.id == 'track-1'), isTrue);
      // track-2 was skipped, so it must NOT be included in the queue!
      expect(fullQueue.any((t) => t.id == 'track-2'), isFalse);
      // track-3 is included
      expect(fullQueue.any((t) => t.id == 'track-3'), isTrue);
    });
  });
}
