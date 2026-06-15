import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/lyrics/lrc_parser.dart';
import 'package:aetherfin/core/lyrics/lyrics_resolver.dart';
import 'package:aetherfin/core/lyrics/lyrics_preload_manager.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockMusicBackend extends Mock implements MusicBackend {}

class MockLyricsResolver extends Mock implements LyricsResolver {}

// ── Helpers ──────────────────────────────────────────────────────────────────

AfTrack _track(
  String id, {
  String title = 'Test Song',
  String artist = 'Test Artist',
  String album = 'Test Album',
  Duration duration = const Duration(minutes: 3, seconds: 30),
}) => AfTrack(
  id: id,
  title: title,
  artistName: artist,
  albumName: album,
  duration: duration,
);

const _englishLrc = '[00:10.00]Hello world\n[00:15.00]Goodbye world';

void main() {
  late MockMusicBackend backend;

  setUp(() {
    backend = MockMusicBackend();
    registerFallbackValue(Duration.zero);
  });

  group('LyricsPreloadManager', () {
    group('preloadNext', () {
      test('preloads next 3 tracks on song change', () async {
        when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

        final preloader = LyricsPreloadManager(backend: backend);
        final queue = [
          _track('t1'),
          _track('t2'),
          _track('t3'),
          _track('t4'),
          _track('t5'),
        ];

        preloader.preloadNext(queue: queue, currentIndex: 0);

        // Need to pump event queue so fire-and-forget futures complete
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        // Should preload t2, t3, t4 (index 1, 2, 3)
        verify(() => backend.lyrics('t2')).called(1);
        verify(() => backend.lyrics('t3')).called(1);
        verify(() => backend.lyrics('t4')).called(1);

        // Should NOT preload t1 (current) or t5 (beyond +3 range)
        verifyNever(() => backend.lyrics('t1'));
        verifyNever(() => backend.lyrics('t5'));
      });

      test('does not preload beyond queue length', () async {
        when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

        final preloader = LyricsPreloadManager(backend: backend);
        // Queue with only 2 tracks — currentIndex=0 means only t2 is ahead
        final queue = [_track('t1'), _track('t2')];

        preloader.preloadNext(queue: queue, currentIndex: 0);

        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        verify(() => backend.lyrics('t2')).called(1);
        verifyNever(() => backend.lyrics('t1'));

        // Verify cache was populated
        expect(preloader.resolver.cacheSize, greaterThan(0));
      });

      test('no preload when at end of queue', () async {
        when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

        final preloader = LyricsPreloadManager(backend: backend);
        final queue = [_track('t1'), _track('t2'), _track('t3')];

        // currentIndex=2 is the last track, nothing ahead to preload
        preloader.preloadNext(queue: queue, currentIndex: 2);

        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        verifyNever(() => backend.lyrics(any()));
      });

      test('no preload when queue is empty', () async {
        when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

        final preloader = LyricsPreloadManager(backend: backend);

        preloader.preloadNext(queue: [], currentIndex: 0);

        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        verifyNever(() => backend.lyrics(any()));
      });

      test('no preload when currentIndex is invalid (-1)', () async {
        when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

        final preloader = LyricsPreloadManager(backend: backend);
        final queue = [_track('t1')];

        preloader.preloadNext(queue: queue, currentIndex: -1);

        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        verifyNever(() => backend.lyrics(any()));
      });
    });

    group('Duplicate prevention', () {
      test('same track not preloaded twice', () async {
        when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

        final preloader = LyricsPreloadManager(backend: backend);
        final queue = [_track('t1'), _track('t2'), _track('t3'), _track('t4')];

        // First preload: should preload t2, t3, t4
        preloader.preloadNext(queue: queue, currentIndex: 0);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        // Second preload with same queue — should skip already-preloaded
        preloader.preloadNext(queue: queue, currentIndex: 0);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        // Each track should be fetched exactly once (no re-fetch on repeat)
        verify(() => backend.lyrics('t2')).called(1);
        verify(() => backend.lyrics('t3')).called(1);
        verify(() => backend.lyrics('t4')).called(1);
        verifyNever(() => backend.lyrics('t1'));
      });

      test('preloads new track after advance', () async {
        when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

        final preloader = LyricsPreloadManager(backend: backend);
        final queue = [
          _track('t1'),
          _track('t2'),
          _track('t3'),
          _track('t4'),
          _track('t5'),
        ];

        // First preload at index 0: preload t2, t3, t4
        preloader.preloadNext(queue: queue, currentIndex: 0);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        verify(() => backend.lyrics('t2')).called(1);
        verify(() => backend.lyrics('t3')).called(1);
        verify(() => backend.lyrics('t4')).called(1);

        // Advance to index 1: should preload t5 (not in preloaded set)
        preloader.preloadNext(queue: queue, currentIndex: 1);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        verify(() => backend.lyrics('t5')).called(1);
      });

      test('skips tracks already in resolver cache', () async {
        when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

        final preloader = LyricsPreloadManager(backend: backend);
        final queue = [_track('t2'), _track('t3')];

        // Pre-populate resolver cache with t2 and t3
        preloader.resolver.cacheLyrics('t2', _englishLrc, LyricsSource.server);
        preloader.resolver.cacheLyrics('t3', _englishLrc, LyricsSource.server);

        // preloadNext should skip t2 and t3 since they're already cached
        preloader.preloadNext(queue: queue, currentIndex: 0);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        verifyNever(() => backend.lyrics('t2'));
        verifyNever(() => backend.lyrics('t3'));
      });
    });

    group('Error handling', () {
      test('does not crash when backend throws', () async {
        when(() => backend.lyrics(any())).thenThrow(Exception('Network error'));

        final preloader = LyricsPreloadManager(backend: backend);
        final queue = [_track('t1'), _track('t2'), _track('t3')];

        // Should not throw — fire-and-forget catches exceptions
        expect(
          () => preloader.preloadNext(queue: queue, currentIndex: 0),
          returnsNormally,
        );

        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        // Exception caught internally, no crash
        verify(() => backend.lyrics('t2')).called(1);
      });

      test('does not block playback (returns synchronously)', () async {
        // Use a slow mock to verify fire-and-forget
        when(() => backend.lyrics(any())).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return _englishLrc;
        });

        final preloader = LyricsPreloadManager(backend: backend);
        final queue = [_track('t1'), _track('t2')];

        final stopwatch = Stopwatch()..start();
        preloader.preloadNext(queue: queue, currentIndex: 0);
        stopwatch.stop();

        // preloadNext must return synchronously (<< 100 ms even though each
        // preload takes 100 ms)
        expect(stopwatch.elapsedMilliseconds, lessThan(50));
      });
    });

    group('reset', () {
      test('clears preloaded track IDs set', () async {
        when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

        final preloader = LyricsPreloadManager(backend: backend);
        // New queue with different tracks than the first batch
        final queue1 = [_track('t1'), _track('t2')];
        final queue2 = [_track('t3'), _track('t4'), _track('t5')];

        preloader.preloadNext(queue: queue1, currentIndex: 0);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        // Reset clears the preloaded set so tracks from the new queue
        // are not skipped by the set check (resolver cache still prevents
        // re-fetch of duplicates across resets).
        preloader.reset();

        preloader.preloadNext(queue: queue2, currentIndex: 0);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        verify(() => backend.lyrics('t2')).called(1);
        verify(() => backend.lyrics('t4')).called(1);
        verify(() => backend.lyrics('t5')).called(1);
        verifyNever(() => backend.lyrics('t1'));
        verifyNever(() => backend.lyrics('t3'));
      });
    });
  });
}
