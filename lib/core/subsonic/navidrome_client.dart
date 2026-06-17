import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/quality.dart';
import '../jellyfin/models/server.dart';
import '../network/shared_dio_client.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'client.dart';

/// A native Navidrome REST client that subclasses [SubsonicClient]
/// to handle authentication and queue sync via Navidrome's native REST endpoints.
class NavidromeClient extends SubsonicClient {
  NavidromeClient({
    required super.server,
    required super.username,
    required super.password,
    required super.clientVersion,
  }) : _ndDio = SharedDioClient().createWithOptions(
         BaseOptions(
           baseUrl: _buildNdBaseUrl(server.baseUrl),
           connectTimeout: const Duration(seconds: 5),
           sendTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 15),
           headers: {
             'User-Agent': 'Aetherfin/$clientVersion (Android)',
             'Accept': 'application/json',
           },
         ),
       ) {
    _ndDio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              error.requestOptions.extra['_nd401Retry'] != true) {
            _ndToken = null;
            error.requestOptions.extra['_nd401Retry'] = true;
            try {
              await _ensureNdAuthenticated();
              final response = await _ndDio.fetch(error.requestOptions);
              handler.resolve(response);
              return;
            } on Exception catch (_) {
              // Re-auth failed — pass original error to next handler
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _ndDio;

  @visibleForTesting
  Dio get ndDio => _ndDio;

  String? _ndToken;
  bool _isAuthenticating = false;
  Completer<void>? _authCompleter;

  static String _buildNdBaseUrl(String baseUrl) {
    final b = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return '${b}api/';
  }

  Future<void> _ensureNdAuthenticated() async {
    if (_ndToken != null) return;
    if (_isAuthenticating) {
      final completer = _authCompleter;
      if (completer != null) {
        await completer.future;
      }
      return;
    }
    _isAuthenticating = true;
    _authCompleter = Completer<void>();
    try {
      if (serverTypeString == null) {
        // ping() populates serverTypeString and serverVersionString
        await ping();
      }

      if (serverTypeString?.toLowerCase() != 'navidrome') {
        throw StateError(
          'Connected server is not Navidrome (type: $serverTypeString)',
        );
      }

      await _loginNavidrome();
      _authCompleter?.complete();
    } on Exception catch (e, s) {
      _authCompleter?.completeError(e, s);
      rethrow;
    } finally {
      _isAuthenticating = false;
      _authCompleter = null;
    }
  }

  Future<void> _loginNavidrome() async {
    final pwd = utf8.decode(passwordBytes);
    afLog('subsonic', 'Logging in to Navidrome native REST API');
    try {
      final response = await _ndDio.post(
        'auth/login',
        data: {'username': username, 'password': pwd},
      );
      final token = response.data['token'] as String?;
      if (token == null || token.isEmpty) {
        throw StateError('Navidrome token was null or empty in login response');
      }
      _ndToken = token;
      _ndDio.options.headers['x-nd-authorization'] = 'Bearer $_ndToken';
      afLog('subsonic', 'Navidrome native REST API authenticated successfully');
    } on DioException catch (e, stack) {
      afLog(
        'subsonic',
        'Navidrome native REST API login failed: ${e.message}',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  Future<JellyfinServer> ping() async {
    final res = await super.ping();
    if (serverTypeString?.toLowerCase() == 'navidrome' && _ndToken == null) {
      try {
        await _loginNavidrome();
      } on Exception catch (e, stack) {
        afLog(
          'subsonic',
          'Failed to authenticate Navidrome REST during ping: $e',
          error: e,
          stackTrace: stack,
        );
        // Don't rethrow — the Subsonic API ping succeeded, so the
        // connection is usable for Subsonic operations even if the
        // Navidrome REST endpoint is unavailable.
      }
    }
    return res;
  }

  @override
  Future<void> savePlayQueue(
    List<String> trackIds, {
    int? currentIndex,
    Duration? position,
  }) async {
    try {
      await _ensureNdAuthenticated();
      if (serverTypeString?.toLowerCase() != 'navidrome') {
        return;
      }
      final body = <String, dynamic>{
        // ignore: use_null_aware_elements — currentIndex is checked for null
        if (currentIndex != null) 'current': currentIndex,
        'ids': trackIds,
        if (position != null) 'position': position.inMilliseconds,
      };
      await _ndDio.post('queue', data: body);
      afLog(
        'subsonic',
        'Saved play queue to Navidrome: count=${trackIds.length}',
      );
    } on Exception catch (e, stack) {
      afLog(
        'subsonic',
        'Failed to save play queue to Navidrome',
        error: e,
        stackTrace: stack,
      );
    }
  }

  @override
  Future<({List<AfTrack> tracks, int currentIndex, Duration position})?>
  getPlayQueue() async {
    try {
      await _ensureNdAuthenticated();
      if (serverTypeString?.toLowerCase() != 'navidrome') {
        return null;
      }
      final response = await _ndDio.get('queue');
      final root = response.data as Map<String, dynamic>?;
      final data = root?['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      final current = _asInt(data['current']) ?? 0;
      final posMs = _asInt(data['position']) ?? 0;
      final itemsList = data['items'] as List?;

      final tracks = <AfTrack>[];
      if (itemsList != null) {
        for (final item in itemsList) {
          if (item is Map) {
            tracks.add(_parseNdSong(item.cast<String, dynamic>()));
          }
        }
      }

      return (
        tracks: tracks,
        currentIndex: current,
        position: Duration(milliseconds: posMs),
      );
    } on Exception catch (e, stack) {
      afLog(
        'subsonic',
        'Failed to fetch play queue from Navidrome',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  AfTrack _parseNdSong(Map<String, dynamic> m) {
    final duration = _asInt(m['duration']) ?? 0;
    final starred = m['starred'] == true || m['starredAt'] != null;
    final created = m['createdAt'] as String?;
    final bitRate = _asInt(m['bitRate']);
    final suffix = (m['suffix'] as String?)?.toLowerCase() ?? '';
    final isLossless = suffix == 'flac' || suffix == 'alac' || suffix == 'wav';
    final sampleRate = _asInt(m['sampleRate']);

    // In Navidrome native REST API, coverArt can be constructed using albumId as fallback
    final coverArt = m['albumId']?.toString() ?? m['id']?.toString();

    return AfTrack(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] as String?) ?? 'Unknown',
      artistName: (m['artist'] as String?) ?? '',
      albumName: (m['album'] as String?) ?? '',
      albumId: m['albumId']?.toString(),
      artistId: m['artistId']?.toString(),
      trackNumber: _asInt(m['trackNumber']) ?? _asInt(m['track']),
      duration: Duration(seconds: duration),
      quality: TrackQuality(
        sourceCodec: suffix,
        bitrateKbps: !isLossless ? bitRate : null,
        bitDepth: isLossless ? _asInt(m['bitDepth']) : null,
        sampleRateKhz: isLossless && sampleRate != null
            ? sampleRate ~/ 1000
            : null,
      ),
      imageUrl: coverArtUrl(coverArt),
      isFavorite: starred,
      dateAdded: created != null ? DateTime.tryParse(created) : null,
    );
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  void close() {
    _ndDio.close();
    super.close();
  }
}
