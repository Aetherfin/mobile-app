import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/client.dart';
import 'package:aetherfin/core/jellyfin/models/server.dart';

JellyfinClient _client({
  String baseUrl = 'http://srv:8096',
  String? token,
  String? userId,
}) {
  return JellyfinClient(
    server: JellyfinServer(baseUrl: baseUrl, name: 'srv'),
    deviceId: 'dev-1',
    accessToken: token,
    userId: userId,
  );
}

void main() {
  group('trackStreamUrl', () {
    test('omits api_key — auth rides on Authorization header now', () {
      final url = _client(token: 't-abc', userId: 'u-1')
          .trackStreamUrl('track-1', maxBitrateKbps: 320);
      expect(url.contains('api_key='), isFalse,
          reason: 'Token must not be embedded in the URL.');
      expect(url.contains('Static=true'), isTrue);
      expect(url.contains('Audio/track-1/stream'), isTrue);
      expect(url.contains('MaxStreamingBitrate=320000'), isTrue);
    });

    test('URL-encodes path + query values', () {
      // Track IDs with `+` `=` `&` are unusual but exist in some libraries.
      final url = _client(userId: 'a+b=c&d').trackStreamUrl('xyz');
      final uri = Uri.parse(url);
      // The decoded userId must round-trip exactly through `queryParameters`.
      expect(uri.queryParameters['UserId'], 'a+b=c&d');
      // Raw query string must NOT contain the unencoded `+` / `=` / `&`
      // in the middle of the value.
      expect(uri.query.contains('UserId=a+b=c'), isFalse,
          reason: 'Plus / equals must be percent-encoded.');
    });

    test('preserves nested base path (e.g. /jellyfin)', () {
      final url = _client(baseUrl: 'https://host.tld/jellyfin', userId: 'u-1')
          .trackStreamUrl('track-2');
      expect(url.startsWith('https://host.tld/jellyfin/Audio/track-2/stream'),
          isTrue,
          reason: 'Server-relative base path must survive Uri.replace.');
    });

    test('handles trailing slash on baseUrl', () {
      final url = _client(baseUrl: 'https://host.tld/', userId: 'u-1')
          .trackStreamUrl('track-3');
      expect(url.startsWith('https://host.tld/Audio/track-3/stream'), isTrue);
      expect(url.contains('//Audio'), isFalse,
          reason: 'Must not produce `//Audio` from a trailing slash.');
    });
  });

  group('authHeaders', () {
    test('returns Authorization with all required fields when authed', () {
      final headers =
          _client(token: 't-abc', userId: 'u-1').authHeaders;
      final auth = headers['Authorization'] ?? '';
      expect(auth.startsWith('MediaBrowser '), isTrue);
      expect(auth.contains('UserId="u-1"'), isTrue);
      expect(auth.contains('Token="t-abc"'), isTrue);
      expect(auth.contains('Client="Aetherfin"'), isTrue);
      expect(auth.contains('Device="Android"'), isTrue);
      expect(auth.contains('DeviceId="dev-1"'), isTrue);
      expect(auth.contains('Version="0.1.0"'), isTrue);
    });

    test('omits Authorization entirely when no token', () {
      final headers = _client().authHeaders;
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('escapes quote / backslash / CR / LF in user-supplied values', () {
      // A malicious server returns a userId with `"` so the attacker
      // could inject Token="…", Client="evil" if we didn't escape.
      final auth = _client(token: 'safe', userId: r'evil",X="y')
          .authHeaders['Authorization']!;
      // Must not introduce a real `X="y` field — the injection should be
      // neutralized by escaping the inner quotes.
      expect(auth.contains(', X="y'), isFalse);
      // Newlines must be stripped so header smuggling is impossible.
      final crlf = _client(token: "abc\r\nX-Evil: hi", userId: 'u')
          .authHeaders['Authorization']!;
      expect(crlf.contains('\n'), isFalse);
      expect(crlf.contains('\r'), isFalse);
    });
  });
}
