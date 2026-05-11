import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'models/items.dart';
import 'models/library.dart';
import 'models/quality.dart';
import 'models/server.dart';

/// Thin Dio-backed Jellyfin REST client.
///
/// Hand-rolled per design spec §11.1 — community Dart SDKs are stale and
/// the surface we need is small.
class JellyfinClient {
  final JellyfinServer server;
  final String? accessToken;
  final String? userId;
  final String deviceId;
  final Dio _dio;
  final MemCacheStore _cacheStore;

  JellyfinClient({
    required this.server,
    required this.deviceId,
    this.accessToken,
    this.userId,
  })  : _cacheStore = MemCacheStore(maxSize: 20 * 1024 * 1024, maxEntrySize: 1 * 1024 * 1024),
        _dio = Dio(BaseOptions(
          // Trailing slash is REQUIRED so Dio's Uri.resolve preserves the
          // server's base path (e.g. https://example.com/jellyfin/). All
          // paths below are written WITHOUT a leading slash for the same
          // reason.
          baseUrl: server.baseUrl.endsWith('/')
              ? server.baseUrl
              : '${server.baseUrl}/',
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
            'Authorization': _buildAuthHeader(
              deviceId: deviceId,
              token: accessToken,
              userId: userId,
            ),
            'Content-Type': 'application/json',
            'User-Agent': 'Aetherfin/0.1.0 (Android)',
            'Accept': 'application/json',
          },
        )) {
    _dio.interceptors.add(
      DioCacheInterceptor(
        options: CacheOptions(
          store: _cacheStore,
          policy: CachePolicy.request,
          maxStale: const Duration(minutes: 5),
          priority: CachePriority.normal,
        ),
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
              ..updateAll((k, v) =>
                  k.toLowerCase().contains('auth') ? '<redacted>' : v);
            // ignore: avoid_print
            print('aetherfin:http → ${options.method} ${_redactUrl(options.uri)}');
            // ignore: avoid_print
            print('aetherfin:http headers: $redactedHeaders');
            // For auth-sensitive endpoints, redact the body too.
            final isAuth =
                options.uri.path.toLowerCase().contains('authenticate');
            // ignore: avoid_print
            print('aetherfin:http body: '
                '${isAuth ? '<redacted ${options.data is Map ? (options.data as Map).keys.toList() : options.data.runtimeType}>' : options.data}');
            handler.next(options);
          },
          onResponse: (response, handler) {
            // ignore: avoid_print
            print('aetherfin:http ← ${response.statusCode} '
                '${response.requestOptions.method} ${_redactUrl(response.requestOptions.uri)}');
            handler.next(response);
          },
          onError: (err, handler) {
            // ignore: avoid_print
            print('aetherfin:http ✕ ${err.response?.statusCode ?? '?'} '
                '${err.requestOptions.method} ${_redactUrl(err.requestOptions.uri)}');
            handler.next(err);
          },
        ),
      );
    }
  }

  /// Headers callers can use to authenticate ad-hoc requests that bypass
  /// the Dio instance — e.g. the audio source URI given to just_audio, or
  /// a CachedNetworkImage that fetches an artwork-protected endpoint.
  ///
  /// Mirrors what the Dio client sends. Empty map if no token is set.
  Map<String, String> get authHeaders {
    final headers = <String, String>{
      'User-Agent': 'Aetherfin/0.1.0 (Android)',
      'Accept': '*/*',
    };
    if (accessToken != null) {
      headers['Authorization'] = _buildAuthHeader(
        deviceId: deviceId,
        token: accessToken,
        userId: userId,
      );
    }
    return headers;
  }

  /// Strip credentials (api_key, X-Emby-Token) from a URL before it's
  /// emitted to logcat. Defensive — we no longer add api_key to URLs,
  /// but third-party endpoints or future code could.
  static Uri _redactUrl(Uri uri) {
    if (uri.queryParameters.isEmpty) return uri;
    final scrubbed = <String, dynamic>{
      for (final e in uri.queryParametersAll.entries)
        e.key:
            _isSensitiveParam(e.key) ? const ['<redacted>'] : e.value,
    };
    return uri.replace(queryParameters: scrubbed);
  }

  static bool _isSensitiveParam(String key) {
    final k = key.toLowerCase();
    return k == 'api_key' ||
        k == 'apikey' ||
        k == 'x-emby-token' ||
        k == 'token';
  }

  /// Release in-memory cache (used on sign-out so cross-account leakage
  /// is impossible).
  void clearCache() {
    _cacheStore.clean();
  }

  /// Free the underlying Dio resources. Call on sign-out so HTTP/2
  /// connections + the cache buffer don't leak across accounts.
  void close() {
    _cacheStore.close();
    _dio.close(force: true);
  }

  /// Build a Jellyfin Authorization header.
  ///
  /// Field order and conditional-omission semantics match
  /// UnicornsOnLSD/finamp `getAuthHeader()`. Specifically:
  ///   • `UserId` is omitted when null/empty (initial auth has no user yet).
  ///   • `Token` is omitted when null/empty (initial auth has no token yet).
  ///   • Field order is UserId, Token, Client, Device, DeviceId, Version
  ///     so anything that does substring-matching on the start of the
  ///     header sees the same byte sequence as Finamp / Jellyfin web.
  ///   • Non-ASCII bytes are stripped — iOS device names and some Android
  ///     ROMs can contain emoji that break Jellyfin's header parser.
  static String _buildAuthHeader({
    required String deviceId,
    String? token,
    String? userId,
  }) {
    final parts = <String>[];
    // UserId / Token come from Jellyfin (UUIDs / hex strings) and from
    // an API-key paste field. They are ASCII-safe by contract — escape
    // quotes / CR / LF / backslash so they can't smuggle extra header
    // fields, but DON'T strip non-ASCII: if a future Jellyfin build
    // ever issues a non-ASCII token, silently rewriting the bytes to
    // `_` would auth-fail in a way that's painful to debug.
    if (userId != null && userId.isNotEmpty) {
      parts.add('UserId="${_escapeHeaderValue(userId)}"');
    }
    if (token != null && token.isNotEmpty) {
      parts.add('Token="${_escapeHeaderValue(token)}"');
    }
    parts.add('Client="Aetherfin"');
    parts.add('Device="Android"');
    // DeviceId IS allowed to contain user-facing characters (it's
    // currently random base64url but on the fallback path it includes
    // a microsecond timestamp). Strip non-ASCII here only so Jellyfin's
    // strict 7-bit header parser never sees an emoji-bearing device name.
    parts.add('DeviceId="${_asciiClean(_escapeHeaderValue(deviceId))}"');
    parts.add('Version="0.1.0"');
    return 'MediaBrowser ${parts.join(", ")}';
  }

  /// Escape characters that would break Jellyfin's quoted-string parser
  /// in the Authorization header. Specifically `"` and `\\` get escaped,
  /// and `\r` / `\n` are dropped entirely so a malicious value cannot
  /// inject extra header fields.
  static String _escapeHeaderValue(String v) {
    return v
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\r', '')
        .replaceAll('\n', '');
  }

  /// Replace non-ASCII runs with `_`. Used only on the parts of the
  /// header we *can* mangle without breaking auth — never on the
  /// server-issued UserId / Token.
  static String _asciiClean(String v) =>
      v.replaceAll(RegExp(r'[^\x00-\x7F]+'), '_');

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
    final data = res.data!;
    final user = (data['User'] as Map).cast<String, dynamic>();
    return JellyfinAuth(
      server: server,
      userId: user['Id'] as String,
      userName: user['Name'] as String,
      accessToken: data['AccessToken'] as String,
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
    final probe = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Authorization': _buildAuthHeader(
          deviceId: deviceId,
          token: apiKey,
        ),
        'Content-Type': 'application/json',
        'User-Agent': 'Aetherfin/0.1.0 (Android)',
        'Accept': 'application/json',
      },
    ));
    try {
      final res = await probe.get<List<dynamic>>('Users');
      final users = (res.data ?? const []).cast<Map>();
      final wanted = username.trim().toLowerCase();
      for (final raw in users) {
        final u = raw.cast<String, dynamic>();
        final name = (u['Name'] as String?)?.trim() ?? '';
        if (name.toLowerCase() == wanted) {
          return JellyfinAuth(
            server: server,
            userId: u['Id'] as String,
            userName: name,
            accessToken: apiKey,
          );
        }
      }
      throw StateError(
        'No user named "$username" on this server. '
        'Available: ${users.map((u) => u['Name']).join(", ")}',
      );
    } finally {
      probe.close(force: true);
    }
  }

  /// `GET /Users/{userId}/Views` — the list of libraries the user can see.
  Future<List<LibraryView>> userViews() async {
    final res = await _dio.get<Map<String, dynamic>>('Users/$userId/Views');
    final items = (res.data?['Items'] as List? ?? const []).cast<Map>();
    return items
        .map((m) => LibraryView(
              id: m['Id'] as String,
              name: m['Name'] as String,
              collectionType: (m['CollectionType'] as String? ?? 'unknown')
                  .toLowerCase(),
            ))
        .toList(growable: false);
  }

  /// Build a streaming URL for a given track ID.
  ///
  /// Uses `/Audio/{id}/stream?Static=true` — the direct-stream endpoint
  /// which serves the original file byte-for-byte (mp3 / flac / m4a /
  /// ogg / wav / opus). just_audio's ExoPlayer plays these natively.
  ///
  /// We previously tried `/Audio/{id}/universal` (transcoding-aware) with
  /// only `api_key` + `maxStreamingBitrate` hints. Without the full
  /// Finamp-style `Container=…&TranscodingProtocol=hls&AudioCodec=aac`
  /// negotiation, Jellyfin defaults to serving an HLS manifest that
  /// just_audio could not decode — audio appeared "playing" (state=ready,
  /// IsPaused=false) but `position` never advanced past 0 because the
  /// decoder rejected the stream.
  ///
  /// Direct-stream is simpler, more reliable, and the quality chip can
  /// still be computed from the source-file metadata we already have on
  /// [AfTrack]. If users hit a track with an exotic codec ExoPlayer can't
  /// decode, we'll re-introduce transcoding negotiation as a follow-up
  /// with the full param set.
  String trackStreamUrl(
    String trackId, {
    int? maxBitrateKbps,
    String? deviceProfileId,
  }) {
    _assertUser();
    final qp = <String, String>{
      'Static': 'true',
      'UserId': userId!,
      'DeviceId': deviceId,
      if (maxBitrateKbps != null)
        'MaxStreamingBitrate': '${maxBitrateKbps * 1000}',
      if (deviceProfileId != null) 'DeviceProfileId': deviceProfileId,
    };
    final base = server.baseUrl.endsWith('/')
        ? server.baseUrl.substring(0, server.baseUrl.length - 1)
        : server.baseUrl;
    // Build via `Uri` so every value is URL-encoded — historically we hand
    // -joined `$k=$v` pairs which silently mis-encoded tokens / IDs that
    // contained `+`, `=`, `&`, or `/`. The token used to ride in this URL
    // as `api_key=…`; it now travels in the Authorization header (see
    // `authHeaders`) which a logcat-grepping attacker cannot recover.
    return Uri.parse(base)
        .replace(
          path: '${Uri.parse(base).path}/Audio/$trackId/stream',
          queryParameters: qp,
        )
        .toString();
  }

  /// `POST /Sessions/Playing` — tell the server a track just started.
  ///
  /// Without this Jellyfin's "Now Playing" / activity widgets stay blank
  /// even though `/Audio/{id}/universal` is streaming. Mirrors Finamp's
  /// reportPlaybackStart() — ItemId + PositionTicks (always 0 at start) +
  /// PlayMethod=DirectStream so the dashboard doesn't render "Transcoding"
  /// while we're actually direct-playing the cached AAC the server picked.
  Future<void> reportPlaybackStart(String trackId) async {
    _assertUser();
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
  ///
  /// Called on a ~10s cadence while playing, and once on every pause/seek.
  /// Sending more often than 10s is wasted bandwidth — Jellyfin's web
  /// client and Finamp both use that interval.
  Future<void> reportProgress(
    String trackId,
    Duration position, {
    bool isPaused = false,
  }) async {
    _assertUser();
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

  /// `POST /Sessions/Playing/Stopped` — tell the server playback stopped
  /// (queue ended, user stopped, app backgrounded long enough to dispose).
  ///
  /// We send POST .../Stopped rather than DELETE /Sessions/Playing because
  /// that's the path Finamp and the Jellyfin web client use and it works
  /// reliably on plugin-heavy installs where DELETE bodies get stripped.
  Future<void> reportPlaybackStop(String trackId, Duration position) async {
    _assertUser();
    await _dio.post(
      'Sessions/Playing/Stopped',
      data: {
        'ItemId': trackId,
        'PositionTicks': position.inMicroseconds * 10,
      },
    );
  }

  /// Toggle a library item's favorite state.
  ///
  /// `POST /Users/{userId}/FavoriteItems/{itemId}` adds, the matching
  /// DELETE removes. Both endpoints return the updated `UserItemDataDto`
  /// — we don't need the body, the boolean state in the request is the
  /// source of truth and the UI updates optimistically.
  Future<void> setFavorite(String itemId, bool isFavorite) async {
    _assertUser();
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

  /// `GET /Users/{userId}/Items/Resume` — items the user paused mid-listen.
  Future<List<AfTrack>> resumeItems({int limit = 20}) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items/Resume',
      queryParameters: <String, dynamic>{
        'Limit': limit,
        'MediaTypes': 'Audio',
        'Fields': _trackFields,
      },
    );
    return _parseItemList(res.data).map(_parseTrack).toList(growable: false);
  }

  /// `GET /Users/{userId}/Items/Latest?IncludeItemTypes=MusicAlbum` — albums
  /// recently added to the user's library, newest first.
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) async {
    _assertUser();
    final res = await _dio.get<List<dynamic>>(
      'Users/$userId/Items/Latest',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'MusicAlbum',
        'Limit': limit,
        'Fields': _albumFields,
        'EnableImages': true,
      },
    );
    return _parseRawItemList(res.data).map(_parseAlbum).toList(growable: false);
  }

  /// `GET /Users/{userId}/Items` — recently played audio tracks. Uses
  /// `Filters=IsPlayed` so the list is restricted to tracks the user has
  /// actually played at least once.
  Future<List<AfTrack>> recentlyPlayed({int limit = 20}) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Filters': 'IsPlayed',
        'Limit': limit,
        'Fields': _trackFields,
        'EnableImages': true,
      },
    );
    return _parseItemList(res.data).map(_parseTrack).toList(growable: false);
  }

  /// `GET /Artists` — all artists the user has access to.
  Future<List<AfArtist>> artists({int limit = 200}) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Artists',
      queryParameters: <String, dynamic>{
        'UserId': userId,
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'Fields': 'Overview',
        'EnableImages': true,
      },
    );
    return _parseItemList(res.data).map(_parseArtist).toList(growable: false);
  }

  /// `GET /Users/{userId}/Items?IncludeItemTypes=Playlist` — user's playlists.
  Future<List<AfPlaylist>> playlists({int limit = 200}) async {
    _assertUser();
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
    return _parseItemList(res.data).map(_parsePlaylist).toList(growable: false);
  }

  /// `GET /MusicGenres` — distinct music genres in the user's library.
  ///
  /// Jellyfin returns one row per genre as stored on each track. Many
  /// libraries (especially MusicBrainz-tagged ones) store comma-separated
  /// genre strings as a *single* tag value — e.g.
  /// `"Alternative, Indie Pop, Indie Rock"`. Those leak straight into the
  /// grid as giant comma-joined tiles, which is unreadable.
  ///
  /// Here we normalise: split each returned name on `,` / `;` / `/`,
  /// trim, lower-case for dedup, and emit one tile per atomic genre
  /// token preserving the title-cased display form of the first
  /// occurrence. A trailing slash inside a token (e.g. `Indie Rock/Rock
  /// pop`) is kept intact — only commas + semicolons split.
  Future<List<AfGenre>> genres({int limit = 200}) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'MusicGenres',
      queryParameters: <String, dynamic>{
        'UserId': userId,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
      },
    );
    final items = _parseItemList(res.data);
    // Cycle through a small palette so the row reads as colourful without
    // requiring a custom server-side colour assignment.
    const palette = <String>[
      '#5644C9', '#A89DEC', '#3FD18C', '#FF7A59',
      '#F8C42D', '#FF6FB5', '#3DB6FF', '#FF4D6D',
    ];
    final seen = <String>{};
    final result = <AfGenre>[];
    for (final m in items) {
      final raw = (m['Name'] as String?) ?? '';
      if (raw.isEmpty) continue;
      for (final part in raw.split(RegExp(r'[,;]'))) {
        final token = part.trim();
        if (token.isEmpty) continue;
        final key = token.toLowerCase();
        if (seen.add(key)) {
          result.add(AfGenre(token, palette[result.length % palette.length]));
        }
      }
    }
    return result;
  }

  /// `GET /Users/{userId}/Items?IncludeItemTypes=MusicAlbum&Filters=IsFavorite`
  /// — the user's favourite (heart-flagged) albums. Powers the Profile
  /// screen's "Pinned" row — previously the row showed four hard-coded
  /// demo names regardless of the user's actual favourites.
  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'Filters': 'IsFavorite',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'Fields': _albumFields,
        'EnableImages': true,
      },
    );
    return _parseItemList(res.data).map(_parseAlbum).toList(growable: false);
  }

  /// `GET /Users/{userId}/Items?IncludeItemTypes=MusicAlbum` — *every* album
  /// in the user's library, sorted alphabetically. Used by the Library
  /// tab's Albums grid, which has historically conflated
  /// `recentlyAddedAlbums` (top-20-newest) with the full library and
  /// looked permanently underpopulated.
  Future<List<AfAlbum>> allAlbums({
    int limit = 500,
    int startIndex = 0,
  }) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'StartIndex': startIndex,
        'Fields': _albumFields,
        'EnableImages': true,
      },
    );
    return _parseItemList(res.data).map(_parseAlbum).toList(growable: false);
  }

  /// `GET /Users/{userId}/Items?IncludeItemTypes=Audio` — *every* track in
  /// the user's library, sorted alphabetically. Used by the Library tab's
  /// Songs list. The Library used to wire Songs to `recentlyPlayed()`
  /// (filter=IsPlayed, limit=20), so unplayed libraries appeared empty
  /// and played libraries appeared capped at 20 rows.
  Future<List<AfTrack>> allTracks({
    int limit = 1000,
    int startIndex = 0,
  }) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit,
        'StartIndex': startIndex,
        'Fields': _trackFields,
        'EnableImages': true,
      },
    );
    return _parseItemList(res.data).map(_parseTrack).toList(growable: false);
  }

  /// `GET /Playlists/{id}/Items` — the ordered track list for a playlist,
  /// plus the playlist's header metadata. Powers the Playlist detail
  /// screen.
  Future<({AfPlaylist playlist, List<AfTrack> tracks})?> playlist(
      String id) async {
    _assertUser();
    // Fan out the header + tracks fetches in parallel — the second
    // request doesn't depend on the first, so awaiting them serially
    // doubled the time-to-first-byte of the Playlist screen.
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
          'Fields': _trackFields,
          'EnableImages': true,
        },
      ),
    ]);
    final header = responses[0].data;
    if (header == null || header.isEmpty) return null;
    final pl = _parsePlaylist(header);
    final tracks = _parseItemList(responses[1].data)
        .map(_parseTrack)
        .toList(growable: false);
    return (playlist: pl, tracks: tracks);
  }

  /// `GET /Items/{id}/InstantMix` — Jellyfin's server-side similar-songs
  /// generator. Given a seed track / album / artist ID, returns up to
  /// [limit] related tracks. Used to extend the queue with a "radio"
  /// from the currently-playing song (the feature the user requested:
  /// "is it possible to generate queue related song based on the song
  /// played?").
  Future<List<AfTrack>> instantMix(String seedId, {int limit = 50}) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Items/$seedId/InstantMix',
      queryParameters: <String, dynamic>{
        'UserId': userId,
        'Limit': limit,
        'Fields': _trackFields,
        'EnableImages': true,
      },
    );
    return _parseItemList(res.data).map(_parseTrack).toList(growable: false);
  }

  /// `GET /Users/{userId}/Items/{albumId}` + `GET /Items?ParentId=…` — full
  /// album detail plus its ordered track list.
  Future<({AfAlbum album, List<AfTrack> tracks})?> album(String id) async {
    _assertUser();
    // Same idea as [playlist] — the album header and its track list are
    // independent endpoints; running them in parallel halves the
    // perceived load time of the Album screen.
    final responses = await Future.wait<Response<Map<String, dynamic>>>([
      _dio.get<Map<String, dynamic>>(
        'Users/$userId/Items/$id',
        queryParameters: <String, dynamic>{
          'Fields': _albumFields,
        },
      ),
      _dio.get<Map<String, dynamic>>(
        'Users/$userId/Items',
        queryParameters: <String, dynamic>{
          'ParentId': id,
          'IncludeItemTypes': 'Audio',
          'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
          'SortOrder': 'Ascending',
          'Fields': _trackFields,
        },
      ),
    ]);
    final albumData = responses[0].data;
    if (albumData == null || albumData.isEmpty) return null;
    final album = _parseAlbum(albumData);
    final tracks = _parseItemList(responses[1].data)
        .map(_parseTrack)
        .toList(growable: false);
    return (album: album, tracks: tracks);
  }

  /// `GET /Users/{userId}/Items/{artistId}` — full artist detail. Album
  /// + top-track lookups can be layered on top via [artistAlbums] etc.
  Future<AfArtist?> artist(String id) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items/$id',
      queryParameters: <String, dynamic>{
        'Fields': 'Overview,ChildCount',
      },
    );
    final data = res.data;
    if (data == null || data.isEmpty) return null;
    return _parseArtist(data);
  }

  /// `GET /Items?AlbumArtistIds=…` — albums credited to this artist.
  Future<List<AfAlbum>> artistAlbums(String artistId, {int limit = 100}) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'AlbumArtistIds': artistId,
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'SortBy': 'PremiereDate,ProductionYear,SortName',
        'SortOrder': 'Descending',
        'Limit': limit,
        'Fields': _albumFields,
      },
    );
    return _parseItemList(res.data).map(_parseAlbum).toList(growable: false);
  }

  /// `GET /Users/{userId}/Items?ArtistIds=…&SortBy=PlayCount` — the artist's
  /// most-played tracks, used to populate the "Top songs" rail on the
  /// artist screen. Falls back to alphabetical when the server has no play
  /// counts (fresh library / first sign-in).
  Future<List<AfTrack>> artistTopTracks(
    String artistId, {
    int limit = 5,
  }) async {
    _assertUser();
    final res = await _dio.get<Map<String, dynamic>>(
      'Users/$userId/Items',
      queryParameters: <String, dynamic>{
        'ArtistIds': artistId,
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'SortBy': 'PlayCount,SortName',
        'SortOrder': 'Descending,Ascending',
        'Limit': limit,
        'Fields': _trackFields,
        'EnableImages': true,
      },
    );
    return _parseItemList(res.data).map(_parseTrack).toList(growable: false);
  }

  /// `GET /Users/{userId}/Items?searchTerm=…` — full-text search across the
  /// audio item types.
  Future<({List<AfTrack> tracks, List<AfAlbum> albums, List<AfArtist> artists, List<AfPlaylist> playlists})>
      search(String query) async {
    _assertUser();
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
        'Fields': _trackFields,
        'EnableImages': true,
      },
    );
    final items = _parseItemList(res.data);
    final tracks = <AfTrack>[];
    final albums = <AfAlbum>[];
    final artists = <AfArtist>[];
    final playlists = <AfPlaylist>[];
    for (final m in items) {
      switch (m['Type']) {
        case 'Audio':
          tracks.add(_parseTrack(m));
        case 'MusicAlbum':
          albums.add(_parseAlbum(m));
        case 'MusicArtist':
          artists.add(_parseArtist(m));
        case 'Playlist':
          playlists.add(_parsePlaylist(m));
      }
    }
    return (tracks: tracks, albums: albums, artists: artists, playlists: playlists);
  }

  /// `GET /Audio/{trackId}/Lyrics` — returns the LRC text blob if the
  /// server has lyrics for this track, otherwise `null`.
  Future<String?> lyrics(String trackId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'Audio/$trackId/Lyrics',
      );
      final lyricsList = (res.data?['Lyrics'] as List? ?? const []).cast<Map>();
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

  // ---------------------------------------------------------------------------
  // Internal parsing helpers
  // ---------------------------------------------------------------------------

  /// Standard `Fields` projection for track listings — keeps payloads
  /// small while including everything the UI renders.
  static const _trackFields =
      'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,IndexNumber,ParentIndexNumber,ProductionYear,DateCreated,UserData';

  /// Standard `Fields` projection for album listings.
  static const _albumFields =
      'PrimaryImageAspectRatio,RunTimeTicks,ChildCount,ProductionYear,DateCreated,AlbumArtist,AlbumArtists';

  void _assertUser() {
    if (userId == null || userId!.isEmpty) {
      throw StateError(
        'JellyfinClient.userId is null — endpoint requires authentication.',
      );
    }
  }

  /// Extract `Items` list from a paged Jellyfin response.
  List<Map<String, dynamic>> _parseItemList(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final items = data['Items'] as List? ?? const [];
    return _normaliseItems(items);
  }

  /// Same as [_parseItemList] but for endpoints that return a raw
  /// top-level JSON array (e.g. `/Users/{id}/Items/Latest`) instead of
  /// the usual `{Items: [...]}` envelope. Centralises the casting so
  /// every parser goes through the same code path.
  List<Map<String, dynamic>> _parseRawItemList(List<dynamic>? data) =>
      _normaliseItems(data ?? const []);

  List<Map<String, dynamic>> _normaliseItems(Iterable<dynamic> items) =>
      items
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList(growable: false);

  AfAlbum _parseAlbum(Map<String, dynamic> m) {
    final id = m['Id'] as String;
    final ticks = m['RunTimeTicks'];
    final duration = ticks is num
        ? Duration(microseconds: ticks ~/ 10)
        : Duration.zero;
    final dateCreated = m['DateCreated'] as String?;
    return AfAlbum(
      id: id,
      name: (m['Name'] as String?) ?? 'Unknown',
      artistName: _albumArtistName(m),
      artistId: _albumArtistId(m),
      trackCount: (m['ChildCount'] as int?) ?? 0,
      year: m['ProductionYear'] as int?,
      totalDuration: duration,
      imageUrl: _imageUrlFor(m, 'Primary', maxWidth: 480),
      dateAdded: dateCreated != null ? DateTime.tryParse(dateCreated) : null,
    );
  }

  AfArtist _parseArtist(Map<String, dynamic> m) {
    return AfArtist(
      id: m['Id'] as String,
      name: (m['Name'] as String?) ?? 'Unknown',
      albumCount: (m['AlbumCount'] as int?) ?? 0,
      trackCount: (m['SongCount'] as int?) ?? (m['ChildCount'] as int?) ?? 0,
      imageUrl: _imageUrlFor(m, 'Primary', maxWidth: 480),
      bio: m['Overview'] as String?,
    );
  }

  AfTrack _parseTrack(Map<String, dynamic> m) {
    final ticks = m['RunTimeTicks'];
    final duration = ticks is num
        ? Duration(microseconds: ticks ~/ 10)
        : Duration.zero;
    final userData = (m['UserData'] as Map?)?.cast<String, dynamic>();
    final dateCreated = m['DateCreated'] as String?;
    final artistIds = (m['ArtistItems'] as List?)
        ?.whereType<Map>()
        .map((i) => i['Id'])
        .whereType<String>()
        .toList();
    return AfTrack(
      id: m['Id'] as String,
      title: (m['Name'] as String?) ?? 'Unknown',
      artistName: _trackArtistName(m),
      albumName: (m['Album'] as String?) ?? '',
      albumId: m['AlbumId'] as String?,
      artistId: (artistIds != null && artistIds.isNotEmpty) ? artistIds.first : null,
      trackNumber: m['IndexNumber'] as int?,
      duration: duration,
      quality: _parseQuality(m),
      imageUrl: _imageUrlFor(m, 'Primary', maxWidth: 480) ??
          _albumImageUrl(m, maxWidth: 480),
      isFavorite: (userData?['IsFavorite'] as bool?) ?? false,
      dateAdded: dateCreated != null ? DateTime.tryParse(dateCreated) : null,
    );
  }

  AfPlaylist _parsePlaylist(Map<String, dynamic> m) {
    final ticks = m['CumulativeRunTimeTicks'] ?? m['RunTimeTicks'];
    final duration = ticks is num
        ? Duration(microseconds: ticks ~/ 10)
        : Duration.zero;
    return AfPlaylist(
      id: m['Id'] as String,
      name: (m['Name'] as String?) ?? 'Unknown',
      trackCount: (m['ChildCount'] as int?) ?? 0,
      duration: duration,
      imageUrl: _imageUrlFor(m, 'Primary', maxWidth: 480),
      isPublic: (m['IsPublic'] as bool?) ?? false,
    );
  }

  TrackQuality? _parseQuality(Map<String, dynamic> m) {
    final sources = m['MediaSources'] as List?;
    if (sources == null || sources.isEmpty) return null;
    final src = (sources.first as Map).cast<String, dynamic>();
    final streams = (src['MediaStreams'] as List? ?? const [])
        .whereType<Map>()
        .map((s) => s.cast<String, dynamic>())
        .where((s) => (s['Type'] as String?) == 'Audio')
        .toList();
    if (streams.isEmpty) return null;
    final audio = streams.first;
    final codec = ((audio['Codec'] as String?) ?? (src['Container'] as String?) ?? '')
        .toLowerCase();
    final bitrate = audio['BitRate'] as int? ?? src['Bitrate'] as int?;
    final sampleRate = audio['SampleRate'] as int?;
    final bitDepth = audio['BitDepth'] as int?;
    final isLossless = codec == 'flac' || codec == 'alac' || codec == 'wav';
    return TrackQuality(
      sourceCodec: codec,
      bitrateKbps: !isLossless && bitrate != null ? bitrate ~/ 1000 : null,
      bitDepth: isLossless ? bitDepth : null,
      sampleRateKhz: isLossless && sampleRate != null ? sampleRate ~/ 1000 : null,
    );
  }

  String _albumArtistName(Map<String, dynamic> m) {
    final artists = m['AlbumArtists'] as List?;
    if (artists != null && artists.isNotEmpty) {
      final first = (artists.first as Map).cast<String, dynamic>();
      final name = first['Name'] as String?;
      if (name != null && name.isNotEmpty) return name;
    }
    return (m['AlbumArtist'] as String?) ?? (m['Artists'] as List?)?.cast<String>().join(', ') ?? '';
  }

  String? _albumArtistId(Map<String, dynamic> m) {
    final artists = m['AlbumArtists'] as List?;
    if (artists != null && artists.isNotEmpty) {
      final first = (artists.first as Map).cast<String, dynamic>();
      return first['Id'] as String?;
    }
    return null;
  }

  String _trackArtistName(Map<String, dynamic> m) {
    final artists = m['ArtistItems'] as List?;
    if (artists != null && artists.isNotEmpty) {
      final names = artists
          .whereType<Map>()
          .map((a) => a['Name'] as String?)
          .whereType<String>()
          .where((s) => s.isNotEmpty);
      if (names.isNotEmpty) return names.join(', ');
    }
    final flat = (m['Artists'] as List?)?.cast<String>();
    if (flat != null && flat.isNotEmpty) return flat.join(', ');
    return (m['AlbumArtist'] as String?) ?? '';
  }

  /// Build a Primary image URL for an item, using its image tag if available
  /// so the URL is cacheable. Returns null when the item has no image.
  String? _imageUrlFor(Map<String, dynamic> m, String imageType,
      {int maxWidth = 480, int quality = 90}) {
    final tags = m['ImageTags'] as Map?;
    final tag = (tags?[imageType] as String?) ?? '';
    if (tag.isEmpty) return null;
    return _buildImageUrl(m['Id'] as String, imageType,
        tag: tag, maxWidth: maxWidth, quality: quality);
  }

  /// For tracks without their own primary image, fall back to the parent
  /// album's image tag.
  String? _albumImageUrl(Map<String, dynamic> m, {int maxWidth = 480}) {
    final id = m['AlbumId'] as String?;
    final tag = m['AlbumPrimaryImageTag'] as String?;
    if (id == null || tag == null || tag.isEmpty) return null;
    return _buildImageUrl(id, 'Primary', tag: tag, maxWidth: maxWidth);
  }

  String _buildImageUrl(String itemId, String imageType,
      {required String tag, int maxWidth = 480, int quality = 90}) {
    final qp = <String, String>{
      'maxWidth': '$maxWidth',
      'quality': '$quality',
      'tag': tag,
    };
    final base = server.baseUrl.endsWith('/')
        ? server.baseUrl.substring(0, server.baseUrl.length - 1)
        : server.baseUrl;
    return Uri.parse(base)
        .replace(
          path: '${Uri.parse(base).path}/Items/$itemId/Images/$imageType',
          queryParameters: qp,
        )
        .toString();
  }
}
