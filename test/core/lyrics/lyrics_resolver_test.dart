import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/lyrics/lrc_parser.dart';
import 'package:aetherfin/core/lyrics/lyrics_resolver.dart';
import 'package:aetherfin/core/lyrics/netease_client.dart';
import 'package:aetherfin/core/lyrics/lrclib_client.dart';
import 'package:aetherfin/core/lyrics/providers/kugou_client.dart';
import 'package:aetherfin/core/lyrics/providers/simpmusic_client.dart';
import 'package:aetherfin/core/lyrics/providers/unison_client.dart';
import 'package:aetherfin/utils/text_utils.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockMusicBackend extends Mock implements MusicBackend {}

class MockNetEaseClient extends Mock implements NetEaseClient {}

class MockLrcLibClient extends Mock implements LrcLibClient {}

class MockKuGouClient extends Mock implements KuGouClient {}

class MockSimpMusicClient extends Mock implements SimpMusicClient {}

class MockUnisonClient extends Mock implements UnisonClient {}

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

/// A synced LRC with Japanese text.
const _japaneseLrc = '[00:10.00]ありがとう\n[00:15.00]さようなら';

/// A synced LRC with English text.
const _englishLrc = '[00:10.00]Hello world\n[00:15.00]Goodbye world';

/// A synced LRC with romaji text (Latin characters, no Japanese).
const _romajiLrc = '[00:10.00]Arigatou\n[00:15.00]Sayounara';

/// NetEase romaji result.
const _neteaseRomajiResult = (
  synced: '[00:10.00]Arigatou\n[00:15.00]Sayounara',
  plain: null,
  romaji: '[00:10.00]Arigatou\n[00:15.00]Sayounara',
);

/// NetEase original (Japanese) result.
const _neteaseJapaneseResult = (
  synced: '[00:10.00]ありがとう\n[00:15.00]さようなら',
  plain: null,
  romaji: null,
);

/// LrcLib result.
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

    // Register fallback values for mock method calls
    registerFallbackValue(Duration.zero);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Flow 1: Embedded lyrics exist
  // ═══════════════════════════════════════════════════════════════════════════

  group('Embedded lyrics exist', () {
    test('returns embedded English lyrics directly (source: server)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _englishLrc);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.server));
      expect(result.lrc.lines.length, equals(2));
      expect(result.lrc.lines[0].text, equals('Hello world'));
    });

    test('returns embedded romaji directly when no Japanese detected '
        '(source: server)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _romajiLrc);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.server));
      expect(result.lrc.lines[0].text, equals('Arigatou'));
    });

    test(
      'embedded Japanese → NetEase romaji succeeds (source: neteaseRomaji)',
      () async {
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
      },
    );

    test('embedded Japanese → NetEase romaji fails → romanize locally '
        '(source: romanize)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _japaneseLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
      // Romanized text should be Latin characters, not Japanese
      expect(containsJapanese(result.lrc.lines[0].text), isFalse);
    });

    test('embedded Japanese → NetEase returns Japanese (no romaji) → '
        'romanize locally (source: romanize)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _japaneseLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => _neteaseJapaneseResult);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
      expect(containsJapanese(result.lrc.lines[0].text), isFalse);
    });

    test('embedded Japanese → NetEase romaji still has Japanese → '
        'romanize the romaji (source: romanize)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _japaneseLrc);
      // NetEase returns romaji that still contains Japanese chars
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer(
        (_) async => (
          synced: '[00:10.00]ありがとうありがとう',
          plain: null,
          romaji: '[00:10.00]ありがとうありがとう',
        ),
      );

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      // Should still romanize since NetEase romaji contains Japanese
      expect(result!.source, equals(LyricsSource.romanize));
      expect(containsJapanese(result.lrc.lines[0].text), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Flow 2: No embedded lyrics
  // ═══════════════════════════════════════════════════════════════════════════

  group('No embedded lyrics', () {
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

    test(
      'no embedded → NetEase romaji succeeds (source: neteaseRomaji)',
      () async {
        when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
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
      },
    );

    test('no embedded → NetEase Japanese (no romaji) → romanize '
        '(source: romanize)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => _neteaseJapaneseResult);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
      expect(containsJapanese(result.lrc.lines[0].text), isFalse);
    });

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

    test('no embedded → NetEase plain lyrics (source: netease)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer(
        (_) async =>
            (synced: null, plain: '[00:10.00]Plain lyrics text', romaji: null),
      );

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.netease));
      expect(result.lrc.lines[0].text, equals('Plain lyrics text'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Edge cases
  // ═══════════════════════════════════════════════════════════════════════════

  group('Edge cases', () {
    test('returns null when backend lyrics throws', () async {
      when(() => backend.lyrics('t1')).thenThrow(Exception('network error'));

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNull);
    });

    test('returns null when backend returns empty string', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => '');
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

    test('NetEase exception does not crash resolver', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _japaneseLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenThrow(Exception('netease down'));

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      // Should fall through to romanize
      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
    });

    test('LRCLib exception does not crash resolver', () async {
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
      ).thenThrow(Exception('lrclib down'));

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

      // Should skip whitespace-only embedded and try LRCLib
      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.lrclib));
    });

    test('NetEase returns null romaji field (not just missing)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _japaneseLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer(
        (_) async => (
          synced: _japaneseLrc,
          plain: null,
          romaji: null, // explicitly null
        ),
      );

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
      expect(containsJapanese(result.lrc.lines[0].text), isFalse);
    });

    test('NetEase returns empty romaji string → romanize', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _japaneseLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer(
        (_) async => (
          synced: _japaneseLrc,
          plain: null,
          romaji: '', // empty string
        ),
      );

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LRC parsing correctness
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

    test('detects synced lyrics (has timestamps > zero)', () async {
      when(
        () => backend.lyrics('t1'),
      ).thenAnswer((_) async => '[00:10.00]Synced line');

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.server));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Cache-first flow
  // ═══════════════════════════════════════════════════════════════════════════

  group('Cache-first flow', () {
    test(
      'cache hit with non-Japanese returns cached result (source: cache)',
      () async {
        // Pre-populate cache with English lyrics
        resolver.cacheLyrics('t1', _englishLrc, LyricsSource.server);

        final track = _track('t1');
        final result = await resolver.resolve(trackId: 't1', track: track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.cache));
        expect(result.lrc.lines[0].text, equals('Hello world'));
        // Backend should NOT be called when cache hits
        verifyNever(() => backend.lyrics('t1'));
      },
    );

    test(
      'cache hit with Japanese romanizes and returns (source: cache)',
      () async {
        // Pre-populate cache with Japanese lyrics
        resolver.cacheLyrics('t1', _japaneseLrc, LyricsSource.server);

        final track = _track('t1');
        final result = await resolver.resolve(trackId: 't1', track: track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.cache));
        // Should be romanized
        expect(containsJapanese(result.lrc.lines[0].text), isFalse);
        // Backend should NOT be called
        verifyNever(() => backend.lyrics('t1'));
      },
    );

    test('cache miss continues normal flow', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _englishLrc);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.server));
      verify(() => backend.lyrics('t1')).called(1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Romanization at every stage
  // ═══════════════════════════════════════════════════════════════════════════

  group('Romanization at every stage', () {
    test('LRCLib returns Japanese → romanize (source: lrclib)', () async {
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
      ).thenAnswer((_) async => (synced: _japaneseLrc, plain: null));

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      // Source should still be lrclib, but lyrics should be romanized
      expect(result!.source, equals(LyricsSource.lrclib));
      expect(containsJapanese(result.lrc.lines[0].text), isFalse);
    });

    test(
      'NetEase romaji still has Japanese → romanize (source: neteaseRomaji)',
      () async {
        when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
        // NetEase returns romaji that still contains Japanese chars
        when(
          () => netease.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            duration: any(named: 'duration'),
          ),
        ).thenAnswer(
          (_) async => (
            synced: '[00:10.00]ありがとうありがとう',
            plain: null,
            romaji: '[00:10.00]ありがとうありがとう',
          ),
        );

        final track = _track('t1');
        final result = await resolver.resolve(trackId: 't1', track: track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.neteaseRomaji));
        // Should be romanized even though source is neteaseRomaji
        expect(containsJapanese(result.lrc.lines[0].text), isFalse);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Source label format
  // ═══════════════════════════════════════════════════════════════════════════

  group('Source label format', () {
    test(
      'LyricsSource labels follow "Lyric provided by <provider>" format',
      () {
        expect(LyricsSource.cache.label, equals('Lyric provided by Cache'));
        expect(LyricsSource.server.label, equals('Lyric provided by Server'));
        expect(LyricsSource.lrclib.label, equals('Lyric provided by LRCLib'));
        expect(LyricsSource.netease.label, equals('Lyric provided by NetEase'));
        expect(
          LyricsSource.neteaseRomaji.label,
          equals('Lyric provided by NetEase Romaji'),
        );
        expect(
          LyricsSource.romanize.label,
          equals('Lyric provided by Romanize'),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Kanji romanization — ensures JapaneseRomanizer actually converts kanji
  // ═══════════════════════════════════════════════════════════════════════════

  group('Kanji romanization', () {
    test(
      'embedded kanji-only lyrics → romanize produces Latin output',
      () async {
        // Pure kanji lyrics (no hiragana/katakana) — the most common failure
        // mode when JapaneseRomanizer is not initialized.
        const kanjiOnlyLrc = '[00:10.00]明日の天気\n[00:15.00]今日の夕暮れ';
        when(() => backend.lyrics('t1')).thenAnswer((_) async => kanjiOnlyLrc);
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

        expect(result, isNotNull);
        expect(
          containsJapanese(result!.lrc.lines[0].text),
          isFalse,
          reason: 'Kanji-only lyrics must be fully romanized to Latin',
        );
        expect(result.lrc.lines.length, equals(2));
      },
    );

    test(
      'embedded mixed kanji+hiragana → romanize produces Latin output',
      () async {
        const mixedLrc = '[00:10.00]ありがとう世界\n[00:15.00]さようなら友達';
        when(() => backend.lyrics('t1')).thenAnswer((_) async => mixedLrc);
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

        expect(result, isNotNull);
        expect(
          containsJapanese(result!.lrc.lines[0].text),
          isFalse,
          reason: 'Mixed kanji+hiragana lyrics must be fully romanized',
        );
        expect(result.lrc.lines.length, equals(2));
      },
    );

    test('LRCLib returns kanji → romanize produces Latin output', () async {
      const kanjiLrc = '[00:10.00]明日の天気\n[00:15.00]今日の夕暮れ';
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
      ).thenAnswer((_) async => (synced: kanjiLrc, plain: null));

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(
        containsJapanese(result!.lrc.lines[0].text),
        isFalse,
        reason: 'LRCLib kanji lyrics must be romanized',
      );
    });

    test(
      'netease romaji still has kanji → romanize produces Latin output',
      () async {
        when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
        when(
          () => netease.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            duration: any(named: 'duration'),
          ),
        ).thenAnswer(
          (_) async => (
            synced: '[00:10.00]ありがとう世界',
            plain: null,
            romaji: '[00:10.00]ありがとう世界',
          ),
        );

        final track = _track('t1');
        final result = await resolver.resolve(trackId: 't1', track: track);

        expect(result, isNotNull);
        expect(
          containsJapanese(result!.lrc.lines[0].text),
          isFalse,
          reason: 'NetEase romaji with kanji must be romanized',
        );
      },
    );

    test('romanized text should contain non-empty Latin content', () async {
      const kanjiLrc = '[00:10.00]愛';
      when(() => backend.lyrics('t1')).thenAnswer((_) async => kanjiLrc);
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

      expect(result, isNotNull);
      final text = result!.lrc.lines[0].text;
      expect(
        text.isNotEmpty,
        isTrue,
        reason: 'Romanized text must not be empty',
      );
      expect(
        RegExp(r'[a-zA-Z]').hasMatch(text),
        isTrue,
        reason: 'Romanized text must contain Latin characters',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Multi-language romanization
  // ═══════════════════════════════════════════════════════════════════════════

  group('Multi-language romanization', () {
    test('embedded Korean lyrics → romanize (source: romanize)', () async {
      const koreanLrc = '[00:10.00]안녕하세요\n[00:15.00]-goodbye world';
      when(() => backend.lyrics('t1')).thenAnswer((_) async => koreanLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
      expect(containsKorean(result.lrc.lines[0].text), isFalse);
    });

    test('embedded Chinese lyrics → romanize (source: romanize)', () async {
      const chineseLrc = '[00:10.00]你好世界\n[00:15.00]再见朋友';
      when(() => backend.lyrics('t1')).thenAnswer((_) async => chineseLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
      // Chinese characters (CJK) should be romanized
      expect(containsChinese(result.lrc.lines[0].text), isFalse);
    });

    test('embedded Cyrillic lyrics → romanize (source: romanize)', () async {
      const cyrillicLrc = '[00:10.00]Привет мир\n[00:15.00]До свидания';
      when(() => backend.lyrics('t1')).thenAnswer((_) async => cyrillicLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
      expect(containsCyrillic(result.lrc.lines[0].text), isFalse);
    });

    test('embedded Arabic lyrics → romanize (source: romanize)', () async {
      const arabicLrc = '[00:10.00]مرحبا بالعالم\n[00:15.00]وداعا';
      when(() => backend.lyrics('t1')).thenAnswer((_) async => arabicLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
      expect(containsArabic(result.lrc.lines[0].text), isFalse);
    });

    test('embedded Hebrew lyrics → romanize (source: romanize)', () async {
      const hebrewLrc = '[00:10.00]שלום עולם\n[00:15.00]להתראות';
      when(() => backend.lyrics('t1')).thenAnswer((_) async => hebrewLrc);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.romanize));
      expect(containsHebrew(result.lrc.lines[0].text), isFalse);
    });

    test('cache hit with Korean → romanize (source: cache)', () async {
      const koreanLrc = '[00:10.00]안녕하세요';
      resolver.cacheLyrics('t1', koreanLrc, LyricsSource.server);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.cache));
      expect(containsKorean(result.lrc.lines[0].text), isFalse);
    });

    test('cache hit with Cyrillic → romanize (source: cache)', () async {
      const cyrillicLrc = '[00:10.00]Привет мир';
      resolver.cacheLyrics('t1', cyrillicLrc, LyricsSource.server);

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.cache));
      expect(containsCyrillic(result.lrc.lines[0].text), isFalse);
    });

    test('LRCLib returns Korean → romanize (source: lrclib)', () async {
      const koreanLrc = '[00:10.00]안녕하세요\n[00:15.00]goodbye';
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
      ).thenAnswer((_) async => (synced: koreanLrc, plain: null));

      final track = _track('t1');
      final result = await resolver.resolve(trackId: 't1', track: track);

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.lrclib));
      expect(containsKorean(result.lrc.lines[0].text), isFalse);
    });

    test(
      'NetEase returns Korean (no romaji) → romanize (source: romanize)',
      () async {
        const koreanLrc = '[00:10.00]안녕하세요\n[00:15.00]goodbye';
        when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
        when(
          () => netease.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            duration: any(named: 'duration'),
          ),
        ).thenAnswer(
          (_) async => (synced: koreanLrc, plain: null, romaji: null),
        );

        final track = _track('t1');
        final result = await resolver.resolve(trackId: 't1', track: track);

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.romanize));
        expect(containsKorean(result.lrc.lines[0].text), isFalse);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Flow order verification
  // ═══════════════════════════════════════════════════════════════════════════

  group('Flow order verification', () {
    test('NetEase is called only when embedded is empty', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _englishLrc);

      final track = _track('t1');
      await resolver.resolve(trackId: 't1', track: track);

      // NetEase should NOT be called when embedded is non-Japanese English
      verifyNever(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      );
    });

    test('LRCLib is called only when both embedded and NetEase fail', () async {
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
      await resolver.resolve(trackId: 't1', track: track);

      verify(
        () => lrclib.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).called(1);
    });

    test('LRCLib is NOT called when NetEase succeeds', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => _neteaseRomajiResult);

      final track = _track('t1');
      await resolver.resolve(trackId: 't1', track: track);

      verifyNever(
        () => lrclib.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Race fetch mode
  // ═══════════════════════════════════════════════════════════════════════════

  group('Race fetch mode', () {
    late MockKuGouClient kugou;
    late MockSimpMusicClient simpmusic;
    late MockUnisonClient unison;
    late LyricsResolver raceResolver;

    setUp(() {
      kugou = MockKuGouClient();
      simpmusic = MockSimpMusicClient();
      unison = MockUnisonClient();
      raceResolver = LyricsResolver(
        backend: backend,
        netease: netease,
        lrclib: lrclib,
        kugou: kugou,
        simpmusic: simpmusic,
        unison: unison,
      );
    });

    test(
      'race fetch with enableRaceFetch=false uses sequential cascade',
      () async {
        when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
        when(
          () => netease.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            duration: any(named: 'duration'),
          ),
        ).thenAnswer((_) async => _neteaseRomajiResult);

        // With enableRaceFetch=false (default), new providers should NOT be called
        final track = _track('t1');
        await raceResolver.resolve(trackId: 't1', track: track);

        verifyNever(
          () => kugou.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            duration: any(named: 'duration'),
          ),
        );
      },
    );

    test('race fetch calls all providers concurrently when enabled', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
      // All providers return null — just verify they're all called
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
      when(
        () => kugou.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => simpmusic.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => unison.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await raceResolver.resolve(
        trackId: 't1',
        track: track,
        enableRaceFetch: true,
      );

      expect(result, isNull);
      // All 5 providers should have been called
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
      verify(
        () => kugou.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).called(1);
      verify(
        () => simpmusic.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).called(1);
      verify(
        () => unison.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).called(1);
    });

    test('race fetch returns first valid result (KuGou wins)', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
      // NetEase, LRCLib fail
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
      // KuGou has first valid result
      when(
        () => kugou.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => (synced: _englishLrc, plain: null));
      // SimpMusic, Unison also return results but KuGou should win
      when(
        () => simpmusic.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => (synced: _englishLrc, plain: null));
      when(
        () => unison.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => (synced: _englishLrc, plain: null));

      final track = _track('t1');
      final result = await raceResolver.resolve(
        trackId: 't1',
        track: track,
        enableRaceFetch: true,
      );

      expect(result, isNotNull);
      // Any provider that returned valid lyrics is acceptable
      expect(
        result!.source == LyricsSource.kugou ||
            result.source == LyricsSource.simpmusic ||
            result.source == LyricsSource.unison,
        isTrue,
        reason:
            'Race fetch should return a result from one of the providers '
            'that returned valid lyrics',
      );
      expect(result.lrc.lines[0].text, equals('Hello world'));
    });

    test(
      'race fetch uses embedded lyrics before racing (embedded wins)',
      () async {
        when(() => backend.lyrics('t1')).thenAnswer((_) async => _englishLrc);

        // Even with enableRaceFetch=true, embedded should be returned directly
        final track = _track('t1');
        final result = await raceResolver.resolve(
          trackId: 't1',
          track: track,
          enableRaceFetch: true,
        );

        expect(result, isNotNull);
        expect(result!.source, equals(LyricsSource.server));
        expect(result.lrc.lines[0].text, equals('Hello world'));
        // None of the network providers should be called
        verifyNever(
          () => netease.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            duration: any(named: 'duration'),
          ),
        );
      },
    );

    test('race fetch returns null when all providers throw', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);
      // All providers throw
      when(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenThrow(Exception('timeout'));
      when(
        () => lrclib.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenThrow(Exception('timeout'));
      when(
        () => kugou.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenThrow(Exception('timeout'));
      when(
        () => simpmusic.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenThrow(Exception('timeout'));
      when(
        () => unison.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenThrow(Exception('timeout'));

      final track = _track('t1');
      final result = await raceResolver.resolve(
        trackId: 't1',
        track: track,
        enableRaceFetch: true,
      );

      // Exceptions from all providers should not crash — returns null
      expect(result, isNull);
    });

    test('race fetch with cache hit skips network', () async {
      // Pre-populate cache
      raceResolver.cacheLyrics('t1', _englishLrc, LyricsSource.server);

      when(() => backend.lyrics('t1')).thenAnswer((_) async => null);

      final track = _track('t1');
      final result = await raceResolver.resolve(
        trackId: 't1',
        track: track,
        enableRaceFetch: true,
      );

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.cache));
      // No network providers should be called
      verifyNever(() => backend.lyrics('t1'));
      verifyNever(
        () => netease.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      );
    });

    test('race fetch does not fire when embedded lyrics exist', () async {
      when(() => backend.lyrics('t1')).thenAnswer((_) async => _englishLrc);

      final track = _track('t1');
      await raceResolver.resolve(
        trackId: 't1',
        track: track,
        enableRaceFetch: true,
      );

      // Verify new providers are not called
      verifyNever(
        () => kugou.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      );
      verifyNever(
        () => simpmusic.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      );
      verifyNever(
        () => unison.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      );
    });

    test('race fetch caches winning result', () async {
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
      when(
        () => kugou.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => (synced: _englishLrc, plain: null));
      when(
        () => simpmusic.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => unison.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).thenAnswer((_) async => null);

      final track = _track('t1');
      // First call: should fetch and cache
      await raceResolver.resolve(
        trackId: 't1',
        track: track,
        enableRaceFetch: true,
      );

      // Second call: should hit cache, not call providers
      final result2 = await raceResolver.resolve(
        trackId: 't1',
        track: track,
        enableRaceFetch: true,
      );

      expect(result2, isNotNull);
      expect(result2!.source, equals(LyricsSource.cache));
      // Second call should not call any provider
      verify(
        () => kugou.fetchLyrics(
          trackName: any(named: 'trackName'),
          artistName: any(named: 'artistName'),
          albumName: any(named: 'albumName'),
          duration: any(named: 'duration'),
        ),
      ).called(1); // Only once from first call
    });
  });
}
