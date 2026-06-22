import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import '../../utils/log.dart';
import '../../utils/url.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/library.dart';
import '../jellyfin/models/quality.dart';
import '../jellyfin/models/server.dart';
import '../network/shared_dio_client.dart';

const _kSubsonicApiVersion = '1.16.1';
const _kClientName = 'Aetherfin';

/// Subsonic/OpenSubsonic REST client for Navidrome (and compatible servers).
///
/// This is the Subsonic counterpart of [JellyfinClient]. It implements
/// [MusicBackend] so the provider layer can treat both backends
/// identically. Auth uses the Subsonic token scheme:
/// `t = md5(password + salt)`, `s = salt`, sent as query params on
/// every request alongside `u`, `v`, `c`, `f=json`.
///
/// Uses [SharedDioClient] for connection pooling and shared caching.
class SubsonicClient implements MusicBackend {
  SubsonicClient({
    required this.server,
    required this.username,
    required String password,
    required this.clientVersion,
    SharedDioClient? sharedClient,
  }) : _passwordBytes = utf8.encode(password),
       _sharedClient = sharedClient ?? SharedDioClient() {
    _dio = _createDioWithOptions(server, clientVersion, _sharedClient);
    _configureInterceptors();
  }

  Dio _createDioWithOptions(
    JellyfinServer server,
    String clientVersion,
    SharedDioClient sharedClient,
  ) {
    return sharedClient.createWithOptions(
      BaseOptions(
        baseUrl: _buildBaseUrl(server.baseUrl),
        connectTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent': 'Aetherfin/$clientVersion (Android)',
          'Accept': 'application/json',
        },
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
  }

  void _configureInterceptors() {
    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final redacted = _redactUri(options.uri);
            afLog('http', '→ ${options.method} $redacted');
            handler.next(options);
          },
          onResponse: (response, handler) {
            final redacted = _redactUri(response.requestOptions.uri);
            afLog('http', '← ${response.statusCode} $redacted');
            handler.next(response);
          },
          onError: (err, handler) {
            final redacted = _redactUri(err.requestOptions.uri);
            afLog('http', '✕ ${err.response?.statusCode ?? '?'} $redacted');
            handler.next(err);
          },
        ),
      );
    }
  }

  final JellyfinServer server;
  final String username;

  /// UTF-8 bytes of the password, zeroed on [close] to minimise the
  /// plaintext-residence window in native heap memory. Converted from the
  /// constructor argument so the original [String] can be GC'd immediately.
  /// Typed as [Uint8List] to clarify this is raw UTF-8 byte data.
  final Uint8List _passwordBytes;

  /// Expose the password bytes to subclasses like NavidromeClient.
  Uint8List get passwordBytes => _passwordBytes;

  /// Aetherfin's running app version (e.g. `0.2.3`). Sent in `User-Agent`.
  /// Loaded from `package_info_plus` in `main()` and injected through
  /// [aetherfinVersionProvider] — never hardcoded here so a `pubspec.yaml`
  /// bump can't leave stale strings in scrobbles or session logs.
  final String clientVersion;

  late final Dio _dio;

  @visibleForTesting
  Dio get dio => _dio;

  final SharedDioClient _sharedClient;
  final Random _rng = Random.secure();

  /// Cached OpenSubsonic extensions/capabilities supported by the server.
  final Set<String> _capabilities = {};
  String? _serverVersion;
  String? _serverType;

  String? get serverVersionString => _serverVersion;
  String? get serverTypeString => _serverType;

  static String _buildBaseUrl(String baseUrl) {
    final b = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return '${b}rest/';
  }

  // ── Auth helpers ──────────────────────────────────────────────────────

  /// Generate Subsonic auth query params for every request.
  /// Feeds password and salt as separate chunks via [startChunkedConversion]
  /// to avoid the intermediate spread list (`[...password, ...salt]`) that
  /// would copy password bytes into a new heap buffer on every API call.
  Map<String, String> _authParams() {
    final salt = _generateSalt();
    final collector = _DigestCollector();
    final hasher = md5.startChunkedConversion(collector);
    hasher.add(_passwordBytes);
    hasher.add(utf8.encode(salt));
    hasher.close();
    final token = collector.digest.toString();
    return {
      'u': username,
      't': token,
      's': salt,
      'v': _kSubsonicApiVersion,
      'c': _kClientName,
      'f': 'json',
    };
  }

  String _generateSalt([int length = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      length,
      (_) => chars[_rng.nextInt(chars.length)],
    ).join();
  }

  /// Redact sensitive Subsonic auth params from a URI before logging.
  /// Strips `u`, `t`, `s`, and `api_key` values so credentials never
  /// appear in logcat output.
  static String _redactUri(Uri uri) {
    if (uri.queryParameters.isEmpty) return uri.path;
    final scrubbed = <String, dynamic>{
      for (final e in uri.queryParametersAll.entries)
        e.key: _isSensitiveSubsonicParam(e.key)
            ? const ['<redacted>']
            : e.value,
    };
    return uri.replace(queryParameters: scrubbed).path;
  }

  static bool _isSensitiveSubsonicParam(String key) {
    final k = key.toLowerCase();
    return k == 'u' || k == 't' || k == 's' || k == 'api_key';
  }

  /// Execute a Subsonic API call and return the inner response data.
  Future<Map<String, dynamic>> _get(
    String endpoint, [
    Map<String, dynamic>? extra,
  ]) async {
    final qp = <String, dynamic>{..._authParams(), ...?extra};
    try {
      Response<Map<String, dynamic>> res;
      // Do not use Form POST for 'ping' or 'getOpenSubsonicExtensions' to avoid dependency issues on first connect
      if (_capabilities.contains('formPost') &&
          endpoint != 'ping' &&
          endpoint != 'getOpenSubsonicExtensions') {
        res = await _dio.post<Map<String, dynamic>>(
          '$endpoint.view',
          data: qp,
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      } else {
        res = await _dio.get<Map<String, dynamic>>(
          '$endpoint.view',
          queryParameters: qp,
        );
      }

      final root = res.data?['subsonic-response'] as Map<String, dynamic>?;
      if (root == null) {
        throw StateError(
          'Subsonic response missing subsonic-response envelope',
        );
      }

      // Extract server details dynamically from response headers or body
      final type = root['type'] as String?;
      final serverVersion = root['serverVersion'] as String?;
      if (type != null && type.isNotEmpty) _serverType = type;
      if (serverVersion != null && serverVersion.isNotEmpty) {
        _serverVersion = serverVersion;
      }

      final status = root['status'] as String?;
      if (status != 'ok') {
        final err = root['error'] as Map<String, dynamic>?;
        final code = err?['code'] as int? ?? 0;
        final msg = err?['message'] as String? ?? 'Unknown Subsonic error';
        throw SubsonicApiError(code, msg);
      }
      return root;
    } on DioException catch (e, stack) {
      final enriched = DioException(
        requestOptions: e.requestOptions,
        response: e.response,
        type: e.type,
        error: e.error,
        message: 'Subsonic API error: ${e.message}',
        stackTrace: e.stackTrace,
      );
      Error.throwWithStackTrace(enriched, stack);
    }
  }

  // ── MusicBackend implementation ───────────────────────────────────────

  @override
  ServerType get serverType => ServerType.subsonic;

  @override
  Map<String, String> get authHeaders => const {};

  @override
  void clearCache() => _sharedClient.clearCache();

  @override
  void close() {
    // Best-effort zeroing of the password buffer. This clears the list
    // wrapper, but Dart's GC may have already copied the underlying
    // Uint8List bytes to an older heap generation where they persist
    // until overwritten by future allocations. True memory zeroing is
    // not guaranteed in a GC-managed heap — this is a defense-in-depth
    // mitigation, not a security guarantee.
    for (var i = 0; i < _passwordBytes.length; i++) {
      _passwordBytes[i] = 0;
    }
    // Note: We don't close the shared client here as it's shared across
    // all backend instances. The shared client should be closed by the
    // app lifecycle manager.
    _dio.close(force: true);
  }

  // ── Server ────────────────────────────────────────────────────────────

  /// `ping.view` — verify the server is reachable and credentials work.
  Future<JellyfinServer> ping() async {
    final root = await _get('ping');

    // Probe OpenSubsonic extensions if supported
    _capabilities.clear();
    try {
      final extRoot = await _get('getOpenSubsonicExtensions');
      final extensions = extRoot['openSubsonicExtensions'] as List?;
      if (extensions != null) {
        for (final ext in extensions) {
          if (ext is Map) {
            final name = ext['name'] as String?;
            if (name != null && name.isNotEmpty) {
              _capabilities.add(name);
            }
          }
        }
      }
      afLog('subsonic', 'OpenSubsonic capabilities detected: $_capabilities');
    } on Exception catch (e, stack) {
      afLog(
        'subsonic',
        'Failed to fetch OpenSubsonic extensions, assuming standard Subsonic: $e',
        error: e,
        stackTrace: stack,
      );
    }

    return server.copyWith(
      isReachable: true,
      version: _serverVersion ?? root['version'] as String?,
    );
  }

  // ── Library browsing ──────────────────────────────────────────────────

  @override
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) async {
    final root = await _get('getAlbumList2', {'type': 'newest', 'size': limit});
    return _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
  }

  @override
  Future<List<AfTrack>> recentlyPlayed({int limit = 20}) async {
    // Subsonic has no direct "recently played tracks" endpoint.
    // Use getAlbumList2 type=recent (recently played albums) and fetch
    // their tracks in parallel, then return up to [limit] tracks.
    final root = await _get('getAlbumList2', {'type': 'recent', 'size': limit});
    final albums = _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
    if (albums.isEmpty) return const [];
    // Fetch tracks from the first few albums in parallel
    final results = await Future.wait(
      albums
          .take(5)
          .map(
            (a) => album(a.id).catchError((Object e, StackTrace stack) {
              afLog(
                'subsonic',
                'recentlyPlayed album fetch failed id=${a.id}',
                error: e,
                stackTrace: stack,
              );
              return null;
            }),
          ),
    );
    final tracks = <AfTrack>[];
    for (final detail in results) {
      if (detail != null) tracks.addAll(detail.tracks);
    }
    return tracks.take(limit).toList(growable: false);
  }

  @override
  Future<List<AfTrack>> resumeItems({int limit = 20}) async {
    // Subsonic has no resume concept.
    return const [];
  }

  @override
  Future<List<AfArtist>> artists({int limit = 200}) async {
    final root = await _get('getArtists');
    final artistsData = root['artists'] as Map<String, dynamic>?;
    final indices =
        (artistsData?['index'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    final result = <AfArtist>[];
    for (final idx in indices) {
      final artistList =
          (idx['artist'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final a in artistList) {
        result.add(_parseArtist(a));
        if (result.length >= limit) return result;
      }
    }
    return result;
  }

  @override
  Future<List<AfPlaylist>> playlists({int limit = 200}) async {
    final root = await _get('getPlaylists');
    final playlistsData = root['playlists'] as Map<String, dynamic>?;
    final list =
        (playlistsData?['playlist'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    return list.take(limit).map(_parsePlaylist).toList(growable: false);
  }

  @override
  Future<int> trackCount() async {
    final root = await _get('search3', {
      'query': '',
      'songCount': 0,
      'songOffset': 0,
      'albumCount': 0,
      'artistCount': 0,
    });
    final results = root['searchResult3'] as Map<String, dynamic>?;
    return (results?['totalMatches'] as int?) ?? 0;
  }

  @override
  Future<List<AfAlbum>> allAlbums({int limit = 200, int startIndex = 0}) async {
    final root = await _get('getAlbumList2', {
      'type': 'alphabeticalByName',
      'size': limit,
      'offset': startIndex,
    });
    return _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
  }

  @override
  Future<List<AfTrack>> allTracks({
    int limit = 1000,
    int startIndex = 0,
  }) async {
    // Subsonic has no "get all songs" endpoint. Use search3 with empty
    // query which Navidrome supports.
    final root = await _get('search3', {
      'query': '',
      'songCount': limit,
      'songOffset': startIndex,
      'albumCount': 0,
      'artistCount': 0,
    });
    final results = root['searchResult3'] as Map<String, dynamic>?;
    final songs =
        (results?['song'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return songs.map(parseTrack).toList(growable: false);
  }

  @override
  Future<List<AfGenre>> genres({int limit = 200}) async {
    final root = await _get('getGenres');
    final genresData = root['genres'] as Map<String, dynamic>?;
    final list = genresData?['genre'] as List?;
    if (list == null || list.isEmpty) return const [];

    const palette = <String>[
      '#5644C9',
      '#A89DEC',
      '#3FD18C',
      '#FF7A59',
      '#F8C42D',
      '#FF6FB5',
      '#3DB6FF',
      '#FF4D6D',
    ];
    // Walk the input once and assign palette colours by output index so
    // the colour sequence matches the Jellyfin backend (which also keys
    // off result.length). Avoids the O(n²) `list.indexOf(g)` lookup and
    // the identity-equality footgun (Map doesn't override ==).
    final result = <AfGenre>[];
    final count = list.length < limit ? list.length : limit;
    for (var i = 0; i < count; i++) {
      final g = list[i];
      if (g is Map) {
        final name = (g['value'] as String?) ?? '';
        if (name.isEmpty) continue;
        result.add(AfGenre(name, palette[result.length % palette.length]));
      } else if (g is String && g.isNotEmpty) {
        result.add(AfGenre(g, palette[result.length % palette.length]));
      }
    }
    return result;
  }

  @override
  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) async {
    final root = await _get('getAlbumList2', {
      'type': 'starred',
      'size': limit,
    });
    return _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
  }

  @override
  Future<List<AfTrack>> favoriteTracks({int limit = 500}) async {
    final root = await _get('getStarred2', {});
    final starred = root['starred2'] as Map<String, dynamic>?;
    if (starred == null) return const [];
    final songs =
        (starred['song'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return songs.take(limit).map(parseTrack).toList(growable: false);
  }

  // ── Detail views ──────────────────────────────────────────────────────

  @override
  Future<({AfAlbum album, List<AfTrack> tracks})?> album(String id) async {
    final root = await _get('getAlbum', {'id': id});
    final albumData = root['album'] as Map<String, dynamic>?;
    if (albumData == null) return null;
    final albumObj = _parseAlbumDetail(albumData);
    final songs =
        (albumData['song'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final tracks = songs.map(parseTrack).toList(growable: false);
    return (album: albumObj, tracks: tracks);
  }

  @override
  Future<AfArtist?> artist(String id) async {
    final root = await _get('getArtist', {'id': id});
    final data = root['artist'] as Map<String, dynamic>?;
    if (data == null) return null;
    return _parseArtistDetail(data);
  }

  /// `GET /rest/getSong.view?id={id}` — full per-track detail for the
  /// "Show details" sheet. Subsonic's `getSong` response contains
  /// `size`, `suffix`, `bitRate`, `duration`, `path`, `genre`,
  /// `playCount`, `channelCount`, `samplingRate`, `bitDepth`.
  @override
  Future<AfTrackDetails?> trackDetails(String id) async {
    try {
      final root = await _get('getSong', {'id': id});
      final data = (root['song'] as Map?)?.cast<String, dynamic>();
      if (data == null) return null;
      final track = parseTrack(data);
      final suffix = (data['suffix'] as String?)?.toLowerCase();
      final bitRate = _asInt(data['bitRate']);
      final samplingRate = _asInt(data['samplingRate']);
      final genre = data['genre'] as String?;
      final lastPlayed = data['played'] as String?;
      return AfTrackDetails(
        track: track,
        container: suffix,
        sizeBytes: _asInt(data['size']),
        channels: _asInt(data['channelCount']),
        sampleRateHz: samplingRate,
        bitDepth: _asInt(data['bitDepth']),
        bitrateBps: bitRate != null ? bitRate * 1000 : null,
        path: data['path'] as String?,
        genres: genre != null ? [genre] : const [],
        playCount: _asInt(data['playCount']),
        lastPlayedAt: lastPlayed != null ? DateTime.tryParse(lastPlayed) : null,
        year: _asInt(data['year']),
        discNumber: _asInt(data['discNumber']),
        albumArtist: data['albumArtist'] as String?,
        composer: data['composer'] as String?,
      );
    } on Exception catch (e, stack) {
      afLog('subsonic', 'getSong failed for $id', error: e, stackTrace: stack);
      return null;
    }
  }

  @override
  Future<List<AfAlbum>> artistAlbums(String artistId, {int limit = 100}) async {
    final root = await _get('getArtist', {'id': artistId});
    final data = root['artist'] as Map<String, dynamic>?;
    if (data == null) return const [];
    final albums =
        (data['album'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return albums.take(limit).map(_parseAlbumDetail).toList(growable: false);
  }

  @override
  Future<List<AfTrack>> artistTopTracks(
    String artistId, {
    int limit = 5,
  }) async {
    // Get artist name first, then use getTopSongs
    final artistObj = await artist(artistId);
    if (artistObj == null) return const [];
    try {
      final root = await _get('getTopSongs', {
        'artist': artistObj.name,
        'count': limit,
      });
      final topSongs = root['topSongs'] as Map<String, dynamic>?;
      final songs =
          (topSongs?['song'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      return songs.map(parseTrack).toList(growable: false);
    } on Exception catch (e, stack) {
      afLog(
        'subsonic',
        'getTopSongs failed, falling back to search',
        error: e,
        stackTrace: stack,
      );
      // getTopSongs may not be supported; fall back to search
      try {
        final root = await _get('search3', {
          'query': artistObj.name,
          'songCount': limit,
          'albumCount': 0,
          'artistCount': 0,
        });
        final results = root['searchResult3'] as Map<String, dynamic>?;
        final songs =
            (results?['song'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        return songs.map(parseTrack).toList(growable: false);
      } on Exception catch (e2, stack2) {
        afLog(
          'subsonic',
          'search3 fallback also failed',
          error: e2,
          stackTrace: stack2,
        );
        return const [];
      }
    }
  }

  @override
  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200}) async {
    final root = await _get('getAlbumList2', {
      'type': 'byGenre',
      'genre': genre,
      'size': limit,
    });
    return _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
  }

  @override
  Future<({AfPlaylist playlist, List<AfTrack> tracks})?> playlist(
    String id,
  ) async {
    final root = await _get('getPlaylist', {'id': id});
    final data = root['playlist'] as Map<String, dynamic>?;
    if (data == null) return null;
    final pl = _parsePlaylist(data);
    final songs =
        (data['entry'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final tracks = songs.map(parseTrack).toList(growable: false);
    return (playlist: pl, tracks: tracks);
  }

  // ── Search ────────────────────────────────────────────────────────────

  @override
  Future<
    ({
      List<AfTrack> tracks,
      List<AfAlbum> albums,
      List<AfArtist> artists,
      List<AfPlaylist> playlists,
    })
  >
  search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return (
        tracks: const <AfTrack>[],
        albums: const <AfAlbum>[],
        artists: const <AfArtist>[],
        playlists: const <AfPlaylist>[],
      );
    }
    final root = await _get('search3', {
      'query': q,
      'songCount': 20,
      'albumCount': 20,
      'artistCount': 20,
      'playlistCount': 20,
    });
    final results = root['searchResult3'] as Map<String, dynamic>?;
    final songs =
        (results?['song'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final albumsList =
        (results?['album'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final artistsList =
        (results?['artist'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final playlistsList =
        (results?['playlist'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    return (
      tracks: songs.map(parseTrack).toList(growable: false),
      albums: albumsList.map(_parseAlbumDetail).toList(growable: false),
      artists: artistsList.map(_parseArtist).toList(growable: false),
      playlists: playlistsList.map(_parsePlaylist).toList(growable: false),
    );
  }

  // ── Favorites ─────────────────────────────────────────────────────────

  @override
  Future<void> setFavorite(String itemId, bool isFavorite) async {
    if (isFavorite) {
      await _get('star', {'id': itemId});
    } else {
      await _get('unstar', {'id': itemId});
    }
  }

  // ── Playlists ─────────────────────────────────────────────────────────

  @override
  Future<void> addToPlaylist(String playlistId, List<String> trackIds) async {
    final params = <String, dynamic>{'playlistId': playlistId};
    // Subsonic takes multiple songIdToAdd params; Dio handles list values
    params['songIdToAdd'] = trackIds;
    await _get('updatePlaylist', params);
  }

  @override
  Future<String?> createPlaylist(String name, List<String> trackIds) async {
    final params = <String, dynamic>{
      'name': name,
      if (trackIds.isNotEmpty) 'songId': trackIds,
    };
    final root = await _get('createPlaylist', params);
    final pl = root['playlist'] as Map<String, dynamic>?;
    return pl?['id']?.toString();
  }

  @override
  Future<void> removeFromPlaylist(
    String playlistId,
    List<String> entryIds,
  ) async {
    // The MusicBackend contract (mirroring JellyfinClient + the only
    // caller, playlist_screen._removeTrack) is `entryIds = list of track
    // IDs to remove`. Subsonic's `updatePlaylist`, however, takes 0-based
    // `songIndexToRemove` *positions*, not IDs — so we need to look up
    // each track ID's current position in the playlist and pass those.
    //
    // The previous implementation called `entryIds.map(int.parse)` which
    // (a) threw on any non-numeric track ID (OpenSubsonic servers may use
    // opaque string IDs) and (b) when track IDs happened to be numeric,
    // silently removed the wrong tracks — interpreting an ID like "42" as
    // "remove the track at position 42 of the playlist."
    //
    // NOTE: This fetch-then-modify pattern has a stale-read race: if the
    // playlist is modified server-side between the fetch (playlist() call)
    // and the modify (updatePlaylist), the computed indices may remove
    // the wrong tracks. For the single-user Navidrome use case this is
    // extremely unlikely. If multi-user access becomes a concern, wrap
    // in a retry loop that re-fetches and re-computes on failure.
    if (entryIds.isEmpty) return;
    final detail = await playlist(playlistId);
    if (detail == null) return;
    final wanted = entryIds.toSet();
    final indices = <int>[];
    for (var i = 0; i < detail.tracks.length; i++) {
      if (wanted.contains(detail.tracks[i].id)) indices.add(i);
    }
    if (indices.isEmpty) return;
    // Sort descending so the call is robust regardless of whether the
    // server reindexes after each removal or applies all removals against
    // the original positions in one shot.
    indices.sort((a, b) => b.compareTo(a));
    final params = <String, dynamic>{
      'playlistId': playlistId,
      'songIndexToRemove': indices,
    };
    await _get('updatePlaylist', params);
  }

  @override
  Future<void> movePlaylistItem(
    String playlistId,
    String itemId,
    int newIndex,
  ) async {
    // Subsonic API has no playlist-reorder endpoint. Throwing lets the UI
    // catch this and show a toast instead of silently discarding the move.
    throw UnsupportedError(
      'Subsonic API does not support playlist item reordering',
    );
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await _get('deletePlaylist', {'id': playlistId});
  }

  @override
  Future<void> renamePlaylist(String playlistId, String newName) async {
    await _get('updatePlaylist', {'playlistId': playlistId, 'name': newName});
  }

  // ── Similar songs ─────────────────────────────────────────────────────

  @override
  Future<List<AfTrack>> instantMix(String seedId, {int limit = 50}) async {
    try {
      final root = await _get('getSimilarSongs2', {
        'id': seedId,
        'count': limit,
      });
      final data = root['similarSongs2'] as Map<String, dynamic>?;
      final songs =
          (data?['song'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      return songs.map(parseTrack).toList(growable: false);
    } on Exception catch (e, stack) {
      afLog('subsonic', 'getSimilarSongs2 failed', error: e, stackTrace: stack);
      // getSimilarSongs2 may not be supported; return empty
      return const [];
    }
  }

  // ── Lyrics ────────────────────────────────────────────────────────────

  @override
  Future<String?> lyrics(String trackId) async {
    try {
      // Try OpenSubsonic getLyricsBySongId first
      final root = await _get('getLyricsBySongId', {'id': trackId});
      final lyricsData = root['lyricsList'] as Map<String, dynamic>?;
      final structured =
          (lyricsData?['structuredLyrics'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      if (structured.isEmpty) return null;
      // Prefer synced lyrics
      final synced = structured.firstWhere(
        (l) => l['synced'] == true,
        orElse: () => structured.first,
      );
      final lines =
          (synced['line'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (lines.isEmpty) return null;
      final buf = StringBuffer();
      for (final line in lines) {
        final text = (line['value'] as String?) ?? '';
        final startMs = _asInt(line['start']);
        if (startMs != null) {
          final mm = (startMs ~/ 60000).toString().padLeft(2, '0');
          final ss = ((startMs ~/ 1000) % 60).toString().padLeft(2, '0');
          final cs = ((startMs % 1000) ~/ 10).toString().padLeft(2, '0');
          buf.writeln('[$mm:$ss.$cs]$text');
        } else {
          buf.writeln(text);
        }
      }
      return buf.toString();
    } on Exception catch (e, stack) {
      afLog(
        'subsonic',
        'getLyricsBySongId failed',
        error: e,
        stackTrace: stack,
      );
      // Fall back to legacy getLyrics (requires artist + title)
      return null;
    }
  }

  // ── Streaming ─────────────────────────────────────────────────────────

  @override
  String trackStreamUrl(String trackId, {int? maxBitrateKbps}) {
    final params = <String, String>{..._authParams(), 'id': trackId};
    if (maxBitrateKbps != null) {
      // Request transcoding at the specified max bitrate.
      // 'format=mp3' tells Navidrome to transcode; without it the
      // server may serve the original file regardless of maxBitRate.
      params['maxBitRate'] = '$maxBitrateKbps';
      params['format'] = 'mp3';
    } else {
      // 'raw' tells Navidrome to serve the original file without
      // transcoding. Without this, Navidrome may transcode on-the-fly
      // which adds latency and CPU load on the server.
      params['format'] = 'raw';
    }
    final baseUri = Uri.parse(stripTrailingSlash(server.baseUrl));
    return baseUri
        .replace(
          path: '${baseUri.path}/rest/stream.view',
          queryParameters: params,
        )
        .toString();
  }

  /// Build a cover art URL with embedded auth.
  String? coverArtUrl(String? coverArtId, {int size = 480}) {
    if (coverArtId == null || coverArtId.isEmpty) return null;
    final params = <String, String>{
      ..._authParams(),
      'id': coverArtId,
      'size': '$size',
    };
    final baseUri = Uri.parse(stripTrailingSlash(server.baseUrl));
    return baseUri
        .replace(
          path: '${baseUri.path}/rest/getCoverArt.view',
          queryParameters: params,
        )
        .toString();
  }

  // ── Playback reporting ────────────────────────────────────────────────

  @override
  Future<void> reportPlaybackStart(String trackId) async {
    try {
      await _get('scrobble', {'id': trackId, 'submission': false});
    } on Exception catch (e, stack) {
      afLog(
        'subsonic',
        'reportPlaybackStart scrobble failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  @override
  Future<void> reportProgress(
    String trackId,
    Duration position, {
    bool isPaused = false,
  }) async {
    if (isPaused) return;
    try {
      await _get('scrobble', {
        'id': trackId,
        'submission': false,
        'time': '${position.inMilliseconds}',
      });
    } on Exception catch (e, stack) {
      afLog(
        'subsonic',
        'reportProgress scrobble failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  @override
  Future<void> reportPlaybackStop(
    String trackId,
    Duration position, {
    bool submission = true,
  }) async {
    try {
      await _get('scrobble', {
        'id': trackId,
        'submission': submission,
        'time': '${position.inMilliseconds}',
      });
    } on Exception catch (e, stack) {
      afLog(
        'subsonic',
        'reportPlaybackStop scrobble failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // ── Play queue sync ─────────────────────────────────────────────────

  @override
  Future<void> savePlayQueue(
    List<String> trackIds, {
    int? currentIndex,
    Duration? position,
  }) async {}

  @override
  Future<({List<AfTrack> tracks, int currentIndex, Duration position})?>
  getPlayQueue() async => null;

  // ── User views ────────────────────────────────────────────────────────

  @override
  Future<List<LibraryView>> userViews() async {
    // Subsonic doesn't have the concept of user views like Jellyfin.
    // Return a single "Music" view as a reasonable default.
    return const [
      LibraryView(id: 'music', name: 'Music', collectionType: 'music'),
    ];
  }

  @override
  Future<void> uploadUserAvatar(List<int> bytes, String mimeType) async {}

  @override
  Future<void> deleteUserAvatar() async {}

  // ── Parsing helpers ───────────────────────────────────────────────────

  List<AfAlbum> _parseAlbumList(Map<String, dynamic>? data) {
    final albums =
        (data?['album'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return albums.map(_parseAlbumDetail).toList(growable: false);
  }

  AfAlbum _parseAlbumDetail(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    final duration = _asInt(m['duration']) ?? 0;
    final created = m['created'] as String?;
    final starred = m['starred'] as String?;
    return AfAlbum(
      id: id,
      name:
          (m['name'] as String?) ??
          (m['album'] as String?) ??
          (m['title'] as String?) ??
          'Unknown',
      artistName: (m['artist'] as String?) ?? '',
      artistId: m['artistId']?.toString(),
      trackCount: _asInt(m['songCount']) ?? 0,
      year: _asInt(m['year']),
      totalDuration: Duration(seconds: duration),
      imageUrl: coverArtUrl(m['coverArt']?.toString()),
      dateAdded: created != null ? DateTime.tryParse(created) : null,
      isFavorite: starred != null,
    );
  }

  AfArtist _parseArtist(Map<String, dynamic> m) {
    return AfArtist(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] as String?) ?? 'Unknown',
      albumCount: _asInt(m['albumCount']) ?? 0,
      imageUrl: coverArtUrl(
        m['coverArt']?.toString() ?? m['artistImageUrl']?.toString(),
      ),
    );
  }

  AfArtist _parseArtistDetail(Map<String, dynamic> m) {
    final albums =
        (m['album'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return AfArtist(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] as String?) ?? 'Unknown',
      albumCount: albums.length,
      imageUrl: coverArtUrl(
        m['coverArt']?.toString() ?? m['artistImageUrl']?.toString(),
      ),
    );
  }

  AfTrack parseTrack(Map<String, dynamic> m) {
    final duration = _asInt(m['duration']) ?? 0;
    final starred = m['starred'] as String?;
    final created = m['created'] as String?;
    final bitRate = _asInt(m['bitRate']);
    final suffix = (m['suffix'] as String?)?.toLowerCase() ?? '';
    final isLossless = suffix == 'flac' || suffix == 'alac' || suffix == 'wav';
    final samplingRate = _asInt(m['samplingRate']);
    return AfTrack(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] as String?) ?? 'Unknown',
      artistName: (m['artist'] as String?) ?? '',
      albumName: (m['album'] as String?) ?? '',
      albumId: m['albumId']?.toString(),
      artistId: m['artistId']?.toString(),
      trackNumber: _asInt(m['track']),
      duration: Duration(seconds: duration),
      quality: TrackQuality(
        sourceCodec: suffix,
        bitrateKbps: !isLossless ? bitRate : null,
        bitDepth: isLossless ? _asInt(m['bitDepth']) : null,
        sampleRateKhz: isLossless && samplingRate != null
            ? samplingRate ~/ 1000
            : null,
      ),
      imageUrl: coverArtUrl(m['coverArt']?.toString()),
      isFavorite: starred != null,
      dateAdded: created != null ? DateTime.tryParse(created) : null,
    );
  }

  AfPlaylist _parsePlaylist(Map<String, dynamic> m) {
    final duration = _asInt(m['duration']) ?? 0;
    return AfPlaylist(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] as String?) ?? 'Unknown',
      trackCount: _asInt(m['songCount']) ?? 0,
      duration: Duration(seconds: duration),
      imageUrl: coverArtUrl(m['coverArt']?.toString()),
      isPublic: (m['public'] as bool?) ?? false,
    );
  }

  /// Coerce a JSON numeric to int regardless of whether the upstream
  /// emitted it as int or double. Subsonic-compatible servers vary in
  /// their JSON encoders — Navidrome consistently emits ints, but some
  /// OpenSubsonic implementations encode integer-valued doubles like
  /// `123.0` for durations / bitrates. A blunt \`as int?\` cast then
  /// throws TypeError and tears the parse down. Also accepts numeric
  /// strings like \`"123"\` defensively.
  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// Collects a single [Digest] from a chunked hash operation.
/// Replaces [DigestSink] (not publicly exported from `package:crypto`).
class _DigestCollector implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

/// Error returned by the Subsonic API (status != "ok").
class SubsonicApiError implements Exception {
  const SubsonicApiError(this.code, this.message);
  final int code;
  final String message;

  @override
  String toString() => 'SubsonicApiError($code): $message';
}
