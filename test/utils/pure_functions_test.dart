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
    });

    test('hh:mm:ss once hours are present', () {
      expect(
        formatTrackDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '01:02:03',
      );
    });
  });

  group('formatCompactCount', () {
    test('< 1000: passes through', () {
      expect(formatCompactCount(0), '0');
      expect(formatCompactCount(42), '42');
    });

    test('1000–9999: one decimal K', () {
      expect(formatCompactCount(1000), '1.0K');
      expect(formatCompactCount(2247), '2.2K');
    });

    test('boundaries and larger magnitudes', () {
      expect(formatCompactCount(9999), '9.9K');
      expect(formatCompactCount(10000), '10K');
      expect(formatCompactCount(999999), '999K');
      expect(formatCompactCount(1000000), '1.0M');
    });
  });

  group('parseLrc', () {
    test('synced lines are sorted by timestamp', () {
      const src = '[00:12.50] second\n[00:02.10] first\n[00:30.00] third\n';
      final lrc = parseLrc(src);
      expect(lrc.lines.length, 3);
      expect(lrc.lines[0].text, 'first');
      expect(lrc.lines[0].start, const Duration(seconds: 2, milliseconds: 100));
    });

    test('activeIndex returns the largest line <= position', () {
      const src = '[00:00.00] a\n[00:05.00] b\n[00:10.00] c\n';
      final lrc = parseLrc(src);
      expect(lrc.activeIndex(Duration.zero), 0);
      expect(lrc.activeIndex(const Duration(seconds: 5)), 1);
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
      expect(redacted, isNot(contains('alice')));
      expect(redacted, isNot(contains('deadbeef')));
    });

    test('redacts Jellyfin api_key', () {
      final raw = Uri.parse(
        'https://jelly.example/Audio/abc/stream'
        '?Static=true&api_key=secret123&UserId=u',
      );
      final redacted = redactSensitiveQueryParams(raw);
      expect(redacted, contains('api_key=%5BREDACTED%5D'));
      expect(redacted, isNot(contains('secret123')));
    });
  });

  group('stableImageCacheKey', () {
    test('produces the same key for two Subsonic URLs with different salts', () {
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
  });

  group('displayError', () {
    test('redacts sensitive query params on DioException', () {
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
      expect(out, isNot(contains('alice')));
      expect(out, isNot(contains('deadbeef')));
    });
  });
}
