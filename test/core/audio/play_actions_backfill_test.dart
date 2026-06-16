import 'package:drift/native.dart';
import 'package:aetherfin/core/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  group('PlayActions Instant Mix Backfilling', () {
    test(
      'playInstantMix backfills the queue using similarity propagation and fallback levels',
      () async {
        final mockSvc = MockPlayerService();
        final mockBackend = MockMusicBackend();
        final mockHistoryRepo = MockQueueHistoryRepository();

        const seed = AfTrack(
          id: 'seed-track',
          title: 'Seed Track',
          artistName: 'Test Artist',
          albumName: 'Test Album',
          artistId: 'artist-1',
          albumId: 'album-1',
        );

        // Setup initial instantMix to return only 2 tracks
        when(() => mockBackend.instantMix('seed-track')).thenAnswer(
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
          ],
        );

        // Setup similarity propagation step (instantMix for the last track 'track-2')
        when(
          () => mockBackend.instantMix('track-2', limit: any(named: 'limit')),
        ).thenAnswer(
          (_) async => [
            const AfTrack(
              id: 'track-3',
              title: 'Track 3',
              artistName: 'Test Artist',
              albumName: 'Test Album',
            ),
            const AfTrack(
              id: 'track-4',
              title: 'Track 4',
              artistName: 'Test Artist',
              albumName: 'Test Album',
            ),
          ],
        );

        // Propagation step 2 (instantMix for 'track-4' returns nothing new)
        when(
          () => mockBackend.instantMix('track-4', limit: any(named: 'limit')),
        ).thenAnswer((_) async => []);

        // Setup artist top tracks fallback
        when(
          () => mockBackend.artistTopTracks(
            'artist-1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => [
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
          ],
        );

        // Setup search fallback
        when(() => mockBackend.search('Test Artist')).thenAnswer(
          (_) async => (
            tracks: [
              const AfTrack(
                id: 'track-7',
                title: 'Track 7',
                artistName: 'Test Artist',
                albumName: 'Test Album',
              ),
            ],
            albums: const <AfAlbum>[],
            artists: const <AfArtist>[],
            playlists: const <AfPlaylist>[],
          ),
        );

        // Setup album fallback
        when(() => mockBackend.album('album-1')).thenAnswer(
          (_) async => (
            album: const AfAlbum(
              id: 'album-1',
              name: 'Test Album',
              artistName: 'Test Artist',
              trackCount: 2,
            ),
            tracks: [
              const AfTrack(
                id: 'track-8',
                title: 'Track 8',
                artistName: 'Test Artist',
                albumName: 'Test Album',
              ),
            ],
          ),
        );

        // Mock playQueue call on service
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

        final container = ProviderContainer(
          overrides: [
            musicBackendProvider.overrideWithValue(mockBackend),
            queueHistoryRepositoryProvider.overrideWithValue(mockHistoryRepo),
            playerServiceProvider.overrideWithValue(mockSvc),
            appModeProvider.overrideWith(
              () => StateHolder<AppMode?>((ref) => AppMode.local),
            ),
            appDatabaseProvider.overrideWithValue(
              AppDatabase.forTesting(NativeDatabase.memory()),
            ),
            initialAuthProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);

        final actions = container.read(playActionsProvider);
        await actions.playInstantMix(seed, wait: true);

        // The final queue must be composed of the seed and the backfilled tracks
        expect(playedQueue, isNotNull);
        expect(playedQueue!.any((t) => t.id == 'seed-track'), isTrue);

        final fullQueue = [...playedQueue!, ...?appendedQueue];
        expect(fullQueue.any((t) => t.id == 'track-1'), isTrue);
        expect(fullQueue.any((t) => t.id == 'track-2'), isTrue);
        expect(fullQueue.any((t) => t.id == 'track-3'), isTrue);
        expect(fullQueue.any((t) => t.id == 'track-4'), isTrue);
        expect(fullQueue.any((t) => t.id == 'track-5'), isTrue);
        expect(fullQueue.any((t) => t.id == 'track-6'), isTrue);
        expect(fullQueue.any((t) => t.id == 'track-7'), isTrue);
        expect(fullQueue.any((t) => t.id == 'track-8'), isTrue);
        expect(fullQueue.any((t) => t.id == 'track-9'), isFalse);
      },
    );
  });
}
