import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/log.dart';
import 'youtube_auth.dart';

/// InnerTube client for YouTube Music home content.
///
/// Uses WEB_REMIX client identity (YouTube Music web app).
/// Supports both anonymous and authenticated (cookie-based) modes.
class InnerTubeClient {
  InnerTubeClient();

  static const _baseUrl = 'https://music.youtube.com/youtubei/v1';
  static const _clientName = 'WEB_REMIX';
  static const _clientVersion = '1.20260213.01.00';
  static const _clientId = '67';
  static const _origin = 'https://music.youtube.com';
  static const _referer = '$_origin/';

  /// Persistent HTTP client for cookie persistence across requests.
  HttpClient? _httpClient;
  String? _cachedVisitorData;
  Completer<void>? _initCompleter;
  String? _cookies;

  /// Auth bundle for authenticated requests. Null = anonymous mode.
  YouTubeAuthBundle? _auth;

  String get _locale {
    final parts = Platform.localeName.split('_');
    final gl = parts.length >= 2 ? parts.last.toUpperCase() : 'US';
    final hl = parts.length >= 2 ? parts.first : 'en';
    return '$gl|$hl';
  }

  /// Set or clear authentication credentials.
  void setAuth(YouTubeAuthBundle? auth) {
    _auth = auth;
    if (auth != null) {
      afLog(
        'youtube',
        'setAuth: email=${auth.email} '
            'hasSAPISID=${auth.cookies.containsKey('SAPISID')} '
            'cookieCount=${auth.cookies.length} '
            'dataSyncId=${auth.dataSyncId}',
      );
      // Merge auth cookies into the cookie jar
      final authCookieStr = auth.cookieString;
      if (_cookies != null && _cookies!.isNotEmpty) {
        _cookies = '$_cookies; $authCookieStr';
      } else {
        _cookies = authCookieStr;
      }
    }
  }

  /// Lazily initialize: fetch homepage for cookies + visitorData in one session.
  ///
  /// Uses a [Completer] to serialize concurrent callers — only the first
  /// caller runs the init logic; subsequent callers await the same future.
  Future<void> _ensureInitialized() async {
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    _initCompleter = Completer<void>();

    try {
      // 1. Fetch homepage to get session cookies.
      // When authenticated, skip page fetch to avoid merging conflicting cookies.
      if (_auth == null) {
        final pageClient = HttpClient();
        try {
          final req = await pageClient.getUrl(Uri.parse(_origin));
          req.headers.set(
            'User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
                'Gecko/20100101 Firefox/140.0',
          );
          req.headers.set('Accept', 'text/html,application/xhtml+xml');
          final resp = await req.close();
          final respCookies = resp.cookies;
          if (respCookies.isNotEmpty) {
            _cookies = respCookies
                .map((c) => '${c.name}=${c.value}')
                .join('; ');
          }
          await resp.transform(utf8.decoder).join();
        } finally {
          pageClient.close();
        }
      }

      // 2. Fetch visitor data
      _cachedVisitorData = await _fetchVisitorData();

      // 3. Create persistent client
      _httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..idleTimeout = const Duration(seconds: 15);
    } on Exception catch (e) {
      afLog(
        'youtube',
        'InnerTube init failed (falling back to new client)',
        error: e,
      );
      _httpClient = HttpClient();
    } finally {
      _initCompleter?.complete();
    }
  }

  Map<String, dynamic> _buildContext({
    required String gl,
    required String hl,
    String? visitorData,
  }) {
    return <String, dynamic>{
      'client': {
        'clientName': _clientName,
        'clientVersion': _clientVersion,
        'hl': hl,
        'gl': gl,
        'visitorData': ?visitorData,
      },
    };
  }

  /// Apply common + auth headers to an HTTP request.
  void _applyHeaders(
    HttpClientRequest request, {
    required String? visitorData,
  }) {
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('X-Goog-Api-Format-Version', '1');
    request.headers.set('X-YouTube-Client-Name', _clientId);
    request.headers.set('X-YouTube-Client-Version', _clientVersion);
    request.headers.set('X-Origin', _origin);
    request.headers.set('Referer', _referer);
    request.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
          'Gecko/20100101 Firefox/140.0',
    );
    if (visitorData != null) {
      request.headers.set('X-Goog-Visitor-Id', visitorData);
    }
    if (_auth != null && _auth!.isValid) {
      final authHeader = _auth!.authorizationHeader;
      if (authHeader != null) {
        request.headers.set('Authorization', authHeader);
      }
      request.headers.set('X-Goog-AuthUser', '0');
    }
    if (_cookies != null) {
      request.headers.set('Cookie', _cookies!);
    }
  }

  /// Fetches the YouTube Music home page content.
  Future<InnerTubeBrowseResponse?> browseHome({
    String? continuation,
    String? params,
  }) async {
    await _ensureInitialized();

    final parts = _locale.split('|');
    final gl = parts[0];
    final hl = parts[1];

    try {
      final visitorData = _cachedVisitorData;
      final body = <String, dynamic>{
        'context': _buildContext(gl: gl, hl: hl, visitorData: visitorData),
        if (continuation == null) 'browseId': 'FEmusic_home',
        if (continuation == null && params != null) 'params': params,
        'continuation': ?continuation,
      };

      final uri = Uri.parse('$_baseUrl/browse?prettyPrint=false');
      final client = _httpClient ?? HttpClient();

      try {
        final request = await client
            .postUrl(uri)
            .timeout(const Duration(seconds: 10));
        _applyHeaders(request, visitorData: visitorData);

        final bodyStr = jsonEncode(body);
        request.write(bodyStr);

        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );

        // Capture any new cookies from response
        final respCookies = response.cookies;
        if (respCookies.isNotEmpty) {
          final newParts = respCookies
              .map((c) => '${c.name}=${c.value}')
              .join('; ');
          _cookies = _cookies != null ? '$_cookies; $newParts' : newParts;
        }

        // Read response bytes with a timeout to avoid streaming hang.
        final completer = Completer<String>();
        final bytes = <int>[];
        final sub = response.listen(
          bytes.addAll,
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete(utf8.decode(bytes));
            }
          },
          onError: (Object e) {
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          },
        );
        String responseBody;
        try {
          responseBody = await completer.future.timeout(
            const Duration(seconds: 10),
          );
        } on TimeoutException {
          unawaited(sub.cancel());
          return null;
        }

        if (response.statusCode != 200) {
          afLog(
            'aetherfin:error',
            'InnerTube browse failed: ${response.statusCode}',
          );
          return null;
        }

        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        final parsed = InnerTubeBrowseResponse.fromJson(json);
        return parsed;
      } on Exception catch (e) {
        afLog('youtube', 'InnerTube HTTP request failed', error: e);
        return null;
      } on Error catch (e) {
        afLog('youtube', 'InnerTube HTTP request failed', error: e);
        return null;
      }
    } on Exception catch (e, stack) {
      afLog(
        'aetherfin:error',
        'InnerTube browse error',
        error: e,
        stackTrace: stack,
      );
      return null;
    } on Error catch (e) {
      afLog('youtube', 'InnerTube browse error', error: e);
      return null;
    }
  }

  /// Browse the user's saved playlists (FEmusic_liked_playlists).
  Future<List<InnerTubePlaylistInfo>> browsePlaylists() async {
    await _ensureInitialized();

    final parts = _locale.split('|');
    final gl = parts[0];
    final hl = parts[1];

    try {
      final visitorData = _cachedVisitorData;
      final body = <String, dynamic>{
        'context': _buildContext(gl: gl, hl: hl, visitorData: visitorData),
        'browseId': 'FEmusic_liked_playlists',
      };

      final uri = Uri.parse('$_baseUrl/browse?prettyPrint=false');
      final client = _httpClient ?? HttpClient();

      try {
        final request = await client.postUrl(uri);
        _applyHeaders(request, visitorData: visitorData);
        request.write(jsonEncode(body));

        final response = await request.close().timeout(const Duration(seconds: 15));
        final completer = Completer<String>();
        final bytes = <int>[];
        response.listen(
          (chunk) => bytes.addAll(chunk),
          onDone: () => completer.complete(utf8.decode(bytes)),
          onError: (Object e) => completer.completeError(e),
        );
        final responseBody = await completer.future.timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          return [];
        }

        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        return _parsePlaylistList(json);
      } on Exception catch (e) {
        return [];
      }
    } on Exception catch (e, stack) {
      return [];
    }
  }

  /// Parse the user's playlist list from the browse response.
  List<InnerTubePlaylistInfo> _parsePlaylistList(Map<String, dynamic> json) {
    final result = <InnerTubePlaylistInfo>[];
    try {
      Map<String, dynamic>? shelf;
      final contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']
              as List?;
      final tabContent = contents?[0]?['tabRenderer']?['content'];
      final sectionList =
          tabContent?['sectionListRenderer'] as Map<String, dynamic>?;
      final sections = sectionList?['contents'] as List?;

      if (sections != null) {
        for (final section in sections) {
          final sMap = section as Map<String, dynamic>;
          shelf ??= sMap['musicShelfRenderer'] as Map<String, dynamic>?;
          shelf ??= sMap['gridRenderer'] as Map<String, dynamic>?;
        }
      }

      if (shelf == null) return result;

      // gridRenderer uses 'items', musicShelfRenderer uses 'contents'
      final items = (shelf['items'] ?? shelf['contents']) as List?;
      if (items == null) return result;

      for (final item in items) {
        final itemMap = item as Map<String, dynamic>;
        final renderer = itemMap['musicTwoRowItemRenderer']
                as Map<String, dynamic>? ??
            itemMap['musicResponsiveListItemRenderer']
                as Map<String, dynamic>?;
        if (renderer == null) continue;

        final titleObj = renderer['title'] as Map<String, dynamic>?;
        final runs = titleObj?['runs'] as List?;
        final title = runs?.map((r) => (r as Map<String, dynamic>)['text'] as String? ?? '').join() ?? '';
        if (title.isEmpty) continue;

        final nav = renderer['navigationEndpoint'] as Map<String, dynamic>?;
        final browseEndpoint = nav?['browseEndpoint'] as Map<String, dynamic>?;
        final browseId = browseEndpoint?['browseId'] as String? ?? '';

        final subtitleObj = renderer['subtitle'] as Map<String, dynamic>?;
        final subtitleRuns = subtitleObj?['runs'] as List?;
        final countStr = subtitleRuns
                ?.map((r) => (r as Map<String, dynamic>)['text'] as String? ?? '')
                .join() ?? '';
        final count = int.tryParse(countStr.replaceAll(RegExp(r'[^0-9]'), ''));

        final thumbRenderer =
            renderer['thumbnailRenderer'] as Map<String, dynamic>?;
        final musicThumb =
            thumbRenderer?['musicThumbnailRenderer'] as Map<String, dynamic>?;
        final thumbObj = musicThumb?['thumbnail'] as Map<String, dynamic>?;
        final thumbnails = thumbObj?['thumbnails'] as List?;
        final imageUrl =
            thumbnails?.isNotEmpty == true
                ? (thumbnails!.last as Map<String, dynamic>)['url']
                        as String? ??
                    ''
                : '';

        result.add(InnerTubePlaylistInfo(
          id: browseId.replaceFirst('VL', ''),
          browseId: browseId,
          title: title,
          trackCount: count,
          imageUrl: imageUrl,
        ));
      }
    } on Exception catch (e) {
      afLog('youtube', '_parsePlaylistList failed', error: e);
    }
    return result;
  }

  /// Browse an artist page and return header info + songs + carousel items.
  /// Makes ONE HTTP call — like Metrolist's YouTube.artist().
  Future<_ArtistPage?> browseArtistPage(String channelId) async {
    await _ensureInitialized();

    final parts = _locale.split('|');
    final gl = parts[0];
    final hl = parts[1];

    try {
      final visitorData = _cachedVisitorData;
      final body = <String, dynamic>{
        'context': _buildContext(gl: gl, hl: hl, visitorData: visitorData),
        'browseId': channelId,
      };

      final uri = Uri.parse('$_baseUrl/browse?prettyPrint=false');
      final client = _httpClient ?? HttpClient();

      try {
        final request = await client.postUrl(uri).timeout(const Duration(seconds: 10));
        _applyHeaders(request, visitorData: visitorData);
        request.write(jsonEncode(body));

        final response = await request.close().timeout(const Duration(seconds: 15));
        final completer = Completer<String>();
        final bytes = <int>[];
        response.listen(
          (chunk) => bytes.addAll(chunk),
          onDone: () => completer.complete(utf8.decode(bytes)),
          onError: (Object e) => completer.completeError(e),
        );
        final responseBody = await completer.future.timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) return null;

        final json = jsonDecode(responseBody) as Map<String, dynamic>;

        // Parse header — try multiple renderer types
        var header = json['header']?['musicImmersiveHeaderRenderer'] as Map<String, dynamic>?;
        header ??= json['header']?['musicVisualHeaderRenderer'] as Map<String, dynamic>?;
        header ??= json['header']?['musicHeaderRenderer'] as Map<String, dynamic>?;

        final titleObj = header?['title'] as Map<String, dynamic>?;
        final runs = titleObj?['runs'] as List?;
        final name = runs?.map((r) => (r as Map<String, dynamic>)['text'] as String? ?? '').join() ?? '';
        if (name.isEmpty) return null;

        final thumb = header?['thumbnail']?['musicThumbnailRenderer']?['thumbnail'] as Map<String, dynamic>?;
        final thumbnails = thumb?['thumbnails'] as List?;
        final thumbUrl = thumbnails?.isNotEmpty == true
            ? (thumbnails!.last as Map<String, dynamic>)['url'] as String? ?? ''
            : '';

        // Parse sections — songs from musicShelfRenderer,
        // everything else from musicCarouselShelfRenderer.
        final tabs = json['contents']?['singleColumnBrowseResultsRenderer']?['tabs'] as List?;
        final tabContent = tabs?.firstOrNull as Map<String, dynamic>?;
        final sectionList = tabContent?['tabRenderer']?['content']?['sectionListRenderer'] as Map<String, dynamic>?;
        final sections = sectionList?['contents'] as List?;

        final songItems = <InnerTubeItem>[];
        final sectionData = <_ArtistSection>[];

        if (sections != null) {
          for (final section in sections) {
            final sMap = section as Map<String, dynamic>;

            // Parse musicShelfRenderer (songs)
            final shelf = sMap['musicShelfRenderer'] as Map<String, dynamic>?;
            if (shelf != null) {
              final contents = shelf['contents'] as List?;
              if (contents != null) {
                for (final c in contents) {
                  final renderer = (c as Map)['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
                  if (renderer == null) continue;
                  final parsed = InnerTubeItem.fromResponsive(renderer);
                  if (parsed != null) songItems.add(parsed);
                }
              }
              // Extract section title + more endpoint
              String sectionTitle = 'Songs';
              String? moreBrowseId;
              final title = shelf['title'] as Map<String, dynamic>?;
              final titleRuns = title?['runs'] as List?;
              if (titleRuns != null && titleRuns.isNotEmpty) {
                sectionTitle = (titleRuns[0] as Map)['text'] as String? ?? 'Songs';
                // Check for navigation endpoint on title runs
                for (final run in titleRuns) {
                  final nav = (run as Map)['navigationEndpoint'] as Map<String, dynamic>?;
                  moreBrowseId = nav?['browseEndpoint']?['browseId'] as String?;
                  if (moreBrowseId != null) break;
                }
              }
              // Also check bottomEndpoint
              final bottomEp = shelf['bottomEndpoint']?['browseEndpoint']?['browseId'] as String?;
              moreBrowseId ??= bottomEp;
              sectionData.add(_ArtistSection(title: sectionTitle, items: songItems.toList(), isSongSection: true, moreBrowseId: moreBrowseId));
              continue;
            }

            // Parse musicCarouselShelfRenderer
            final carousel = sMap['musicCarouselShelfRenderer'] as Map<String, dynamic>?;
            if (carousel != null) {
              final carouselItems = <InnerTubeItem>[];
              final contents = carousel['contents'] as List?;
              if (contents != null) {
                for (final c in contents) {
                  final twoRow = (c as Map)['musicTwoRowItemRenderer'] as Map<String, dynamic>?;
                  if (twoRow == null) {
                    final listItem = (c as Map)['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
                    if (listItem != null) {
                      final parsed = InnerTubeItem.fromResponsive(listItem);
                      if (parsed != null) carouselItems.add(parsed);
                    }
                    continue;
                  }
                  final parsed = InnerTubeItem.fromTwoRow(twoRow);
                  if (parsed != null) carouselItems.add(parsed);
                }
              }
              // Extract section title + more endpoint
              String sectionTitle = '';
              String? moreBrowseId;
              final header = carousel['header']?['musicCarouselShelfBasicHeaderRenderer'] as Map<String, dynamic>?;
              final headerTitle = header?['title'] as Map<String, dynamic>?;
              final headerRuns = headerTitle?['runs'] as List?;
              if (headerRuns != null && headerRuns.isNotEmpty) {
                sectionTitle = (headerRuns.first as Map)['title']?['runs']?[0]?['text'] as String? ?? '';
                if (sectionTitle.isEmpty) {
                  sectionTitle = (headerRuns.first as Map)['text'] as String? ?? '';
                }
              }
              if (sectionTitle.isEmpty) sectionTitle = 'More';
              // Get the "more" browse ID from moreContentButton
              moreBrowseId = header?['moreContentButton']?['buttonRenderer']?['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
              if (carouselItems.isNotEmpty) {
                sectionData.add(_ArtistSection(title: sectionTitle, items: carouselItems, isSongSection: false, moreBrowseId: moreBrowseId));
              }
            }
          }
        }

        return _ArtistPage(
          name: name,
          thumbUrl: thumbUrl,
          songs: songItems,
          carouselItems: sectionData.expand((s) => s.items).toList(),
          sections: sectionData,
        );
      } on Exception catch (_) {
        return null;
      }
    } on Exception catch (_) {
      return null;
    }
  }

  /// Browse a playlist by its browseId (e.g. "VLPLxxxx") and return track items.
  Future<List<InnerTubeItem>> browsePlaylist(String browseId) async {
    final result = await browsePlaylistWithMetadata(browseId);
    return result?.tracks ?? [];
  }

  Future<_BrowseResult?> browsePlaylistWithMetadata(String browseId) async {
    await _ensureInitialized();

    final parts = _locale.split('|');
    final gl = parts[0];
    final hl = parts[1];

    try {
      final visitorData = _cachedVisitorData;

      final body = <String, dynamic>{
        'context': _buildContext(gl: gl, hl: hl, visitorData: visitorData),
        'browseId': browseId,
      };

      final uri = Uri.parse('$_baseUrl/browse?prettyPrint=false');
      final client = _httpClient ?? HttpClient();

      try {
        final request = await client.postUrl(uri).timeout(const Duration(seconds: 10));
        _applyHeaders(request, visitorData: visitorData);

        request.write(jsonEncode(body));

        final response = await request.close().timeout(const Duration(seconds: 15));
        final completer = Completer<String>();
        final bytes = <int>[];
        response.listen(
          (chunk) => bytes.addAll(chunk),
          onDone: () => completer.complete(utf8.decode(bytes)),
          onError: (Object e) => completer.completeError(e),
        );
        final responseBody = await completer.future.timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          return null;
        }

        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        
        // Extract album metadata from microformat
        String? albumTitle;
        String? albumArtist;
        String? albumArtUrl;
        final mf = json['microformat']?['microformatDataRenderer'] as Map<String, dynamic>?;
        if (mf != null) {
          albumTitle = mf['title'] as String?;
          // Strip " - Album by Artist" suffix
          if (albumTitle != null) {
            final sep = RegExp(r' - (Album|Single|EP) by ');
            final match = sep.firstMatch(albumTitle);
            if (match != null) {
              albumArtist = albumTitle!.substring(match.end);
              albumTitle = albumTitle!.substring(0, match.start);
            }
          }
          // Extract thumbnail from microformat
          final thumb = mf['thumbnail']?['thumbnails'] as List?;
          albumArtUrl = thumb?.isNotEmpty == true
              ? (thumb!.last as Map<String, dynamic>)['url'] as String? ?? ''
              : '';
        }
        
        final tracks = _parsePlaylistItems(json);
        return _BrowseResult(
          tracks: tracks,
          albumTitle: albumTitle,
          albumArtist: albumArtist,
          albumArtUrl: albumArtUrl,
        );
      } finally {
        // Don't close persistent client
      }
    } on Exception catch (e, stack) {
      afLog('youtube', 'browsePlaylist failed', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Parse track items from a playlist browse response.
  List<InnerTubeItem> _parsePlaylistItems(Map<String, dynamic> json) {
    final items = <InnerTubeItem>[];
    try {
      Map<String, dynamic>? shelf;

      // Layout 1: twoColumnBrowseResultsRenderer (playlists)
      final twoCol =
          json['contents']?['twoColumnBrowseResultsRenderer']
              as Map<String, dynamic>?;
      if (twoCol != null) {
        final secList = twoCol['secondaryContents'] as Map<String, dynamic>?;
        final contents = secList?['sectionListRenderer']?['contents'] as List?;
        if (contents != null && contents.isNotEmpty) {
          shelf =
              contents[0]['musicPlaylistShelfRenderer']
                  as Map<String, dynamic>?;
          shelf ??= contents[0]['musicShelfRenderer']
                  as Map<String, dynamic>?;
        }
      }

      // Layout 2: singleColumnBrowseResultsRenderer (artist/album pages)
      if (shelf == null) {
        final tabs =
            json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']
                as List?;
        final tabContent = tabs?[0]?['tabRenderer']?['content'];
        shelf =
            tabContent?['musicPlaylistShelfRenderer'] as Map<String, dynamic>?;
        shelf ??= tabContent?['musicShelfRenderer'] as Map<String, dynamic>?;
      }

      if (shelf == null) {
        final mf = json['microformat'];
        if (mf is Map) {
          final mfr = mf['microformatDataRenderer'] as Map<String, dynamic>?;
          }
        return items;
      }

      if (shelf != null) {
        final shelfContents = shelf['contents'] as List?;
        if (shelfContents != null) {
          for (final item in shelfContents) {
            final map = item as Map<String, dynamic>;
            final renderer =
                map['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
            if (renderer == null) continue;
            final parsed = InnerTubeItem.fromResponsive(renderer);
            if (parsed != null) items.add(parsed);
          }
        }
      }
    } on Exception catch (e) {
      afLog('youtube', 'InnerTube browse parsing failed', error: e);
    }
    return items;
  }

  /// Fetches visitor data from /sw.js_data endpoint.
  /// This is how Metrolist (and the official YT Music app) obtains it.
  /// Response is prefixed with ")]}'" (5 chars), then a JSON array.
  Future<String?> _fetchVisitorData() async {
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('https://music.youtube.com/sw.js_data'),
        );
        request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
              'Gecko/20100101 Firefox/140.0',
        );
        request.headers.set('Accept', '*/*');
        request.headers.set('Referer', _referer);

        final response = await request.close();
        final raw = await response.transform(utf8.decoder).join();

        if (response.statusCode == 200 && raw.length > 5) {
          // Strip the XSSI prefix ")]}'" and parse as JSON array.
          final jsonStr = raw.substring(5);
          final parsed = jsonDecode(jsonStr);
          // Navigate: parsed[0][2] is an array of strings/arrays.
          final outerArray = parsed as List;
          final innerArray = outerArray[0] as List;
          final candidates = innerArray[2] as List;
          // Find a string matching the visitor data pattern (starts with Cgt or Cgs).
          for (final candidate in candidates) {
            if (candidate is String &&
                (candidate.startsWith('Cgt') || candidate.startsWith('Cgs'))) {
              return candidate;
            }
          }
        }
      } finally {
        client.close();
      }
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get visitor data', error: e);
    }
    return null;
  }

  /// Release resources held by this client.
  void dispose() {
    _httpClient?.close();
    _httpClient = null;
  }
}

/// Filter chip from the home page.
class InnerTubeChip {
  const InnerTubeChip({required this.title, this.params});

  final String title;
  final String? params;
}

/// Parsed response from the InnerTube browse endpoint.
class InnerTubeBrowseResponse {
  InnerTubeBrowseResponse({
    required this.sections,
    this.continuation,
    this.chips = const [],
  });

  final List<InnerTubeSection> sections;
  final String? continuation;
  final List<InnerTubeChip> chips;

  // ignore: sort_constructors_first
  factory InnerTubeBrowseResponse.fromJson(Map<String, dynamic> json) {
    final sections = <InnerTubeSection>[];
    final chips = <InnerTubeChip>[];
    String? continuation;

    try {
      // Initial browse response: singleColumnBrowseResultsRenderer
      final contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']
              as List?;
      final tabContent = contents?[0]?['tabRenderer']?['content'];
      final sectionList =
          tabContent?['sectionListRenderer'] as Map<String, dynamic>?;

      // Continuation response: may have contents directly under a different path
      Map<String, dynamic>? sectionListOrActions;

      if (sectionList != null) {
        sectionListOrActions = sectionList;
      } else {
        // Try continuationContents → sectionListContinuation
        final contContents =
            json['continuationContents'] as Map<String, dynamic>?;
        final sectionListCont =
            contContents?['sectionListContinuation'] as Map<String, dynamic>?;
        if (sectionListCont != null) {
          sectionListOrActions = sectionListCont;
          // Extract continuation from continuationItems in contents
          final contItems = sectionListCont['contents'] as List?;
          if (contItems != null) {
            for (final ci in contItems) {
              final ciMap = ci as Map<String, dynamic>;
              if (ciMap.containsKey('continuationItemRenderer')) {
                final contItem =
                    ciMap['continuationItemRenderer'] as Map<String, dynamic>?;
                final contEndpoint =
                    contItem?['continuationEndpoint'] as Map<String, dynamic>?;
                final contCommand =
                    contEndpoint?['continuationCommand']
                        as Map<String, dynamic>?;
                final token = contCommand?['token'] as String?;
                if (token != null && token.isNotEmpty) {
                  continuation = token;
                }
              }
            }
          }
        } else {
          // Continuation responses may put actions at the top level
          final actions = json['onResponseReceivedActions'] as List?;
          if (actions != null && actions.isNotEmpty) {
            for (final action in actions) {
              final actionMap = action as Map<String, dynamic>;
              final appendItems =
                  actionMap['appendContinuationItemsAction']
                      as Map<String, dynamic>?;
              if (appendItems != null) {
                sectionListOrActions = {
                  'contents': appendItems['continuationItems'] ?? [],
                };
                final contItems = appendItems['continuationItems'] as List?;
                if (contItems != null) {
                  for (final ci in contItems) {
                    final ciMap = ci as Map<String, dynamic>;
                    if (ciMap.containsKey('continuationItemRenderer')) {
                      final contItem =
                          ciMap['continuationItemRenderer']
                              as Map<String, dynamic>?;
                      final contEndpoint =
                          contItem?['continuationEndpoint']
                              as Map<String, dynamic>?;
                      final contCommand =
                          contEndpoint?['continuationCommand']
                              as Map<String, dynamic>?;
                      final token = contCommand?['token'] as String?;
                      if (token != null && token.isNotEmpty) {
                        continuation = token;
                      }
                    }
                  }
                }
                break;
              }
            }
          }
        }
      }

      if (sectionListOrActions == null) {
        return InnerTubeBrowseResponse(sections: sections);
      }

      // Parse chips if available (initial responses only).
      final header = sectionListOrActions['header'] as Map<String, dynamic>?;
      final chipCloud = header?['chipCloudRenderer'] as Map<String, dynamic>?;
      final chipList = chipCloud?['chips'] as List?;
      if (chipList != null) {
        for (final chipItem in chipList) {
          final renderer =
              chipItem['chipCloudChipRenderer'] as Map<String, dynamic>?;
          if (renderer == null) continue;
          final textObj = renderer['text'] as Map<String, dynamic>?;
          final runs = textObj?['runs'] as List?;
          final title = runs?[0]?['text'] as String? ?? '';
          if (title.isEmpty) continue;

          final browseEndpoint =
              renderer['navigationEndpoint']?['browseEndpoint']
                  as Map<String, dynamic>?;
          final params = browseEndpoint?['params'] as String?;
          chips.add(InnerTubeChip(title: title, params: params));
        }
      }

      // Parse carousel sections.
      final sectionItems = sectionListOrActions['contents'] as List?;
      if (sectionItems != null) {
        for (final item in sectionItems) {
          final itemMap = item as Map<String, dynamic>;

          // Skip continuationItemRenderer — extract token below.
          if (itemMap.containsKey('continuationItemRenderer')) {
            final contItem =
                itemMap['continuationItemRenderer'] as Map<String, dynamic>?;
            final contEndpoint =
                contItem?['continuationEndpoint'] as Map<String, dynamic>?;
            final contCommand =
                contEndpoint?['continuationCommand'] as Map<String, dynamic>?;
            final token = contCommand?['token'] as String?;
            if (token != null && token.isNotEmpty) {
              continuation = token;
            }
            continue;
          }

          // musicCarouselShelfRenderer — standard carousel
          final carousel =
              itemMap['musicCarouselShelfRenderer'] as Map<String, dynamic>?;
          if (carousel != null) {
            final section = InnerTubeSection.fromCarousel(carousel);
            if (section != null) {
              sections.add(section);
            }
            continue;
          }

          // musicTastebuilderShelfRenderer — mood/genre grid
          final tastebuilder =
              itemMap['musicTastebuilderShelfRenderer']
                  as Map<String, dynamic>?;
          if (tastebuilder != null) {
            // Skip tastebuilder — it's an onboarding prompt ("Tell us which artists you like")
            continue;
          }

          // musicShelfRenderer — flat list of songs (e.g. "Listen Again")
          final shelf = itemMap['musicShelfRenderer'] as Map<String, dynamic>?;
          if (shelf != null) {
            final section = InnerTubeSection.fromShelf(shelf);
            if (section != null) {
              sections.add(section);
            }
            continue;
          }
        }
      }

      // Fallback: old-style continuation in sectionList.continuations
      if (continuation == null && sectionList != null) {
        final conts = sectionList['continuations'] as List?;
        if (conts != null && conts.isNotEmpty) {
          final contData = conts[0] as Map<String, dynamic>?;
          continuation =
              contData?['nextContinuationData']?['continuation'] as String?;
        }
      }
    } on Exception catch (e) {
      afLog('youtube', 'InnerTube browse parse error', error: e);
    }

    return InnerTubeBrowseResponse(
      sections: sections,
      continuation: continuation,
      chips: chips,
    );
  }
}

/// A single section/carousel from the home page.
class InnerTubeSection {
  InnerTubeSection({required this.title, required this.items});

  final String title;
  final List<InnerTubeItem> items;

  static InnerTubeSection? fromCarousel(Map<String, dynamic> carousel) {
    try {
      final header = carousel['header'] as Map<String, dynamic>?;
      var headerRenderer =
          header?['musicCarouselShelfHeaderRenderer'] as Map<String, dynamic>?;
      headerRenderer ??=
          header?['musicCarouselShelfBasicHeaderRenderer']
              as Map<String, dynamic>?;

      final titleObj = headerRenderer?['title'];
      String title = '';
      if (titleObj is Map && titleObj['runs'] is List) {
        title = (titleObj['runs'] as List)
            .map((r) => (r as Map<String, dynamic>)['text'] as String? ?? '')
            .join();
      } else if (titleObj is String) {
        title = titleObj;
      }

      final contents = carousel['contents'] as List?;
      if (contents == null || contents.isEmpty) return null;

      final items = <InnerTubeItem>[];
      for (final content in contents) {
        final contentMap = content as Map<String, dynamic>;

        final twoRow =
            contentMap['musicTwoRowItemRenderer'] as Map<String, dynamic>?;
        if (twoRow != null) {
          final item = InnerTubeItem.fromTwoRow(twoRow);
          if (item != null) items.add(item);
          continue;
        }

        final listItem =
            contentMap['musicResponsiveListItemRenderer']
                as Map<String, dynamic>?;
        if (listItem != null) {
          final item = InnerTubeItem.fromResponsive(listItem);
          if (item != null) items.add(item);
        }
      }

      if (items.isEmpty) return null;
      return InnerTubeSection(title: title, items: items);
    } on Exception catch (e, stack) {
      afLog(
        'youtube',
        'InnerTube fromCarousel parse failed',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Parse a musicTastebuilderShelfRenderer (single mood/genre card).
  ///
  /// Actual structure: { thumbnail, primaryText, secondaryText, actionButton, isVisible, trackingParams }
  /// actionButton → musicButtonRenderer → navigationEndpoint → browseEndpoint
  static InnerTubeSection? fromTastebuilder(Map<String, dynamic> shelf) {
    try {
      // Extract title from primaryText
      String title = '';
      final primaryText = shelf['primaryText'];
      if (primaryText is Map && primaryText['runs'] is List) {
        title = (primaryText['runs'] as List)
            .map((r) => (r as Map<String, dynamic>)['text'] as String? ?? '')
            .join();
      }

      // Extract browse endpoint from actionButton
      final actionBtn = shelf['actionButton'] as Map<String, dynamic>?;
      final musicBtn =
          actionBtn?['musicButtonRenderer'] as Map<String, dynamic>?;
      final navEp = musicBtn?['navigationEndpoint'] as Map<String, dynamic>?;
      final browseEp = navEp?['browseEndpoint'] as Map<String, dynamic>?;
      final browseId = browseEp?['browseId'] as String? ?? '';

      if (browseId.isEmpty || title.isEmpty) return null;

      // Extract thumbnail
      final thumbObj = shelf['thumbnail'] as Map<String, dynamic>?;
      final musicThumb =
          thumbObj?['musicThumbnailRenderer'] as Map<String, dynamic>?;
      final thumbInner = musicThumb?['thumbnail'] as Map<String, dynamic>?;
      final thumbList = thumbInner?['thumbnails'] as List?;
      final thumbnailUrl = thumbList?.isNotEmpty == true
          ? (thumbList!.last as Map<String, dynamic>)['url'] as String? ?? ''
          : '';

      return InnerTubeSection(
        title: 'For You',
        items: [
          InnerTubeItem(
            id: browseId,
            title: title,
            subtitle: '',
            thumbnailUrl: thumbnailUrl,
            type: InnerTubeItemType.playlist,
            browseId: browseId,
          ),
        ],
      );
    } on Exception catch (e, stack) {
      afLog(
        'youtube',
        'InnerTube fromTastebuilder parse failed',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Parse a musicShelfRenderer (flat song list, e.g. "Listen Again").
  static InnerTubeSection? fromShelf(Map<String, dynamic> shelf) {
    try {
      final titleObj = shelf['title'];
      String title = '';
      if (titleObj is Map && titleObj['runs'] is List) {
        title = (titleObj['runs'] as List)
            .map((r) => (r as Map<String, dynamic>)['text'] as String? ?? '')
            .join();
      }

      final contents = shelf['contents'] as List?;
      if (contents == null || contents.isEmpty) return null;

      final items = <InnerTubeItem>[];
      for (final content in contents) {
        final map = content as Map<String, dynamic>;
        final renderer =
            map['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
        if (renderer == null) continue;
        final parsed = InnerTubeItem.fromResponsive(renderer);
        if (parsed != null) items.add(parsed);
      }

      if (items.isEmpty) return null;
      return InnerTubeSection(title: title, items: items);
    } on Exception catch (e, stack) {
      afLog(
        'youtube',
        'InnerTube fromShelf parse failed',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }
}

/// A single item in a section (song, album, playlist, artist).
class InnerTubeItem {
  InnerTubeItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
    required this.type,
    this.videoId,
    this.browseId,
    this.artistId,
  });

  final String id;
  final String title;
  final String subtitle;
  final String thumbnailUrl;
  final InnerTubeItemType type;
  final String? videoId;
  final String? browseId;
  final String? artistId;

  static InnerTubeItem? fromTwoRow(Map<String, dynamic> renderer) {
    try {
      final titleRuns = renderer['title'] as Map<String, dynamic>?;
      final runs = titleRuns?['runs'] as List?;
      final title = runs?[0]?['text'] as String? ?? '';
      if (title.isEmpty) return null;

      final subtitleObj = renderer['subtitle'] as Map<String, dynamic>?;
      final subtitleRuns = subtitleObj?['runs'] as List?;
      final rawSubtitle =
          subtitleRuns
              ?.map((r) => (r as Map<String, dynamic>)['text'] as String? ?? '')
              .join() ??
          '';
      // Strip play counts — "2Pac · 5.2M subscribers" → "2Pac"
      final subtitle = rawSubtitle
          .split(RegExp(r'\s*[·•|]\s*'))
          .first
          .trim();
      // Extract artist browse ID from first subtitle run
      String? artistId;
      if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
        artistId = (subtitleRuns[0] as Map<String, dynamic>)
            ?['navigationEndpoint']
            ?['browseEndpoint']
            ?['browseId'] as String?;
      }

      final thumbnailRenderer =
          renderer['thumbnailRenderer'] as Map<String, dynamic>?;
      final musicThumb =
          thumbnailRenderer?['musicThumbnailRenderer'] as Map<String, dynamic>?;
      final thumbnailObj = musicThumb?['thumbnail'] as Map<String, dynamic>?;
      final thumbnails = thumbnailObj?['thumbnails'] as List?;
      final thumbnailUrl = thumbnails?.isNotEmpty == true
          ? (thumbnails!.last as Map<String, dynamic>)['url'] as String? ?? ''
          : '';

      final nav = renderer['navigationEndpoint'] as Map<String, dynamic>?;
      final watchEndpoint = nav?['watchEndpoint'] as Map<String, dynamic>?;
      final browseEndpoint = nav?['browseEndpoint'] as Map<String, dynamic>?;
      final configs =
          browseEndpoint?['browseEndpointContextSupportedConfigs']
              as Map<String, dynamic>?;
      final musicConfig =
          configs?['browseEndpointContextMusicConfig'] as Map<String, dynamic>?;
      final pageType = musicConfig?['pageType'] as String?;

      final videoId = watchEndpoint?['videoId'] as String?;

      InnerTubeItemType type;
      String id;

      if (watchEndpoint != null && videoId != null) {
        type = InnerTubeItemType.song;
        id = videoId;
      } else if (pageType == 'MUSIC_PAGE_TYPE_ALBUM') {
        type = InnerTubeItemType.album;
        id = browseEndpoint?['browseId'] as String? ?? '';
      } else if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST') {
        type = InnerTubeItemType.playlist;
        id = (browseEndpoint?['browseId'] as String? ?? '').replaceFirst(
          'VL',
          '',
        );
      } else if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
        type = InnerTubeItemType.artist;
        id = browseEndpoint?['browseId'] as String? ?? '';
      } else {
        return null;
      }

      if (id.isEmpty) return null;

      return InnerTubeItem(
        id: id,
        title: title,
        subtitle: subtitle,
        thumbnailUrl: thumbnailUrl,
        type: type,
        videoId: videoId,
        browseId: browseEndpoint?['browseId'] as String?,
        artistId: artistId,
      );
    } on Exception catch (e, stack) {
      afLog(
        'youtube',
        'InnerTube fromTwoRow parse failed',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  static InnerTubeItem? fromResponsive(Map<String, dynamic> renderer) {
    try {
      final flexColumns = renderer['flexColumns'] as List?;
      final firstCol = flexColumns?[0] as Map<String, dynamic>?;
      final firstColRenderer =
          firstCol?['musicResponsiveListItemFlexColumnRenderer']
              as Map<String, dynamic>?;
      final textObj = firstColRenderer?['text'] as Map<String, dynamic>?;
      final runs = textObj?['runs'] as List?;
      final title = runs?[0]?['text'] as String? ?? '';
      if (title.isEmpty) return null;

      final secondCol = flexColumns?[1] as Map<String, dynamic>?;
      final secondColRenderer =
          secondCol?['musicResponsiveListItemFlexColumnRenderer']
              as Map<String, dynamic>?;
      final subTextObj = secondColRenderer?['text'] as Map<String, dynamic>?;
      final subRuns = subTextObj?['runs'] as List?;
      final rawSubtitle =
          subRuns
              ?.map((r) => (r as Map<String, dynamic>)['text'] as String? ?? '')
              .join() ??
          '';
      // Strip play counts — "Artist · 975K plays" → "Artist"
      final subtitle = rawSubtitle
          .split(RegExp(r'\s*[·•|]\s*'))
          .first
          .trim();
      // Extract artist browse ID from first subtitle run
      String? artistId;
      if (subRuns != null && subRuns.isNotEmpty) {
        final firstRun = subRuns[0] as Map<String, dynamic>?;
        artistId = firstRun
            ?['navigationEndpoint']
            ?['browseEndpoint']
            ?['browseId'] as String?;
      }

      final thumbnailObj = renderer['thumbnail'] as Map<String, dynamic>?;
      final musicThumb =
          thumbnailObj?['musicThumbnailRenderer'] as Map<String, dynamic>?;
      final thumbObj = musicThumb?['thumbnail'] as Map<String, dynamic>?;
      final thumbnails = thumbObj?['thumbnails'] as List?;
      final thumbnailUrl = thumbnails?.isNotEmpty == true
          ? (thumbnails!.last as Map<String, dynamic>)['url'] as String? ?? ''
          : '';

      // Try onTap first, then playlistItemData fallback.
      final onTap = renderer['onTap'] as Map<String, dynamic>?;
      final watchEndpoint = onTap?['watchEndpoint'] as Map<String, dynamic>?;
      var videoId = watchEndpoint?['videoId'] as String?;
      if (videoId == null) {
        final playlistItemData =
            renderer['playlistItemData'] as Map<String, dynamic>?;
        videoId = playlistItemData?['videoId'] as String?;
      }
      if (videoId == null) return null;

      return InnerTubeItem(
        id: videoId,
        title: title,
        subtitle: subtitle,
        thumbnailUrl: thumbnailUrl,
        type: InnerTubeItemType.song,
        videoId: videoId,
        artistId: artistId,
      );
    } on Exception catch (e, stack) {
      afLog(
        'youtube',
        'InnerTube fromResponsive parse failed',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }
}

/// Parsed playlist info from the browsePlaylists response.
class InnerTubePlaylistInfo {
  InnerTubePlaylistInfo({
    required this.id,
    required this.browseId,
    required this.title,
    this.trackCount,
    this.imageUrl = '',
  });

  final String id;
  final String browseId;
  final String title;
  final int? trackCount;
  final String imageUrl;
}

class _ArtistSection {
  _ArtistSection({required this.title, required this.items, required this.isSongSection, this.moreBrowseId});
  final String title;
  final List<InnerTubeItem> items;
  final bool isSongSection;
  final String? moreBrowseId;
}

class _ArtistPage {
  _ArtistPage({
    required this.name,
    this.thumbUrl,
    this.songs = const [],
    this.carouselItems = const [],
    this.sections = const [],
  });
  final String name;
  final String? thumbUrl;
  final List<InnerTubeItem> songs;
  final List<InnerTubeItem> carouselItems;
  final List<_ArtistSection> sections;
}

class _BrowseResult {
  _BrowseResult({
    required this.tracks,
    this.albumTitle,
    this.albumArtist,
    this.albumArtUrl,
  });
  final List<InnerTubeItem> tracks;
  final String? albumTitle;
  final String? albumArtist;
  final String? albumArtUrl;
}

enum InnerTubeItemType { song, album, playlist, artist }
