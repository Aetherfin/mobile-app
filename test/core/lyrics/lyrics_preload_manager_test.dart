import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/lyrics/lrc_parser.dart';

import 'package:aetherfin/core/lyrics/lyrics_preload_manager.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockMusicBackend extends Mock implements MusicBackend {}

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

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      verify(() => backend.lyrics('t2')).called(1);
      verify(() => backend.lyrics('t3')).called(1);
      verify(() => backend.lyrics('t4')).called(1);
      verifyNever(() => backend.lyrics('t1'));
      verifyNever(() => backend.lyrics('t5'));
    });

    test('does not preload beyond queue length', () async {
      when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

      final preloader = LyricsPreloadManager(backend: backend);
      final queue = [_track('t1'), _track('t2')];

      preloader.preloadNext(queue: queue, currentIndex: 0);

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      verify(() => backend.lyrics('t2')).called(1);
      verifyNever(() => backend.lyrics('t1'));
      expect(preloader.resolver.cacheSize, greaterThan(0));
    });

    test('skips tracks already in resolver cache', () async {
      when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

      final preloader = LyricsPreloadManager(backend: backend);
      final queue = [_track('t2'), _track('t3')];

      preloader.resolver.cacheLyrics('t2', _englishLrc, LyricsSource.server);
      preloader.resolver.cacheLyrics('t3', _englishLrc, LyricsSource.server);

      preloader.preloadNext(queue: queue, currentIndex: 0);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      verifyNever(() => backend.lyrics('t2'));
      verifyNever(() => backend.lyrics('t3'));
    });

    test('same track not preloaded twice', () async {
      when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

      final preloader = LyricsPreloadManager(backend: backend);
      final queue = [_track('t1'), _track('t2'), _track('t3'), _track('t4')];

      preloader.preloadNext(queue: queue, currentIndex: 0);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      preloader.preloadNext(queue: queue, currentIndex: 0);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      verify(() => backend.lyrics('t2')).called(1);
      verify(() => backend.lyrics('t3')).called(1);
      verify(() => backend.lyrics('t4')).called(1);
    });

    test('clears preloaded track IDs on reset', () async {
      when(() => backend.lyrics(any())).thenAnswer((_) async => _englishLrc);

      final preloader = LyricsPreloadManager(backend: backend);
      final queue1 = [_track('t1'), _track('t2')];
      final queue2 = [_track('t3'), _track('t4'), _track('t5')];

      preloader.preloadNext(queue: queue1, currentIndex: 0);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      preloader.reset();

      preloader.preloadNext(queue: queue2, currentIndex: 0);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      verify(() => backend.lyrics('t4')).called(1);
      verify(() => backend.lyrics('t5')).called(1);
      verifyNever(() => backend.lyrics('t1'));
    });
  });
}
