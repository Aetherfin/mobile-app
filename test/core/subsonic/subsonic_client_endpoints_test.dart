import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:aetherfin/core/subsonic/client.dart';
import 'package:aetherfin/core/jellyfin/models/server.dart';

SubsonicClient _client({
  String baseUrl = 'http://srv:4533',
  String username = 'testuser',
  String password = 'testpass',
  String clientVersion = '9.9.9-test',
}) {
  return SubsonicClient(
    server: JellyfinServer(baseUrl: baseUrl, name: 'srv'),
    username: username,
    password: password,
    clientVersion: clientVersion,
  );
}

Map<String, dynamic> _okResponse(Map<String, dynamic> body) => {
  'subsonic-response': {
    'status': 'ok',
    'version': '1.16.1',
    'type': 'navidrome',
    'serverVersion': '0.51.0',
    ...body,
  },
};

Map<String, dynamic> _errorResponse(int code, String message) => {
  'subsonic-response': {
    'status': 'failed',
    'version': '1.16.1',
    'error': {'code': code, 'message': message},
  },
};

Map<String, dynamic> _trackMap({
  String id = 't-1',
  String title = 'Test Track',
  String artist = 'Test Artist',
  String album = 'Test Album',
  String albumId = 'a-1',
  String artistId = 'ar-1',
  int track = 1,
  int duration = 200,
  String? suffix,
  int? bitRate,
  String? coverArt,
  String? starred,
  int? samplingRate,
  int? bitDepth,
  String? created,
}) => {
  'id': id,
  'title': title,
  'artist': artist,
  'album': album,
  'albumId': albumId,
  'artistId': artistId,
  'track': track,
  'duration': duration,
  'suffix': ?suffix,
  'bitRate': ?bitRate,
  'coverArt': ?coverArt,
  'starred': ?starred,
  'samplingRate': ?samplingRate,
  'bitDepth': ?bitDepth,
  'created': ?created,
};

Map<String, dynamic> _albumMap({
  String id = 'a-1',
  String name = 'Test Album',
  String artist = 'Test Artist',
  String artistId = 'ar-1',
  int songCount = 10,
  int duration = 2000,
  int? year,
  String? coverArt,
  String? starred,
  String? created,
}) => {
  'id': id,
  'name': name,
  'artist': artist,
  'artistId': artistId,
  'songCount': songCount,
  'duration': duration,
  'year': ?year,
  'coverArt': ?coverArt,
  'starred': ?starred,
  'created': ?created,
};

Map<String, dynamic> _artistMap({
  String id = 'ar-1',
  String name = 'Test Artist',
  int albumCount = 3,
  String? coverArt,
}) => {'id': id, 'name': name, 'albumCount': albumCount, 'coverArt': ?coverArt};

Map<String, dynamic> _playlistMap({
  String id = 'pl-1',
  String name = 'Test Playlist',
  int songCount = 15,
  int duration = 3600,
  bool isPublic = false,
  String? coverArt,
}) => {
  'id': id,
  'name': name,
  'songCount': songCount,
  'duration': duration,
  'public': isPublic,
  'coverArt': ?coverArt,
};

void main() {
  late SubsonicClient client;
  late List<RequestOptions> capturedRequests;

  setUp(() {
    capturedRequests = [];
    client = _client();
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequests.add(options);
          final path = options.path;
          if (path.contains('ping')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({}),
              ),
            );
          } else if (path.contains('getOpenSubsonicExtensions')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'openSubsonicExtensions': [
                    {'name': 'formPost'},
                  ],
                }),
              ),
            );
          } else {
            handler.next(options);
          }
        },
      ),
    );
  });

  group('Library browsing', () {
    test('recentlyAddedAlbums parses albumList2 response', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'albumList2': {
                    'album': [
                      _albumMap(
                        id: 'a-1',
                        name: 'Album One',
                        year: 2025,
                        songCount: 12,
                      ),
                      _albumMap(
                        id: 'a-2',
                        name: 'Album Two',
                        year: 2024,
                        songCount: 8,
                      ),
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final albums = await client.recentlyAddedAlbums(limit: 5);

      expect(albums, hasLength(2));
      expect(albums[0].id, 'a-1');
      expect(albums[0].name, 'Album One');
      expect(albums[0].artistName, 'Test Artist');
      expect(albums[0].trackCount, 12);
      expect(albums[0].year, 2025);
      expect(albums[1].id, 'a-2');
      expect(albums[1].name, 'Album Two');
      expect(albums[1].trackCount, 8);

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('getAlbumList2'),
      );
      expect(req.queryParameters['type'], 'newest');
      expect(req.queryParameters['size'], 5);
      expect(req.queryParameters['u'], 'testuser');
      expect(req.queryParameters['f'], 'json');
    });

    test('artists parses indexed artist list', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'artists': {
                    'index': [
                      {
                        'artist': [
                          _artistMap(id: 'ar-1', name: 'Artist A'),
                          _artistMap(id: 'ar-2', name: 'Artist B'),
                        ],
                      },
                      {
                        'artist': [_artistMap(id: 'ar-3', name: 'Artist C')],
                      },
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final artists = await client.artists(limit: 10);

      expect(artists, hasLength(3));
      expect(artists[0].id, 'ar-1');
      expect(artists[0].name, 'Artist A');
      expect(artists[1].name, 'Artist B');
      expect(artists[2].name, 'Artist C');
    });

    test('favoriteAlbums uses type=starred', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'albumList2': {'album': []},
                }),
              ),
            );
          },
        ),
      );

      await client.favoriteAlbums(limit: 15);

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('getAlbumList2'),
      );
      expect(req.queryParameters['type'], 'starred');
      expect(req.queryParameters['size'], 15);
    });
  });

  group('Detail views', () {
    test('album returns album with parsed tracks', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'album': {
                    ..._albumMap(
                      id: 'a-1',
                      name: 'Detail Album',
                      year: 2023,
                      songCount: 3,
                      starred: '2025-03-01T00:00:00Z',
                    ),
                    'song': [
                      _trackMap(
                        id: 't-1',
                        title: 'Song One',
                        track: 1,
                        duration: 180,
                      ),
                      _trackMap(
                        id: 't-2',
                        title: 'Song Two',
                        track: 2,
                        duration: 240,
                      ),
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final result = await client.album('a-1');

      expect(result, isNotNull);
      expect(result!.album.id, 'a-1');
      expect(result.album.name, 'Detail Album');
      expect(result.album.year, 2023);
      expect(result.album.isFavorite, isTrue);
      expect(result.tracks, hasLength(2));
      expect(result.tracks[0].title, 'Song One');
      expect(result.tracks[0].trackNumber, 1);
      expect(result.tracks[1].title, 'Song Two');
    });

    test('artist returns parsed artist', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'artist': {
                    ..._artistMap(
                      id: 'ar-1',
                      name: 'Great Artist',
                      coverArt: 'ca-1',
                    ),
                    'album': [_albumMap(id: 'a-1'), _albumMap(id: 'a-2')],
                  },
                }),
              ),
            );
          },
        ),
      );

      final result = await client.artist('ar-1');

      expect(result, isNotNull);
      expect(result!.id, 'ar-1');
      expect(result.name, 'Great Artist');
      expect(result.albumCount, 2);
    });

    test('trackDetails returns full metadata', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'song': {
                    ..._trackMap(
                      id: 't-1',
                      title: 'Detailed Song',
                      suffix: 'flac',
                      bitRate: 1411,
                      samplingRate: 44100,
                      bitDepth: 16,
                      starred: '2025-06-01T00:00:00Z',
                    ),
                    'size': 12345678,
                    'channelCount': 2,
                    'path': '/music/test.flac',
                    'playCount': 42,
                    'played': '2025-06-15T10:30:00Z',
                    'year': 2024,
                    'discNumber': 1,
                    'albumArtist': 'Album Artist',
                    'composer': 'Composer Name',
                    'genre': 'Rock',
                  },
                }),
              ),
            );
          },
        ),
      );

      final result = await client.trackDetails('t-1');

      expect(result, isNotNull);
      expect(result!.track.id, 't-1');
      expect(result.track.title, 'Detailed Song');
      expect(result.container, 'flac');
      expect(result.sizeBytes, 12345678);
      expect(result.channels, 2);
      expect(result.sampleRateHz, 44100);
      expect(result.bitDepth, 16);
      expect(result.bitrateBps, 1411000);
      expect(result.path, '/music/test.flac');
      expect(result.playCount, 42);
      expect(result.year, 2024);
      expect(result.discNumber, 1);
      expect(result.albumArtist, 'Album Artist');
      expect(result.composer, 'Composer Name');
      expect(result.genres, contains('Rock'));
      expect(result.lastPlayedAt, DateTime.parse('2025-06-15T10:30:00Z'));
      expect(result.track.isFavorite, isTrue);
    });
  });

  group('Search', () {
    test('search returns typed result groups', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'searchResult3': {
                    'song': [_trackMap(id: 't-1', title: 'Found Track')],
                    'album': [_albumMap(id: 'a-1', name: 'Found Album')],
                    'artist': [_artistMap(id: 'ar-1', name: 'Found Artist')],
                    'playlist': [
                      _playlistMap(id: 'pl-1', name: 'Found Playlist'),
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final result = await client.search('test query');

      expect(result.tracks, hasLength(1));
      expect(result.tracks[0].title, 'Found Track');
      expect(result.albums, hasLength(1));
      expect(result.albums[0].name, 'Found Album');
      expect(result.artists, hasLength(1));
      expect(result.artists[0].name, 'Found Artist');
      expect(result.playlists, hasLength(1));
      expect(result.playlists[0].name, 'Found Playlist');

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('search3'),
      );
      expect(req.queryParameters['query'], 'test query');
      expect(req.queryParameters['songCount'], 20);
      expect(req.queryParameters['albumCount'], 20);
      expect(req.queryParameters['artistCount'], 20);
      expect(req.queryParameters['playlistCount'], 20);
    });
  });

  group('Playlists', () {
    test('playlists returns list of playlists', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'playlists': {
                    'playlist': [
                      _playlistMap(id: 'pl-1', name: 'My Mix'),
                      _playlistMap(id: 'pl-2', name: 'Chill Vibes'),
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final playlists = await client.playlists();

      expect(playlists, hasLength(2));
      expect(playlists[0].id, 'pl-1');
      expect(playlists[0].name, 'My Mix');
      expect(playlists[1].name, 'Chill Vibes');
    });

    test('playlist returns playlist with entry tracks', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'playlist': {
                    ..._playlistMap(
                      id: 'pl-1',
                      name: 'Detailed Playlist',
                      songCount: 2,
                    ),
                    'entry': [
                      _trackMap(id: 't-1', title: 'Playlist Track 1'),
                      _trackMap(id: 't-2', title: 'Playlist Track 2'),
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final result = await client.playlist('pl-1');

      expect(result, isNotNull);
      expect(result!.playlist.id, 'pl-1');
      expect(result.playlist.name, 'Detailed Playlist');
      expect(result.tracks, hasLength(2));
      expect(result.tracks[0].title, 'Playlist Track 1');
      expect(result.tracks[1].title, 'Playlist Track 2');

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('getPlaylist'),
      );
      expect(req.queryParameters['id'], 'pl-1');
    });
  });

  group('Favorites', () {
    test('setFavorite true calls star endpoint', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({}),
              ),
            );
          },
        ),
      );

      await client.setFavorite('t-1', true);

      final req = capturedRequests.firstWhere((r) => r.path.contains('star'));
      expect(req.queryParameters['id'], 't-1');
    });

    test('setFavorite false calls unstar endpoint', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({}),
              ),
            );
          },
        ),
      );

      await client.setFavorite('t-1', false);

      final req = capturedRequests.firstWhere((r) => r.path.contains('unstar'));
      expect(req.queryParameters['id'], 't-1');
    });
  });

  group('Playback reporting', () {
    test('reportPlaybackStart calls scrobble with submission=false', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({}),
              ),
            );
          },
        ),
      );

      await client.reportPlaybackStart('t-1');

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('scrobble'),
      );
      expect(req.queryParameters['id'], 't-1');
      expect(req.queryParameters['submission'], false);
    });

    test('reportPlaybackStop calls scrobble with submission=true', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({}),
              ),
            );
          },
        ),
      );

      await client.reportPlaybackStop('t-1', const Duration(seconds: 200));

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('scrobble'),
      );
      expect(req.queryParameters['id'], 't-1');
      expect(req.queryParameters['submission'], true);
      expect(req.queryParameters['time'], '200000');
    });
  });

  group('Streaming URLs', () {
    test('trackStreamUrl includes auth params and id', () {
      final url = client.trackStreamUrl('t-1');
      final uri = Uri.parse(url);
      expect(uri.queryParameters['id'], 't-1');
      expect(uri.queryParameters['u'], 'testuser');
      expect(uri.queryParameters['v'], '1.16.1');
      expect(uri.queryParameters['c'], 'Aetherfin');
      expect(uri.queryParameters['f'], 'json');
      expect(uri.queryParameters['t'], isNotEmpty);
      expect(uri.queryParameters['s'], isNotEmpty);
      expect(uri.queryParameters['format'], 'raw');
      expect(uri.path.endsWith('/rest/stream.view'), isTrue);
    });

    test('coverArtUrl returns URL with size and auth params', () {
      final url = client.coverArtUrl('ca-1', size: 300);
      expect(url, isNotNull);
      final uri = Uri.parse(url!);
      expect(uri.queryParameters['id'], 'ca-1');
      expect(uri.queryParameters['size'], '300');
      expect(uri.queryParameters['u'], 'testuser');
      expect(uri.queryParameters['f'], 'json');
      expect(uri.path.endsWith('/rest/getCoverArt.view'), isTrue);
    });

    test('coverArtUrl returns null for null id', () {
      expect(client.coverArtUrl(null), isNull);
    });
  });

  group('Error handling', () {
    test('api error status throws SubsonicApiError', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _errorResponse(40, 'Wrong username or password'),
              ),
            );
          },
        ),
      );

      expect(
        () => client.recentlyAddedAlbums(),
        throwsA(isA<SubsonicApiError>().having((e) => e.code, 'code', 40)),
      );
    });
  });

  group('Auth params', () {
    test('all requests carry Subsonic auth query parameters', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'albumList2': {'album': []},
                }),
              ),
            );
          },
        ),
      );

      await client.allAlbums();

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('getAlbumList2'),
      );
      final qp = req.queryParameters;
      expect(qp['u'], 'testuser');
      expect(qp['t'], isNotEmpty);
      expect(qp['s'], isNotEmpty);
      expect(qp['v'], '1.16.1');
      expect(qp['c'], 'Aetherfin');
      expect(qp['f'], 'json');
    });
  });
}
