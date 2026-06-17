import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import '../../utils/log.dart';
import '../../utils/url.dart';
import '../backend/music_backend.dart';
import '../network/shared_dio_client.dart';
import 'models/items.dart';
import 'models/library.dart';
import 'models/server.dart';
import 'response_parser.dart';
import 'url_builder.dart';

/// Thin Dio-backed Jellyfin REST client.
///
/// Hand-rolled per design spec §11.1 — community Dart SDKs are stale and
/// the surface we need is small.
///
/// Uses [SharedDioClient] for connection pooling and shared caching.
class JellyfinClient implements MusicBackend {
  JellyfinClient({
    required this.server,
    required this.deviceId,
    required this.clientVersion,
    this.accessToken,
    this.userId,
    SharedDioClient? sharedClient,
    this.username,
    String? password,
  }) : _sharedClient = sharedClient ?? SharedDioClient(),
       _urlBuilder = JellyfinUrlBuilder(
         baseUrl: server.baseUrl,
         deviceId: deviceId,
         clientVersion: clientVersion,
         accessToken: accessToken,
         userId: userId,
       ),
       _passwordBytes = password != null ? utf8.encode(password) : null {
    _dio = _createDioWithOptions(
      server,
      deviceId,
      accessToken,
      userId,
      clientVersion,
      _sharedClient,
    );
    _parser = JellyfinResponseParser(_urlBuilder);
    _configureInterceptors();
  }

  Dio _createDioWithOptions(
    JellyfinServer server,
    String deviceId,
    String? accessToken,
    String? userId,
    String clientVersion,
    SharedDioClient sharedClient,
  ) {
    final baseUrl = server.baseUrl.endsWith('/')
        ? server.baseUrl
        : '${server.baseUrl}/';

    return sharedClient.createWithOptions(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        // Header shape mirrors UnicornsOnLSD/finamp's getAuthHeader()
        // (lib/services/jellyfin_api.dart line 408) which is the most
        // battle-tested Flutter client. Key differences from our old
        // implementation:
        //   • Token field is OMITTED entirely when not authenticated
        //     (vs sending `Token=""`). Some Jellyfin plugins read the
        //     header into a struct that treats empty-string and missing
        //     differently, and the official Jellyfin docs example also
        //     omits the field during initial auth.
        //   • Only `Authorization` is sent — Finamp does not send
        //     `X-Emby-Authorization` and Jellyfin's parser consumes only
        //     one of them. Sending both is redundant and a known cause
        //     of confused middleware in plugin-heavy installs.
        //   • `Content-Type: application/json` is set explicitly here
        //     so it doesn't depend on Dio's auto-content-type logic
        //     (which only fires when there's a body — meaning GETs go
        //     out without Content-Type, and some plugins choke on that).
        headers: {
          'Authorization': JellyfinUrlBuilder.buildAuthHeader(
            deviceId: deviceId,
            token: accessToken,
            userId: userId,
            clientVersion: clientVersion,
          ),
          'Content-Type': 'application/json',
          'User-Agent': JellyfinUrlBuilder.userAgentFor(clientVersion),
          'Accept': 'application/json',
        },
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
  }

  void _configureInterceptors() {
    // 401 token rotation interceptor.
    // Mirrors the Navidrome 401 retry pattern in navidrome_client.dart.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              error.requestOptions.extra['_jf401Retry'] != true &&
              !_isReauthenticating &&
              _passwordBytes != null &&
              username != null) {
            _jellyfinToken = null;
            error.requestOptions.extra['_jf401Retry'] = true;
            try {
              await _reauthenticate();
              final response = await _dio.fetch(error.requestOptions);
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

    // HTTPS redirect guard — prevent scheme downgrade from HTTPS to HTTP
    // which could indicate a MITM attack on shared networks.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.scheme == 'https') {
            options.extra['_originalScheme'] = 'https';
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          // Check if we were redirected from HTTPS to HTTP
          final originalScheme =
              response.requestOptions.extra['_originalScheme'];
          if (originalScheme == 'https' &&
              response.requestOptions.uri.scheme == 'http') {
            afLog(
              'http',
              'HTTPS→HTTP redirect blocked: ${response.requestOptions.uri}',
            );
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                error: 'HTTPS to HTTP redirect detected — possible MITM',
              ),
            );
            return;
          }
          handler.next(response);
        },
      ),
    );

    // Debug-only HTTP trace. In release builds we skip these prints
    // entirely so URLs, headers, and bodies never reach logcat where
    // any app on the device with READ_LOGS could capture them.
    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final redactedHeaders = Map<String, dynamic>.from(options.headers)
              ..updateAll(
                (k, v) => k.toLowerCase().contains('auth') ? '<redacted>' : v,
              );
            afLog(
              'http',
              '→ ${options.method} ${JellyfinUrlBuilder.redactUrl(options.uri)}',
            );
            afLog('http', 'headers: $redactedHeaders');
            // For auth-sensitive endpoints, redact the body too.
            final isAuth = options.uri.path.toLowerCase().contains(
              'authenticate',
            );
            afLog(
              'http',
              'body: '
                  '${isAuth ? '<redacted ${options.data is Map ? (options.data as Map).keys.toList() : options.data.runtimeType}>' : options.data}',
            );
            handler.next(options);
          },
          onResponse: (response, handler) {
            afLog(
              'http',
              '← ${response.statusCode} '
                  '${response.requestOptions.method} ${JellyfinUrlBuilder.redactUrl(response.requestOptions.uri)}',
            );
            handler.next(response);
          },
          onError: (err, handler) {
            afLog(
              'http',
              '✕ ${err.response?.statusCode ?? '?'} '
                  '${err.requestOptions.method} ${JellyfinUrlBuilder.redactUrl(err.requestOptions.uri)}',
            );
            handler.next(err);
          },
        ),
      );
    }
  }

  Future<void> _reauthenticate() async {
    if (username == null || _passwordBytes == null) {
      throw StateError('Cannot re-authenticate: no stored credentials');
    }
    _isReauthenticating = true;
    try {
      final auth = await authenticate(
        username: username!,
        password: utf8.decode(_passwordBytes),
      );
      _jellyfinToken = auth.accessToken;
      _dio.options.headers['Authorization'] =
          JellyfinUrlBuilder.buildAuthHeader(
            deviceId: deviceId,
            token: _jellyfinToken,
            userId: userId,
            clientVersion: clientVersion,
          );
    } finally {
      _isReauthenticating = false;
    }
  }

  final SharedDioClient _sharedClient;
  static final _genreSplitRe = RegExp(r'[,;]');

  final JellyfinServer server;
  final String? accessToken;
  final String? userId;
  final String deviceId;
  final String? username;
  final List<int>? _passwordBytes;
  String? _jellyfinToken;
  bool _isReauthenticating = false;

  /// Aetherfin's running app version (e.g. `0.2.3`). Sent verbatim in the
  /// `MediaBrowser` Authorization `Version="…"` field and in the
  /// `User-Agent` header. Loaded from `package_info_plus` in `main()` and
  /// injected through [aetherfinVersionProvider] — never hardcoded here so
  /// a `pubspec.yaml` bump can't leave stale strings in HTTP traffic.
  final String clientVersion;

  late final Dio _dio;

  @visibleForTesting
  Dio get dio => _dio;

  final JellyfinUrlBuilder _urlBuilder;
  late final JellyfinResponseParser _parser;

  @override
  ServerType get serverType => ServerType.jellyfin;

  @override
  Map<String, String> get authHeaders => _urlBuilder.authHeaders;

  @override
  void clearCache() {
    _sharedClient.clearCache();
  }

  @override
  void close() {
    // Best-effort zeroing of the password buffer (matches SubsonicClient).
    // Dart's GC-managed heap means this is defense-in-depth, not a guarantee
    // — the bytes may already have been copied to an older heap generation.
    if (_passwordBytes != null) {
      for (var i = 0; i < _passwordBytes.length; i++) {
        _passwordBytes[i] = 0;
      }
    }
    // Note: We don't close the shared client here as it's shared across
    // all backend instances. The shared client should be closed by the
    // app lifecycle manager.
    _dio.close(force: true);
  }

  /// `GET /System/Info/Public` — used by mDNS resolution to confirm a
  /// reachable server and pick up its name + version.
  Future<JellyfinServer> publicInfo() async {
    final res = await _dio.get<Map<String, dynamic>>('System/Info/Public');
    final data = res.data ?? const <String, dynamic>{};
    return server.copyWith(
      name: (data['ServerName'] as String?) ?? server.name,
      version: data['Version'] as String?,
      id: data['Id'] as String?,
      isReachable: true,
    );
  }

  /// Authenticate via username + password. Returns the auth blob ready
  /// to be persisted to secure storage.
  Future<JellyfinAuth> authenticate({
    required String username,
    required String password,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      'Users/AuthenticateByName',
      data: {'Username': username, 'Pw': password},
    );
    final data = res.data;
    if (data == null) {
      throw StateError('Authentication failed: empty response body.');
    }
    final rawUser = data['User'];
    if (rawUser is! Map) {
      throw StateError(
        'Authentication failed: invalid or missing User object.',
      );
    }
    final user = rawUser.cast<String, dynamic>();
    final userId = user['Id'];
    if (userId is! String) {
      throw StateError('Authentication failed: missing or invalid User.Id.');
    }
    final accessToken = data['AccessToken'];
    if (accessToken is! String) {
      throw StateError(
        'Authentication failed: missing or invalid AccessToken.',
      );
    }
    return JellyfinAuth(
      server: server,
      userId: userId,
      userName: (user['Name'] as String?) ?? '',
      accessToken: accessToken,
    );
  }

  /// Authenticate via a server-issued API key (created in
  /// `Dashboard → API Keys`). This bypasses `/Users/AuthenticateByName`
  /// — and therefore Jellyfin's session-creation / `LogSessionActivity`
  /// code path entirely — so it works even when plugins or stale device
  /// state cause that endpoint to 500.
  ///
  /// We list users with the API key, find the one whose name matches
  /// [username] (case-insensitive), and return their userId + the key
  /// as the access token. Throws [StateError] if no matching user is
  /// found, with a clear message the UI can surface.
  Future<JellyfinAuth> authenticateWithApiKey({
    required String username,
    required String apiKey,
  }) async {
    // Build a temporary client carrying the API key in the Authorization
    // header. We can't just swap headers on `_dio` because that would
    // mutate state shared with other callers.
    final probe = SharedDioClient().dio;
    try {
      // Build full URL since shared Dio has no baseUrl configured
      final base = _dio.options.baseUrl.endsWith('/')
          ? _dio.options.baseUrl
          : '${_dio.options.baseUrl}/';
      final res = await probe.get<List<dynamic>>(
        '${base}Users',
        options: Options(
          headers: {
            'Authorization': JellyfinUrlBuilder.buildAuthHeader(
              deviceId: deviceId,
              token: apiKey,
              clientVersion: clientVersion,
            ),
            'Content-Type': 'application/json',
            'User-Agent': JellyfinUrlBuilder.userAgentFor(clientVersion),
            'Accept': 'application/json',
          },
        ),
      );
      final users = (res.data ?? const []).whereType<Map<String, dynamic>>();
      final wanted = username.trim().toLowerCase();
      for (final raw in users) {
        final u = raw.cast<String, dynamic>();
        final name = (u['Name'] as String?)?.trim() ?? '';
        if (name.toLowerCase() == wanted) {
          return JellyfinAuth(
            server: server,
            userId: (u['Id'] ?? '').toString(),
            userName: name,
            accessToken: apiKey,
          );
        }
      }
      // Intentionally generic — echoing the attempted username or the
      // full user list would let an attacker who possesses only the API
      // key enumerate accounts on the server.
      throw StateError('Authentication failed. Check your credentials.');
    } finally {
      // NOT closing the shared client — it's a singleton managed by
      // the app lifecycle, not per-request scope.
    }
  }

  @override
  Future<List<LibraryView>> userViews() async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>('Users/$userId/Views');
    final items = (res.data?['Items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    return items
        .map(
          (m) => LibraryView(
            id: m['Id'] as String,
            name: m['Name'] as String,
            collectionType: (m['CollectionType'] as String? ?? 'unknown')
                .toLowerCase(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> uploadUserAvatar(List<int> bytes, String mimeType) async {
    _urlBuilder.assertUser();
    await _dio.post(
      'Users/$userId/Images/Primary',
      data: bytes,
      options: Options(headers: {'Content-Type': mimeType}),
    );
  }

  @override
  Future<void> deleteUserAvatar() async {
    _urlBuilder.assertUser();
    await _dio.delete('Users/$userId/Images/Primary');
  }

  @override
  String trackStreamUrl(
    String trackId, {
    int? maxBitrateKbps,
    String? deviceProfileId,
  }) {
    return _urlBuilder.trackStreamUrl(
      trackId,
      maxBitrateKbps: maxBitrateKbps,
      deviceProfileId: deviceProfileId,
    );
  }

  /// `POST /Sessions/Playing` — tell the server a track just started.
  @override
  Future<void> reportPlaybackStart(String trackId) async {
    _urlBuilder.assertUser();
    await _dio.post(
      'Sessions/Playing',
      data: {
        'ItemId': trackId,
        'PositionTicks': 0,
        'PlayMethod': 'DirectStream',
        'CanSeek': true,
      },
    );
  }

  /// `POST /Sessions/Playing/Progress` — playback progress reporting.
  @override
  Future<void> reportProgress(
    String trackId,
    Duration position, {
    bool isPaused = false,
  }) async {
    _urlBuilder.assertUser();
    await _dio.post(
      'Sessions/Playing/Progress',
      data: {
        'ItemId': trackId,
        'PositionTicks': position.inMicroseconds * 10,
        'IsPaused': isPaused,
        'PlayMethod': 'DirectStream',
      },
    );
  }

  @override
  Future<void> reportPlaybackStop(
    String trackId,
    Duration position, {
    bool submission = true,
  }) async {
    _urlBuilder.assertUser();
    await _dio.post(
      'Sessions/Playing/Stopped',
      data: {'ItemId': trackId, 'PositionTicks': position.inMicroseconds * 10},
    );
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

  @override
  Future<void> setFavorite(String itemId, bool isFavorite) async {
    _urlBuilder.assertUser();
    final path = 'Users/$userId/FavoriteItems/$itemId';
    if (isFavorite) {
      await _dio.post<Map<String, dynamic>>(path);
    } else {
      await _dio.delete<Map<String, dynamic>>(path);
    }
  }

  // ---------------------------------------------------------------------------
  // Library endpoints
  // ---------------------------------------------------------------------------

  @override
  Future<List<AfTrack>> resumeItems({int limit = 20}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items/Resume',
      queryParameters: <String, dynamic>{
        'Limit': limit,
        'MediaTypes': 'Audio',
        'Fields': JellyfinResponseParser.trackFields,
      },
    );
    return _parser
        .parseItemList(res.data)
        .map(_parser.parseTrack)
        .toList(growable: false);
  }

  @override
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<List<dynamic>>(
      'Users/$userId/Items/Latest',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'MusicAlbum',
        'Limit': limit,
        'Fields': JellyfinResponseParser.albumFields,
        'EnableImages': true,
      },
    );
    return _parser
        .parseRawItemList(res.data)
        .map(_parser.parseAlbum)
        .toList(growable: false);
  }

  @override
  Future<List<AfTrack>> recentlyPlayed({int limit = 20}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Filters': 'IsPlayed',
        'Limit': limit,
        'Fields': JellyfinResponseParser.trackFields,
        'EnableImages': true,
      },
    );
    return _parser
        .parseItemList(res.data)
        .map(_parser.parseTrack)
        .toList(growable: false);
  }

  @override
  Future<List<AfArtist>> artists({int limit = 200}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Artists/AlbumArtists',
      queryParameters: <String, dynamic>{
        'UserId': userId,
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'Fields': 'Overview,AlbumCount,SongCount,ChildCount',
        'EnableImages': true,
        'EnableImageTypes': 'Primary',
      },
    );
    final items = _parser.parseItemList(res.data);
    final parser = _parser;
    return Isolate.run(
      () => items.map(parser.parseArtist).toList(growable: false),
    );
  }

  @override
  Future<List<AfPlaylist>> playlists({int limit = 200}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'Playlist',
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'Fields': 'ChildCount,CumulativeRunTimeTicks',
        'EnableImages': true,
      },
    );
    final items = _parser.parseItemList(res.data);
    final parser = _parser;
    return Isolate.run(
      () => items.map(parser.parsePlaylist).toList(growable: false),
    );
  }

  @override
  Future<List<AfGenre>> genres({int limit = 200}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'MusicGenres',
      queryParameters: <String, dynamic>{
        'UserId': userId,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'EnableImages': true,
        'EnableImageTypes': 'Primary',
      },
    );
    final items = _parser.parseItemList(res.data);
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
    final seen = <String>{};
    final result = <AfGenre>[];
    for (final m in items) {
      final raw = (m['Name'] as String?) ?? '';
      if (raw.isEmpty) continue;
      final id = (m['Id'] as String?) ?? '';
      // Build image URL from genre's primary image tag
      final imageTags = m['ImageTags'] as Map<String, dynamic>?;
      final primaryTag = imageTags?['Primary'] as String?;
      String? imageUrl;
      if (id.isNotEmpty && primaryTag != null) {
        final baseUri = Uri.parse(stripTrailingSlash(server.baseUrl));
        imageUrl = baseUri
            .replace(
              path: '${baseUri.path}/Items/$id/Images/Primary',
              queryParameters: {
                'tag': primaryTag,
                'quality': '80',
                'maxWidth': '480',
              },
            )
            .toString();
      }
      for (final part in raw.split(_genreSplitRe)) {
        final token = part.trim();
        if (token.isEmpty) continue;
        final key = token.toLowerCase();
        if (seen.add(key)) {
          result.add(
            AfGenre(
              token,
              palette[result.length % palette.length],
              imageUrl: imageUrl,
            ),
          );
        }
      }
    }
    return result;
  }

  @override
  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'Filters': 'IsFavorite',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'Fields': JellyfinResponseParser.albumFields,
        'EnableImages': true,
      },
    );
    return _parser
        .parseItemList(res.data)
        .map(_parser.parseAlbum)
        .toList(growable: false);
  }

  @override
  Future<List<AfTrack>> favoriteTracks({int limit = 500}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'Filters': 'IsFavorite',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'Fields': JellyfinResponseParser.trackFields,
        'EnableImages': true,
      },
    );
    final items = _parser.parseItemList(res.data);
    final parser = _parser;
    return Isolate.run(
      () => items.map(parser.parseTrack).toList(growable: false),
    );
  }

  @override
  Future<List<AfAlbum>> allAlbums({int limit = 200, int startIndex = 0}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'StartIndex': startIndex,
        'Fields': JellyfinResponseParser.albumFields,
        'EnableImages': true,
      },
    );
    final items = _parser.parseItemList(res.data);
    final parser = _parser;
    return Isolate.run(
      () => items.map(parser.parseAlbum).toList(growable: false),
    );
  }

  @override
  Future<List<AfTrack>> allTracks({
    int limit = 1000,
    int startIndex = 0,
  }) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'StartIndex': startIndex,
        'Fields': JellyfinResponseParser.trackFields,
        'EnableImages': true,
      },
    );
    final items = _parser.parseItemList(res.data);
    final parser = _parser;
    return Isolate.run(
      () => items.map(parser.parseTrack).toList(growable: false),
    );
  }

  @override
  Future<({AfPlaylist playlist, List<AfTrack> tracks})?> playlist(
    String id,
  ) async {
    _urlBuilder.assertUser();
    final responses = await Future.wait<Response<Map<String, dynamic>>>([
      _dio.get<Map<String, dynamic>>(
        'Users/$userId/Items/$id',
        queryParameters: <String, dynamic>{
          'Fields': 'ChildCount,CumulativeRunTimeTicks',
        },
      ),
      _dio.get<Map<String, dynamic>>(
        'Playlists/$id/Items',
        queryParameters: <String, dynamic>{
          'UserId': userId,
          'Fields': JellyfinResponseParser.trackFields,
          'EnableImages': true,
        },
      ),
    ]);
    final header = responses[0].data;
    if (header == null || header.isEmpty) return null;
    final pl = _parser.parsePlaylist(header);
    final tracks = _parser
        .parseItemList(responses[1].data)
        .map(_parser.parseTrack)
        .toList(growable: false);
    return (playlist: pl, tracks: tracks);
  }

  @override
  Future<void> addToPlaylist(String playlistId, List<String> trackIds) async {
    _urlBuilder.assertUser();
    await _dio.post<void>(
      'Playlists/$playlistId/Items',
      queryParameters: <String, dynamic>{
        'Ids': trackIds.join(','),
        'UserId': userId,
      },
    );
  }

  @override
  Future<String?> createPlaylist(String name, List<String> trackIds) async {
    _urlBuilder.assertUser();
    final res = await _dio.post<Map<String, dynamic>>(
      'Playlists',
      data: {
        'Name': name,
        'Ids': trackIds,
        'UserId': userId,
        'MediaType': 'Audio',
      },
    );
    return res.data?['Id'] as String?;
  }

  @override
  Future<void> removeFromPlaylist(
    String playlistId,
    List<String> entryIds,
  ) async {
    _urlBuilder.assertUser();
    await _dio.delete<void>(
      'Playlists/$playlistId/Items',
      queryParameters: <String, dynamic>{'EntryIds': entryIds.join(',')},
    );
  }

  @override
  Future<void> movePlaylistItem(
    String playlistId,
    String itemId,
    int newIndex,
  ) async {
    _urlBuilder.assertUser();
    await _dio.post<void>(
      'Playlists/$playlistId/Items/Move/$itemId',
      queryParameters: <String, dynamic>{'NewIndex': newIndex},
    );
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _urlBuilder.assertUser();
    await _dio.delete<void>('Items/$playlistId');
  }

  @override
  Future<void> renamePlaylist(String playlistId, String newName) async {
    _urlBuilder.assertUser();
    await _dio.post<void>('Items/$playlistId', data: {'Name': newName});
  }

  @override
  Future<List<AfTrack>> instantMix(String seedId, {int limit = 50}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Items/$seedId/InstantMix',
      queryParameters: <String, dynamic>{
        'UserId': userId,
        'Limit': limit,
        'Fields': JellyfinResponseParser.trackFields,
        'EnableImages': true,
      },
    );
    return _parser
        .parseItemList(res.data)
        .map(_parser.parseTrack)
        .toList(growable: false);
  }

  @override
  Future<({AfAlbum album, List<AfTrack> tracks})?> album(String id) async {
    _urlBuilder.assertUser();
    final responses = await Future.wait<Response<Map<String, dynamic>>>([
      _dio.get<Map<String, dynamic>>(
        'Users/$userId/Items/$id',
        queryParameters: <String, dynamic>{
          'Fields': JellyfinResponseParser.albumFields,
        },
      ),
      _dio.get<Map<String, dynamic>>(
        'Users/$userId/Items',
        queryParameters: <String, dynamic>{
          'ParentId': id,
          'IncludeItemTypes': 'Audio',
          'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
          'SortOrder': 'Ascending',
          'Fields': JellyfinResponseParser.trackFields,
        },
      ),
    ]);
    final albumData = responses[0].data;
    if (albumData == null || albumData.isEmpty) return null;
    final album = _parser.parseAlbum(albumData);
    final tracks = _parser
        .parseItemList(responses[1].data)
        .map(_parser.parseTrack)
        .toList(growable: false);
    return (album: album, tracks: tracks);
  }

  @override
  Future<AfArtist?> artist(String id) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items/$id',
      queryParameters: <String, dynamic>{'Fields': 'Overview,ChildCount'},
    );
    final data = res.data;
    if (data == null || data.isEmpty) return null;
    return _parser.parseArtist(data);
  }

  @override
  Future<AfTrackDetails?> trackDetails(String id) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items/$id',
      queryParameters: <String, dynamic>{
        'Fields':
            'MediaSources,Genres,Path,DateCreated,ProductionYear,UserData,PrimaryImageAspectRatio,IndexNumber,ParentIndexNumber,RunTimeTicks,AlbumArtist,AlbumArtists,People',
      },
    );
    final data = res.data;
    if (data == null || data.isEmpty) return null;

    final track = _parser.parseTrack(data);
    final sources = data['MediaSources'] as List?;
    Map<String, dynamic>? src;
    Map<String, dynamic>? audio;
    if (sources != null && sources.isNotEmpty) {
      final rawFirst = sources.firstWhere((s) => s is Map, orElse: () => null);
      if (rawFirst is Map) src = rawFirst.cast<String, dynamic>();
      if (src != null) {
        final streams = (src['MediaStreams'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((s) => s.cast<String, dynamic>())
            .where((s) => (s['Type'] as String?) == 'Audio')
            .toList();
        if (streams.isNotEmpty) audio = streams.first;
      }
    }

    final genres =
        (data['Genres'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const <String>[];
    final userData = (data['UserData'] as Map?)?.cast<String, dynamic>();
    final lastPlayed = userData?['LastPlayedDate'] as String?;
    final albumArtists = data['AlbumArtists'] as List?;
    String? albumArtist;
    if (albumArtists != null && albumArtists.isNotEmpty) {
      final first = albumArtists.firstWhere(
        (a) => a is Map,
        orElse: () => null,
      );
      if (first is Map) {
        final fm = first.cast<String, dynamic>();
        albumArtist = fm['Name'] as String?;
      }
    }
    albumArtist ??= data['AlbumArtist'] as String?;
    final composer = (data['People'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .map((p) => p.cast<String, dynamic>())
        .where((p) => p['Type'] == 'Composer')
        .map((p) => p['Name'] as String?)
        .whereType<String>()
        .join(', ');
    final hasTranscoding = src?['TranscodingUrl'] != null;

    return AfTrackDetails(
      track: track,
      container: (src?['Container'] as String?)?.toLowerCase(),
      sizeBytes: src?['Size'] as int?,
      channels: audio?['Channels'] as int?,
      sampleRateHz: audio?['SampleRate'] as int?,
      bitDepth: audio?['BitDepth'] as int?,
      bitrateBps: (audio?['BitRate'] as int?) ?? (src?['Bitrate'] as int?),
      path: src?['Path'] as String?,
      genres: genres,
      playCount: userData?['PlayCount'] as int?,
      lastPlayedAt: lastPlayed != null ? DateTime.tryParse(lastPlayed) : null,
      year: data['ProductionYear'] as int?,
      discNumber: data['ParentIndexNumber'] as int?,
      albumArtist: albumArtist,
      composer: (composer != null && composer.isNotEmpty) ? composer : null,
      isTranscoded: hasTranscoding,
    );
  }

  @override
  Future<List<AfAlbum>> artistAlbums(String artistId, {int limit = 100}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'AlbumArtistIds': artistId,
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'SortBy': 'PremiereDate,ProductionYear,SortName',
        'SortOrder': 'Descending',
        'Limit': limit,
        'Fields': JellyfinResponseParser.albumFields,
      },
    );
    return _parser
        .parseItemList(res.data)
        .map(_parser.parseAlbum)
        .toList(growable: false);
  }

  @override
  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200}) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'Genres': genre,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'Fields': JellyfinResponseParser.albumFields,
        'EnableImages': true,
      },
    );
    return _parser
        .parseItemList(res.data)
        .map(_parser.parseAlbum)
        .toList(growable: false);
  }

  @override
  Future<List<AfTrack>> artistTopTracks(
    String artistId, {
    int limit = 5,
  }) async {
    _urlBuilder.assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'ArtistIds': artistId,
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'SortBy': 'PlayCount,SortName',
        'SortOrder': 'Descending,Ascending',
        'Limit': limit,
        'Fields': JellyfinResponseParser.trackFields,
        'EnableImages': true,
      },
    );
    return _parser
        .parseItemList(res.data)
        .map(_parser.parseTrack)
        .toList(growable: false);
  }

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
    _urlBuilder.assertUser();
    final q = query.trim();
    if (q.isEmpty) {
      return (
        tracks: const <AfTrack>[],
        albums: const <AfAlbum>[],
        artists: const <AfArtist>[],
        playlists: const <AfPlaylist>[],
      );
    }
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'searchTerm': q,
        'IncludeItemTypes': 'Audio,MusicAlbum,MusicArtist,Playlist',
        'Recursive': true,
        'Limit': 50,
        'Fields': JellyfinResponseParser.trackFields,
        'EnableImages': true,
      },
    );
    final items = _parser.parseItemList(res.data);
    final tracks = <AfTrack>[];
    final albums = <AfAlbum>[];
    final artists = <AfArtist>[];
    final playlists = <AfPlaylist>[];
    for (final m in items) {
      switch (m['Type']) {
        case 'Audio':
          tracks.add(_parser.parseTrack(m));
        case 'MusicAlbum':
          albums.add(_parser.parseAlbum(m));
        case 'MusicArtist':
          artists.add(_parser.parseArtist(m));
        case 'Playlist':
          playlists.add(_parser.parsePlaylist(m));
      }
    }
    return (
      tracks: tracks,
      albums: albums,
      artists: artists,
      playlists: playlists,
    );
  }

  /// `GET /Audio/{trackId}/Lyrics` — returns the LRC text blob if the
  /// server has lyrics for this track, otherwise `null`.
  @override
  Future<String?> lyrics(String trackId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('Audio/$trackId/Lyrics');
      final lyricsList = (res.data?['Lyrics'] as List? ?? const [])
          .whereType<Map<String, dynamic>>();
      if (lyricsList.isEmpty) return null;
      // Reconstruct an LRC blob from the structured lyrics Jellyfin returns.
      // Each entry has `Text` and optionally `Start` (in ticks). For unsynced
      // lyrics the timestamp is null — emit plain lines.
      final buf = StringBuffer();
      for (final raw in lyricsList) {
        final m = raw.cast<String, dynamic>();
        final text = (m['Text'] as String?) ?? '';
        final startTicks = m['Start'];
        if (startTicks is num) {
          final totalMs = startTicks ~/ 10000;
          final mm = (totalMs ~/ 60000).toString().padLeft(2, '0');
          final ss = ((totalMs ~/ 1000) % 60).toString().padLeft(2, '0');
          final cs = ((totalMs % 1000) ~/ 10).toString().padLeft(2, '0');
          buf.writeln('[$mm:$ss.$cs]$text');
        } else {
          buf.writeln(text);
        }
      }
      return buf.toString();
    } on DioException catch (e) {
      // Treat any 4xx as "no lyrics here" — 404 (missing), 401/403 (no
      // permission to read lyrics on this track), 400 (server doesn't
      // support the endpoint at all). The Lyrics screen renders the
      // tasteful "No lyrics yet" placeholder for `null`, which is the
      // right UX regardless of which 4xx the server returned.
      // 5xx still bubbles up so an outage doesn't get silently masked.
      final status = e.response?.statusCode ?? 0;
      if (status >= 400 && status < 500) return null;
      rethrow;
    }
  }
}
