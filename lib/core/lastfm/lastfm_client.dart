import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../utils/log.dart';
import '../network/shared_dio_client.dart';

/// Lightweight Last.fm API client for fetching similar tracks and scrobbling.
///
/// Uses `track.getSimilar`, `auth.getToken` + `auth.getSession`,
/// `track.updateNowPlaying`, and `track.scrobble` endpoints.
class LastFmClient {
  LastFmClient({
    required String apiKey,
    String? apiSecret,
    String? sessionKey,
    void Function(String message)? onStatus,
    Dio? dio,
  }) : _apiKey = apiKey,
       _apiSecret = apiSecret,
       _sessionKey = sessionKey,
       _onStatus = onStatus,
       _dio =
           dio ??
           SharedDioClient().createWithOptions(
             BaseOptions(
               baseUrl: 'https://ws.audioscrobbler.com/2.0/',
               connectTimeout: const Duration(seconds: 5),
               sendTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 15),
             ),
           );

  final String _apiKey;
  final String? _apiSecret;
  final String? _sessionKey;
  final void Function(String message)? _onStatus;

  final Dio _dio;

  /// Close the underlying HTTP client and release resources.
  void close() {
    _dio.close(force: true);
  }

  /// Helper to calculate MD5 request signature for authenticated endpoints.
  /// Concatenates parameters alphabetically by name, appends secret, and hashes.
  String _generateSignature(Map<String, String> params) {
    final secret = _apiSecret;
    if (secret == null) {
      throw StateError('API secret is required for signing requests');
    }
    final sortedKeys = params.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in sortedKeys) {
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(secret);
    final bytes = utf8.encode(buffer.toString());
    return md5.convert(bytes).toString();
  }

  /// Fetch a request token via [auth.getToken].
  /// Throws on failure.
  Future<String> getToken() async {
    final params = <String, String>{
      'method': 'auth.getToken',
      'api_key': _apiKey,
    };
    final sig = _generateSignature(params);
    params['api_sig'] = sig;
    params['format'] = 'json';

    try {
      final res = await _dio.get('/', queryParameters: params);
      final data = res.data;
      if (data is Map) {
        final token = data['token'] as String?;
        if (token != null) return token;
      }
      throw Exception('getToken failed: missing token in response');
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('message')) {
        throw Exception(data['message']);
      }
      throw Exception(e.message ?? 'Network error getting token');
    }
  }

  /// URL where the user must authorize the [token] in their browser.
  String authPageUrl(String token) =>
      'https://www.last.fm/api/auth/?api_key=$_apiKey&token=$token';

  /// Exchange an authorized [token] for a permanent session key
  /// via [auth.getSession].
  ///
  /// Returns the session key string on success.
  /// Throws if the token has not been authorized yet or on network error.
  Future<String> getSession(String token) async {
    final params = <String, String>{
      'method': 'auth.getSession',
      'token': token,
      'api_key': _apiKey,
    };
    final sig = _generateSignature(params);
    params['api_sig'] = sig;
    params['format'] = 'json';

    try {
      final res = await _dio.get('/', queryParameters: params);
      final data = res.data;
      if (data is Map) {
        final session = data['session'] as Map?;
        if (session != null) {
          final key = session['key'] as String?;
          final name = session['name'] as String?;
          if (key != null) {
            // Wrap both key and username for the caller
            _lastSessionName = name ?? '';
            return key;
          }
          if (name != null) throw Exception('Token not yet authorized');
        }
      }
      throw Exception('getSession failed: missing session key');
    } on DioException catch (e) {
      // On 4 — token not yet authorized
      final data = e.response?.data;
      if (data is Map && data.containsKey('message')) {
        throw Exception(data['message']);
      }
      throw Exception(e.message ?? 'Network error getting session');
    }
  }

  /// The username returned by the last [getSession] call. Empty if unset.
  String get lastSessionName => _lastSessionName;
  String _lastSessionName = '';

  /// Verify the session is valid and return the authenticated user's real
  /// Last.fm username by calling [user.getInfo].
  ///
  /// Returns the username string (e.g. "my_lastfm_account") on success.
  /// Returns empty string on failure.
  Future<String> verifySession() async {
    final sk = _sessionKey;
    if (sk == null) return '';

    final params = <String, String>{
      'method': 'user.getInfo',
      'api_key': _apiKey,
      'sk': sk,
    };
    final sig = _generateSignature(params);
    params['api_sig'] = sig;
    params['format'] = 'json';

    try {
      final res = await _dio.get('/', queryParameters: params);
      final data = res.data;
      if (data is Map) {
        final user = data['user'] as Map?;
        if (user != null) {
          final name = user['name'] as String?;
          if (name != null && name.isNotEmpty) {
            _lastSessionName = name;
            return name;
          }
        }
      }
      _reportStatus(false, 'verifySession: $data');
      return '';
    } on Exception catch (e, stack) {
      _reportStatus(false, 'verifySession: $e');
      afLog(
        'error',
        'Last.fm verifySession failed',
        error: e,
        stackTrace: stack,
      );
      return '';
    }
  }

  void _reportStatus(bool ok, String msg) =>
      _onStatus?.call('${ok ? 'OK' : 'ERROR'} $msg');

  /// Update the "Now Playing" track on the user's Last.fm profile.
  Future<void> updateNowPlaying({
    required String artist,
    required String track,
    String? album,
    Duration? duration,
  }) async {
    final sk = _sessionKey;
    if (sk == null) {
      _reportStatus(false, 'nowplaying skipped: no session key');
      return;
    }

    final params = {
      'method': 'track.updateNowPlaying',
      'artist': artist,
      'track': track,
      'api_key': _apiKey,
      'sk': sk,
      if (album != null && album.isNotEmpty) 'album': album,
      if (duration != null && duration.inSeconds > 0)
        'duration': duration.inSeconds.toString(),
    };

    try {
      final sig = _generateSignature(params);
      params['api_sig'] = sig;
      params['format'] = 'json';

      final res = await _dio.post(
        '/',
        data: params,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = res.data;
      if (body is Map && body['lfm'] is Map) {
        final lfm = body['lfm'] as Map;
        if (lfm['status'] == 'failed') {
          final code = lfm['error'];
          final msg = lfm['message'] ?? 'unknown error';
          _reportStatus(false, 'nowplaying (code $code): $msg');
          afLog('error', 'Last.fm now playing rejected: $msg (code $code)');
          return;
        }
      }
      _reportStatus(true, 'nowplaying: $artist - $track');
      afLog('data', 'Last.fm now playing updated: $artist - $track');
    } on Exception catch (e, stack) {
      _reportStatus(false, 'nowplaying: $e');
      afLog('error', 'Last.fm now playing failed', error: e, stackTrace: stack);
    }
  }

  /// Report a [Duration] to Last.fm on the following [artist], [track].
  /// This submits the track as listened. Only scrobble if the listener has
  /// listened for 50% of the track or 4 minutes (for very long songs).
  Future<void> scrobble({
    required String artist,
    required String track,
    required int timestamp, // Unix timestamp in seconds
    String? album,
    Duration? duration,
  }) async {
    final sk = _sessionKey;
    if (sk == null) {
      _reportStatus(false, 'scrobble skipped: no session key');
      return;
    }

    final params = {
      'method': 'track.scrobble',
      'artist[0]': artist,
      'track[0]': track,
      'timestamp[0]': timestamp.toString(),
      'api_key': _apiKey,
      'sk': sk,
      if (album != null && album.isNotEmpty) 'album[0]': album,
      if (duration != null && duration.inSeconds > 0)
        'duration[0]': duration.inSeconds.toString(),
    };

    try {
      final sig = _generateSignature(params);
      params['api_sig'] = sig;
      params['format'] = 'json';

      final res = await _dio.post(
        '/',
        data: params,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = res.data;
      if (body is Map && body['scrobbles'] is Map) {
        final scrobbles = body['scrobbles'] as Map;
        final attr = scrobbles['@attr'] as Map?;
        if (attr != null && attr['accepted'] == 1) {
          _reportStatus(true, 'scrobble: $artist - $track');
          afLog('data', 'Last.fm scrobble submitted: $artist - $track');
        } else {
          final scrobble = scrobbles['scrobble'] as Map?;
          final ignoredMsg = scrobble?['ignoredMessage'] as Map?;
          final code = ignoredMsg?['code'] ?? 'unknown';
          final text = ignoredMsg?['#text'] ?? '';
          _reportStatus(false, 'scrobble ignored (code $code): $text');
          afLog('error', 'Last.fm scrobble ignored: code=$code msg=$text');
        }
      } else {
        _reportStatus(false, 'scrobble: unexpected response');
        afLog('error', 'Last.fm scrobble response parse failed: $body');
      }
    } on Exception catch (e, stack) {
      _reportStatus(false, 'scrobble: $e');
      afLog('error', 'Last.fm scrobble failed', error: e, stackTrace: stack);
    }
  }

  /// Fetch similar tracks from Last.fm for [artistName] / [trackTitle].
  /// Returns list of `{artist, title}` pairs. Empty on failure.
  Future<List<({String artist, String title})>> getSimilar({
    required String artistName,
    required String trackTitle,
    int limit = 30,
  }) async {
    try {
      final res = await _dio.get(
        '/',
        queryParameters: {
          'method': 'track.getSimilar',
          'artist': artistName,
          'track': trackTitle,
          'api_key': _apiKey,
          'format': 'json',
          'limit': limit,
        },
      );
      final data = res.data;
      if (data is! Map) return [];
      final similartracks = data['similartracks'] as Map?;
      if (similartracks == null) return [];
      final tracks = similartracks['track'] as List?;
      if (tracks == null) return [];
      return tracks.map((t) {
        final name = (t as Map)['name'] as String? ?? '';
        final artist = (t['artist'] as Map?)?['name'] as String? ?? '';
        return (artist: artist, title: name);
      }).toList();
    } on Exception catch (e, stack) {
      afLog('error', 'Last.fm getSimilar failed', error: e, stackTrace: stack);
      return [];
    }
  }

  /// Love a track on Last.fm (adds to loved tracks).
  Future<void> love({required String artist, required String track}) async {
    final sk = _sessionKey;
    if (sk == null) return;

    final params = {
      'method': 'track.love',
      'artist': artist,
      'track': track,
      'api_key': _apiKey,
      'sk': sk,
    };

    try {
      final sig = _generateSignature(params);
      params['api_sig'] = sig;
      params['format'] = 'json';

      await _dio.post(
        '/',
        data: params,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      afLog('data', 'Last.fm loved track: $artist - $track');
    } on Exception catch (e, stack) {
      afLog('error', 'Last.fm love track failed', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Unlove a track on Last.fm.
  Future<void> unlove({required String artist, required String track}) async {
    final sk = _sessionKey;
    if (sk == null) return;

    final params = {
      'method': 'track.unlove',
      'artist': artist,
      'track': track,
      'api_key': _apiKey,
      'sk': sk,
    };

    try {
      final sig = _generateSignature(params);
      params['api_sig'] = sig;
      params['format'] = 'json';

      await _dio.post(
        '/',
        data: params,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      afLog('data', 'Last.fm unloved track: $artist - $track');
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Last.fm unlove track failed',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Fetch user's loved tracks.
  Future<List<({String artist, String title})>> getLovedTracks({
    required String username,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get(
        '/',
        queryParameters: {
          'method': 'user.getLovedTracks',
          'user': username,
          'api_key': _apiKey,
          'format': 'json',
          'limit': limit,
        },
      );
      final data = res.data;
      if (data is! Map) return [];
      final lovedtracks = data['lovedtracks'] as Map?;
      if (lovedtracks == null) return [];
      final tracks = lovedtracks['track'] as List?;
      if (tracks == null) return [];
      return tracks.map((t) {
        final name = (t as Map)['name'] as String? ?? '';
        final artist = (t['artist'] as Map?)?['name'] as String? ?? '';
        return (artist: artist, title: name);
      }).toList();
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Last.fm getLovedTracks failed',
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  /// Fetch top tracks for a user over a given period.
  Future<List<({String artist, String title, int playCount})>> getTopTracks({
    required String username,
    String period = '7day',
    int limit = 10,
  }) async {
    try {
      final res = await _dio.get(
        '/',
        queryParameters: {
          'method': 'user.getTopTracks',
          'user': username,
          'api_key': _apiKey,
          'format': 'json',
          'period': period,
          'limit': limit,
        },
      );
      final data = res.data;
      if (data is! Map) return [];
      final toptracks = data['toptracks'] as Map?;
      if (toptracks == null) return [];
      final tracks = toptracks['track'] as List?;
      if (tracks == null) return [];
      return tracks.map((t) {
        final name = (t as Map)['name'] as String? ?? '';
        final artist = (t['artist'] as Map?)?['name'] as String? ?? '';
        final playCount = int.tryParse((t['playcount'] as String? ?? '0')) ?? 0;
        return (artist: artist, title: name, playCount: playCount);
      }).toList();
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Last.fm getTopTracks failed',
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  /// Fetch top artists for a user.
  Future<List<({String artist, int playCount})>> getTopArtists({
    required String username,
    String period = '7day',
    int limit = 10,
  }) async {
    try {
      final res = await _dio.get(
        '/',
        queryParameters: {
          'method': 'user.getTopArtists',
          'user': username,
          'api_key': _apiKey,
          'format': 'json',
          'period': period,
          'limit': limit,
        },
      );
      final data = res.data;
      if (data is! Map) return [];
      final topartists = data['topartists'] as Map?;
      if (topartists == null) return [];
      final artists = topartists['artist'] as List?;
      if (artists == null) return [];
      return artists.map((t) {
        final name = (t as Map)['name'] as String? ?? '';
        final playCount = int.tryParse((t['playcount'] as String? ?? '0')) ?? 0;
        return (artist: name, playCount: playCount);
      }).toList();
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Last.fm getTopArtists failed',
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  /// Fetch top albums for a user.
  Future<List<({String artist, String album, int playCount, String? imageUrl})>>
  getTopAlbums({
    required String username,
    String period = '7day',
    int limit = 10,
  }) async {
    try {
      final res = await _dio.get(
        '/',
        queryParameters: {
          'method': 'user.getTopAlbums',
          'user': username,
          'api_key': _apiKey,
          'format': 'json',
          'period': period,
          'limit': limit,
        },
      );
      final data = res.data;
      if (data is! Map) return [];
      final topalbums = data['topalbums'] as Map?;
      if (topalbums == null) return [];
      final albums = topalbums['album'] as List?;
      if (albums == null) return [];
      return albums.map((t) {
        final name = (t as Map)['name'] as String? ?? '';
        final artist = (t['artist'] as Map?)?['name'] as String? ?? '';
        final playCount = int.tryParse((t['playcount'] as String? ?? '0')) ?? 0;
        final images = t['image'] as List?;
        String? imageUrl;
        if (images != null && images.isNotEmpty) {
          final xlImage = images.firstWhere(
            (img) =>
                (img as Map)['size'] == 'extralarge' || img['size'] == 'large',
            orElse: () => images.last,
          );
          if (xlImage is Map) {
            imageUrl = xlImage['#text'] as String?;
          }
        }
        return (
          artist: artist,
          album: name,
          playCount: playCount,
          imageUrl: imageUrl,
        );
      }).toList();
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Last.fm getTopAlbums failed',
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  /// Fetch artist information (biography, stats, etc.).
  Future<Map<String, dynamic>?> getArtistInfo({
    required String artistName,
  }) async {
    try {
      final res = await _dio.get(
        '/',
        queryParameters: {
          'method': 'artist.getInfo',
          'artist': artistName,
          'api_key': _apiKey,
          'format': 'json',
        },
      );
      final data = res.data;
      if (data is Map) {
        return data['artist'] as Map<String, dynamic>?;
      }
      return null;
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Last.fm getArtistInfo failed',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Fetch album information (wiki, stats, etc.).
  Future<Map<String, dynamic>?> getAlbumInfo({
    required String artistName,
    required String albumName,
  }) async {
    try {
      final res = await _dio.get(
        '/',
        queryParameters: {
          'method': 'album.getInfo',
          'artist': artistName,
          'album': albumName,
          'api_key': _apiKey,
          'format': 'json',
        },
      );
      final data = res.data;
      if (data is Map) {
        return data['album'] as Map<String, dynamic>?;
      }
      return null;
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Last.fm getAlbumInfo failed',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Fetch similar artists.
  Future<List<String>> getSimilarArtists({
    required String artistName,
    int limit = 10,
  }) async {
    try {
      final res = await _dio.get(
        '/',
        queryParameters: {
          'method': 'artist.getSimilar',
          'artist': artistName,
          'api_key': _apiKey,
          'format': 'json',
          'limit': limit,
        },
      );
      final data = res.data;
      if (data is! Map) return [];
      final similarartists = data['similarartists'] as Map?;
      if (similarartists == null) return [];
      final artists = similarartists['artist'] as List?;
      if (artists == null) return [];
      return artists
          .map((t) => (t as Map)['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Last.fm getSimilarArtists failed',
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }
}
