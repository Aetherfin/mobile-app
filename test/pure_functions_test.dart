import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/lyrics/lrc_parser.dart';
import 'package:aetherfin/utils/display_error.dart';
import 'package:aetherfin/utils/time_format.dart';
import 'package:aetherfin/utils/url.dart';

void main() {
  group('formatTrackDuration', () {
    test('mm:ss for sub-hour durations', () {
      expect(formatTrackDuration(Duration.zero), '00:00');
      expect(formatTrackDuration(const Duration(seconds: 7)), '00:07');
      expect(formatTrackDuration(const Duration(seconds: 75)), '01:15');
      expect(formatTrackDuration(const Duration(minutes: 42, seconds: 9)),
          '42:09');
    });

    test('hh:mm:ss once hours are present', () {
      expect(
          formatTrackDuration(
              const Duration(hours: 1, minutes: 2, seconds: 3)),
          '01:02:03');
      expect(formatTrackDuration(const Duration(hours: 13)), '13:00:00');
    });

    test('clamps negatives to zero', () {
      expect(formatTrackDuration(const Duration(seconds: -5)), '00:00');
    });
  });

  group('formatHourCount', () {
    test('returns minutes for sub-hour durations', () {
      expect(formatHourCount(Duration.zero), '0m');
      expect(formatHourCount(const Duration(minutes: 7)), '7m');
      expect(formatHourCount(const Duration(minutes: 59)), '59m');
    });

    test('rounds to whole hours once >= 1h', () {
      expect(formatHourCount(const Duration(minutes: 60)), '1h');
      expect(formatHourCount(const Duration(minutes: 89)), '1h');
      expect(formatHourCount(const Duration(minutes: 90)), '2h');
      expect(formatHourCount(const Duration(hours: 103)), '103h');
    });
  });

  group('formatCompactCount', () {
    test('< 1000: passes through', () {
      expect(formatCompactCount(0), '0');
      expect(formatCompactCount(42), '42');
      expect(formatCompactCount(999), '999');
    });

    test('1000–9999: one decimal K, truncated (never crosses tier)', () {
      expect(formatCompactCount(1000), '1.0K');
      expect(formatCompactCount(2247), '2.2K');
      // 9999 must NOT render as "10.0K" — the old toStringAsFixed-based
      // implementation rounded UP across the tier boundary which made
      // the column re-flow two characters wider one step before the
      // tier actually changed.
      expect(formatCompactCount(9999), '9.9K');
    });

    test('10K–999K: whole K, floored', () {
      expect(formatCompactCount(10_000), '10K');
      expect(formatCompactCount(12_400), '12K');
      // Truncation also kills the legacy "999K → 999K, 999_500 → 1000K"
      // round-up bug at the 1M boundary. 999_499 still fits in the K
      // tier; the very next value (1_000_000) crosses into M.
      expect(formatCompactCount(999_499), '999K');
    });

    test('millions', () {
      expect(formatCompactCount(1_200_000), '1.2M');
      expect(formatCompactCount(42_000_000), '42M');
    });
  });

  group('parseLrc', () {
    test('synced lines are sorted by timestamp', () {
      const src = '''
[00:12.50] second
[00:02.10] first
[00:30.00] third
''';
      final lrc = parseLrc(src);
      expect(lrc.lines.length, 3);
      expect(lrc.lines[0].text, 'first');
      expect(lrc.lines[0].start, const Duration(seconds: 2, milliseconds: 100));
      expect(lrc.lines[1].text, 'second');
      expect(lrc.lines[2].text, 'third');
    });

    test('multi-timestamp lines expand into multiple lines', () {
      const src = '[00:01.00][00:05.00][00:09.00] chorus';
      final lrc = parseLrc(src);
      expect(lrc.lines.length, 3);
      expect(lrc.lines.map((l) => l.text).toSet(), {'chorus'});
      expect(lrc.lines[0].start, const Duration(seconds: 1));
      expect(lrc.lines[1].start, const Duration(seconds: 5));
      expect(lrc.lines[2].start, const Duration(seconds: 9));
    });

    test('metadata is collected into Lrc.meta', () {
      const src = '''
[ti:My Title]
[ar:My Artist]
[00:00.00] hello
''';
      final lrc = parseLrc(src);
      expect(lrc.meta['ti'], 'My Title');
      expect(lrc.meta['ar'], 'My Artist');
      expect(lrc.lines.length, 1);
      expect(lrc.lines.first.text, 'hello');
    });

    test('unparseable lines are skipped, not crashed', () {
      const src = '''
random non-LRC line
[xx:xx.xx] also not valid
[00:01.00] valid
''';
      final lrc = parseLrc(src);
      expect(lrc.lines.length, 1);
      expect(lrc.lines.first.text, 'valid');
    });

    test('activeIndex returns the largest line <= position', () {
      const src = '''
[00:00.00] a
[00:05.00] b
[00:10.00] c
''';
      final lrc = parseLrc(src);
      expect(lrc.activeIndex(Duration.zero), 0);
      expect(lrc.activeIndex(const Duration(seconds: 3)), 0);
      expect(lrc.activeIndex(const Duration(seconds: 5)), 1);
      expect(lrc.activeIndex(const Duration(seconds: 9)), 1);
      expect(lrc.activeIndex(const Duration(seconds: 10)), 2);
      expect(lrc.activeIndex(const Duration(seconds: 999)), 2);
    });
  });

  group('redactSensitiveQueryParams', () {
    test('redacts Subsonic auth token, salt and username', () {
      final raw = Uri.parse(
        'https://navi.example/rest/ping.view'
        '?u=alice&t=deadbeef&s=cafe&c=Aetherfin&v=1.16.1&f=json',
      );
      final redacted = redactSensitiveQueryParams(raw);
      expect(redacted, contains('u=%5BREDACTED%5D'));
      expect(redacted, contains('t=%5BREDACTED%5D'));
      expect(redacted, contains('s=%5BREDACTED%5D'));
      expect(redacted, contains('c=Aetherfin'));
      expect(redacted, contains('v=1.16.1'));
      expect(redacted, isNot(contains('alice')));
      expect(redacted, isNot(contains('deadbeef')));
      expect(redacted, isNot(contains('cafe')));
    });

    test('redacts Jellyfin api_key', () {
      final raw = Uri.parse(
        'https://jelly.example/Audio/abc/stream'
        '?Static=true&api_key=secret123&UserId=u',
      );
      final redacted = redactSensitiveQueryParams(raw);
      expect(redacted, contains('api_key=%5BREDACTED%5D'));
      expect(redacted, contains('Static=true'));
      expect(redacted, contains('UserId=u'));
      expect(redacted, isNot(contains('secret123')));
    });

    test('passes through URIs without sensitive params untouched', () {
      final raw = 'https://example/path?foo=bar';
      expect(redactSensitiveQueryParams(raw), raw);
    });

    test('passes through plain strings without query params', () {
      expect(redactSensitiveQueryParams('https://example/path'),
          'https://example/path');
    });
  });

  group('stableImageCacheKey', () {
    test('produces the same key for two Subsonic URLs with different salts',
        () {
      // Real Subsonic getCoverArt URLs look like this — the only
      // difference between two requests for the same artwork is the
      // (u, t, s) triple. The cache key must collapse that to one slot.
      const a =
          'https://nav.example/rest/getCoverArt.view?u=alice&t=aaaaaaaa&s=salt1&v=1.16.1&c=Aetherfin&f=json&id=al-42&size=480';
      const b =
          'https://nav.example/rest/getCoverArt.view?u=alice&t=bbbbbbbb&s=salt2&v=1.16.1&c=Aetherfin&f=json&id=al-42&size=480';
      expect(stableImageCacheKey(a), stableImageCacheKey(b));
    });

    test('different cover IDs map to different keys', () {
      const a =
          'https://nav.example/rest/getCoverArt.view?u=alice&t=hash&s=salt&id=al-42&size=480';
      const b =
          'https://nav.example/rest/getCoverArt.view?u=alice&t=hash&s=salt&id=al-99&size=480';
      expect(stableImageCacheKey(a), isNot(equals(stableImageCacheKey(b))));
    });

    test('different sizes map to different keys (memCache hint)', () {
      const small =
          'https://nav.example/rest/getCoverArt.view?u=alice&t=h&s=s&id=al-42&size=120';
      const large =
          'https://nav.example/rest/getCoverArt.view?u=alice&t=h&s=s&id=al-42&size=480';
      expect(stableImageCacheKey(small),
          isNot(equals(stableImageCacheKey(large))));
    });

    test('strips Jellyfin api_key while keeping cover-art path + tag', () {
      const raw =
          'https://jf.example/Items/track-1/Images/Primary?tag=hash7&maxWidth=320&api_key=secret';
      final key = stableImageCacheKey(raw);
      expect(key, isNot(contains('api_key')));
      expect(key, isNot(contains('secret')));
      expect(key, contains('Items/track-1/Images/Primary'));
      expect(key, contains('tag=hash7'));
      expect(key, contains('maxWidth=320'));
    });

    test('passes through plain (non-query) URLs untouched', () {
      const raw = 'https://example/Items/x/Images/Primary';
      expect(stableImageCacheKey(raw), raw);
    });

    test('passes through file:// URLs untouched', () {
      const raw = 'file:///storage/emulated/0/Music/album/cover.jpg';
      expect(stableImageCacheKey(raw), raw);
    });
  });

  group('displayError', () {
    test('redacts sensitive query params on DioException with response', () {
      final dio = DioException(
        requestOptions: RequestOptions(
          path: '/rest/ping.view',
          baseUrl: 'https://nav.example',
          queryParameters: {
            'u': 'alice',
            't': 'deadbeef',
            's': 'cafe',
            'v': '1.16.1',
            'c': 'Aetherfin',
          },
        ),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/rest/ping.view'),
          statusCode: 500,
        ),
      );
      final out = displayError(dio, prefix: 'Search failed');
      expect(out, startsWith('Search failed: HTTP 500 from '));
      // None of the redacted token characters should remain.
      expect(out, isNot(contains('alice')));
      expect(out, isNot(contains('deadbeef')));
      expect(out, isNot(contains('cafe')));
      // Non-sensitive params still visible for debugging.
      expect(out, contains('c=Aetherfin'));
    });

    test('redacts api_key on Jellyfin DioException without response', () {
      final dio = DioException(
        requestOptions: RequestOptions(
          path: '/Users/u/Items',
          baseUrl: 'https://jelly.example',
          queryParameters: {
            'api_key': 'secret-token',
            'searchTerm': 'radiohead',
          },
        ),
        type: DioExceptionType.connectionError,
        message: 'Connection refused',
      );
      final out = displayError(dio);
      expect(out, isNot(contains('secret-token')));
      expect(out, contains('searchTerm=radiohead'));
      expect(out, contains('connectionError'));
      expect(out, contains('Connection refused'));
    });

    test('non-Dio errors pass through unchanged', () {
      expect(displayError(const FormatException('bad number'),
              prefix: 'Could not parse'),
          'Could not parse: FormatException: bad number');
      expect(
          displayError(StateError('nope')), 'Bad state: nope');
    });
  });
}
