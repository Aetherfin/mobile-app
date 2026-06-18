import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/lyrics/lrc_parser.dart';
import 'package:aetherfin/core/lyrics/lyrics_resolver.dart';
import 'package:aetherfin/core/lyrics/netease_client.dart';
import 'package:aetherfin/core/lyrics/lrclib_client.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockMusicBackend extends Mock implements MusicBackend {}

class MockNetEaseClient extends Mock implements NetEaseClient {}

class MockLrcLibClient extends Mock implements LrcLibClient {}

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

const _japaneseLrc = '[00:10.00]ありがとう\n[00:15.00]さようなら';
const _englishLrc = '[00:10.00]Hello world\n[00:15.00]Goodbye world';

const _neteaseRomajiResult = (
  synced: '[00:10.00]Arigatou\n[00:15.00]Sayounara',
  plain: null,
  romaji: '[00:10.00]Arigatou\n[00:15.00]Sayounara',
);

const _lrclibResult = (
  synced: '[00:10.00]Hello world\n[00:15.00]Goodbye world',
  plain: null,
);

void main() {
  late MockMusicBackend backend;
  late MockNetEaseClient netease;
  late MockLrcLibClient lrclib;
  late LyricsResolver resolver;

  setUp(() {
    backend = MockMusicBackend();
    netease = MockNetEaseClient();
    lrclib = MockLrcLibClient();
    resolver = LyricsResolver(
      backend: backend,
      netease: netease,
      lrclib: lrclib,
    );

    registerFallbackValue(Duration.zero);

    when(
      () => lrclib.fetchLyrics(
        trackName: any(named: 'trackName'),
        artistName: any(named: 'artistName'),
        albumName: any(named: 'albumName'),
        duration: any(named: 'duration'),
      ),
    ).thenAnswer((_) async => null);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Resolve from embedded
  // ═══════════════════════════════════════════════════════════════════════════

  group('Embedded lyrics', () {
    test('returns embedded English lyrics directly (source: server)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _englishLrc);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.server));
      expect(result.lrc.lines.length, equals(2));
      expect(result.lrc.lines[0].text, equals('Hello world'));
    });

    test(
      'returns embedded romaji directly when no Japanese detected',
      () async {
        when(
          () => backend.lyrics('t1'),
        ).thenAnswer((_) async => '[00:10.00]Arigatou\n[00:15.00]Sayounara');

        final track = _track('t1');
        final result = await resolver.resolve(trackId: 't1', track: track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.server));
        expect(result.lrc.lines[0].text, equals('Arigatou'));
      },
    );

    test('embedded Japanese → NetEase romaji succeeds', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _japaneseLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => _neteaseRomajiResult);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.neteaseRomaji));
      expect(result.lrc.lines[0].text, equals('Arigatou'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Resolve from LRC
  // ═══════════════════════════════════════════════════════════════════════════

  group('LRC parsing', () {
    test('parses synced lyrics with correct timestamps', () async {
      when(() => backend.lyrics('t1')).thenAnswer(
        (_) async => '[00:05.50]First\n[01:30.00]Second\n[02:45.99]Third',
      );

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.lrc.lines.length, equals(3));
      expect(
        result.lrc.lines[0].start,
        equals(const Duration(seconds: 5, milliseconds: 500)),
      );
      expect(
        result.lrc.lines[1].start,
        equals(const Duration(minutes: 1, seconds: 30)),
      );
      expect(
        result.lrc.lines[2].start,
        equals(const Duration(minutes: 2, seconds: 45, milliseconds: 990)),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Multi-provider priority
  // ═══════════════════════════════════════════════════════════════════════════

  group('Multi-provider priority', () {
    test('LRCLib is called in parallel with NetEase (phase1)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => _neteaseRomajiResult);
      when(
        () => lrclib.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      verify(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).called(1);
      verify(
        () => lrclib.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).called(1);
      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.neteaseRomaji));
    });

    test('NetEase is called only when embedded is empty', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _englishLrc);

      final track = _track('t1');
      await resolver.resolve(trackId: 't1', track: track);

      verifyNever(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Fallback chain
  // ═══════════════════════════════════════════════════════════════════════════

  group('Fallback chain', () {
    test(
      'no embedded → NetEase fails → LRCLib succeeds (source: lrclib)',
      () async {
        when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
        when(
          () => netease.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            duration: any(named: 'duration'),
          ),
        ).thenAnswer((_) async => null);
        when(
          () => lrclib.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            duration: any(named: 'duration'),
          ),
        ).thenAnswer((_) async => _lrclibResult);

        final track = _track('t1');
        final result = await resolver.resolve(trackId: 't1', track: track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.lrclib));
        expect(result.lrc.lines[0].text, equals('Hello world'));
      },
    );

    test('no embedded → NetEase English succeeds (source: netease)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer(
        (_) async => (synced: _englishLrc, plain: null, romaji: null),
      );

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.netease));
      expect(result.lrc.lines[0].text, equals('Hello world'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Empty result
  // ═══════════════════════════════════════════════════════════════════════════

  group('Empty result', () {
    test('returns null when all sources fail', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => lrclib.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNull);
    });

    test('embedded lyrics with only whitespace is treated as empty', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => '   \n  ');
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => lrclib.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => _lrclibResult);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.lrclib));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Cache hit
  // ═══════════════════════════════════════════════════════════════════════════

  group('Cache', () {
    test('cache hit with non-Japanese returns cached result', () async {
      resolver.cacheLyrics('t1', _englishLrc, LyricsSource.server);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.cache));
      expect(result.lrc.lines[0].text, equals('Hello world'));
      verifyNever(() => backend.lyrics('t1'));
    });

    test('cache miss continues normal flow', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _englishLrc);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.server));
      verify(() => backend.lyrics('t1')).called(1);
    });
  });
}
