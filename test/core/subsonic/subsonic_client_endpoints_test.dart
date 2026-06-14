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
}) => {
  'id': id,
  'name': name,
  'albumCount': albumCount,
  'coverArt': ?coverArt,
};

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

    test('allAlbums passes offset and size params', () async {
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

      await client.allAlbums(limit: 50, startIndex: 100);

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('getAlbumList2'),
      );
      expect(req.queryParameters['type'], 'alphabeticalByName');
      expect(req.queryParameters['size'], 50);
      expect(req.queryParameters['offset'], 100);
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

    test('genres returns named genres with palette colours', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'genres': {
                    'genre': [
                      {'value': 'Rock'},
                      {'value': 'Jazz'},
                      {'value': 'Electronic'},
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final genres = await client.genres(limit: 10);

      expect(genres, hasLength(3));
      expect(genres[0].name, 'Rock');
      expect(genres[1].name, 'Jazz');
      expect(genres[2].name, 'Electronic');
      expect(genres[0].tint, isNotEmpty);
    });

    test('genres returns empty list on null genre data', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'genres': {'genre': null},
                }),
              ),
            );
          },
        ),
      );

      final genres = await client.genres();
      expect(genres, isEmpty);
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

    test('favoriteTracks parses starred2 response', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'starred2': {
                    'song': [
                      _trackMap(
                        id: 't-1',
                        title: 'Loved One',
                        starred: '2025-01-01T00:00:00Z',
                      ),
                      _trackMap(
                        id: 't-2',
                        title: 'Loved Two',
                        starred: '2025-01-02T00:00:00Z',
                      ),
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final tracks = await client.favoriteTracks(limit: 100);

      expect(tracks, hasLength(2));
      expect(tracks[0].id, 't-1');
      expect(tracks[0].title, 'Loved One');
      expect(tracks[0].isFavorite, isTrue);
      expect(tracks[1].isFavorite, isTrue);
    });

    test('favoriteTracks returns empty on null starred2', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({'starred2': null}),
              ),
            );
          },
        ),
      );

      final tracks = await client.favoriteTracks();
      expect(tracks, isEmpty);
    });

    test('recentlyPlayed fetches album list then album details', () async {
      final albumDetailResponse = _okResponse({
        'album': {
          ..._albumMap(id: 'a-1'),
          'song': [_trackMap(id: 't-1'), _trackMap(id: 't-2')],
        },
      });

      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            if (options.path.contains('getAlbumList2')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: _okResponse({
                    'albumList2': {
                      'album': [_albumMap(id: 'a-1', name: 'Recent Album')],
                    },
                  }),
                ),
              );
            } else if (options.path.contains('getAlbum')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: albumDetailResponse,
                ),
              );
            } else {
              handler.next(options);
            }
          },
        ),
      );

      final tracks = await client.recentlyPlayed(limit: 5);

      expect(tracks, isNotEmpty);
      expect(tracks[0].id, 't-1');

      final albumListReq = capturedRequests.firstWhere(
        (r) => r.path.contains('getAlbumList2'),
      );
      expect(albumListReq.queryParameters['type'], 'recent');
    });

    test('resumeItems returns empty list (Subsonic has no resume)', () async {
      final items = await client.resumeItems();
      expect(items, isEmpty);
    });

    test('albumsByGenre passes genre filter', () async {
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

      await client.albumsByGenre('Rock', limit: 50);

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('getAlbumList2'),
      );
      expect(req.queryParameters['type'], 'byGenre');
      expect(req.queryParameters['genre'], 'Rock');
      expect(req.queryParameters['size'], 50);
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

    test('album returns null on missing data', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({'album': null}),
              ),
            );
          },
        ),
      );

      final result = await client.album('a-missing');
      expect(result, isNull);
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

    test('artist returns null on missing data', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({'artist': null}),
              ),
            );
          },
        ),
      );

      final result = await client.artist('ar-missing');
      expect(result, isNull);
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

    test('trackDetails returns null on missing song data', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({'song': null}),
              ),
            );
          },
        ),
      );

      final result = await client.trackDetails('t-missing');
      expect(result, isNull);
    });

    test('trackDetails returns null on DioException', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );

      final result = await client.trackDetails('t-error');
      expect(result, isNull);
    });

    test('artistAlbums returns album list for artist', () async {
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
                    ..._artistMap(id: 'ar-1'),
                    'album': [
                      _albumMap(id: 'a-1', name: 'Album X'),
                      _albumMap(id: 'a-2', name: 'Album Y'),
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final albums = await client.artistAlbums('ar-1');

      expect(albums, hasLength(2));
      expect(albums[0].id, 'a-1');
      expect(albums[0].name, 'Album X');
      expect(albums[1].name, 'Album Y');
    });

    test('artistAlbums returns empty on null artist data', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({'artist': null}),
              ),
            );
          },
        ),
      );

      final albums = await client.artistAlbums('ar-missing');
      expect(albums, isEmpty);
    });

    test('artistTopTracks returns top songs list', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            if (options.path.contains('getArtist')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: _okResponse({
                    'artist': _artistMap(id: 'ar-1', name: 'Top Artist'),
                  }),
                ),
              );
            } else if (options.path.contains('getTopSongs')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: _okResponse({
                    'topSongs': {
                      'song': [
                        _trackMap(id: 't-1', title: 'Hit One'),
                        _trackMap(id: 't-2', title: 'Hit Two'),
                      ],
                    },
                  }),
                ),
              );
            } else {
              handler.next(options);
            }
          },
        ),
      );

      final tracks = await client.artistTopTracks('ar-1');

      expect(tracks, hasLength(2));
      expect(tracks[0].title, 'Hit One');
      expect(tracks[1].title, 'Hit Two');
    });

    test(
      'artistTopTracks falls back to search3 when getTopSongs fails',
      () async {
        client.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedRequests.add(options);
              if (options.path.contains('getArtist')) {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: _okResponse({
                      'artist': _artistMap(id: 'ar-1', name: 'Fallback Artist'),
                    }),
                  ),
                );
              } else if (options.path.contains('getTopSongs')) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.unknown,
                  ),
                );
              } else if (options.path.contains('search3')) {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: _okResponse({
                      'searchResult3': {
                        'song': [
                          _trackMap(id: 't-fallback', title: 'Fallback Track'),
                        ],
                      },
                    }),
                  ),
                );
              } else {
                handler.next(options);
              }
            },
          ),
        );

        final tracks = await client.artistTopTracks('ar-1');

        expect(tracks, hasLength(1));
        expect(tracks[0].title, 'Fallback Track');
      },
    );
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

    test('search with empty query returns empty results', () async {
      final result = await client.search('');

      expect(result.tracks, isEmpty);
      expect(result.albums, isEmpty);
      expect(result.artists, isEmpty);
      expect(result.playlists, isEmpty);
    });

    test('search with whitespace-only returns empty', () async {
      final result = await client.search('   ');
      expect(result.tracks, isEmpty);
    });

    test('allTracks uses search3 with empty query', () async {
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
                    'song': [
                      _trackMap(id: 't-1', title: 'All Track One'),
                      _trackMap(id: 't-2', title: 'All Track Two'),
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final tracks = await client.allTracks(limit: 100, startIndex: 50);

      expect(tracks, hasLength(2));
      expect(tracks[0].title, 'All Track One');

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('search3'),
      );
      expect(req.queryParameters['query'], '');
      expect(req.queryParameters['songCount'], 100);
      expect(req.queryParameters['songOffset'], 50);
      expect(req.queryParameters['albumCount'], 0);
      expect(req.queryParameters['artistCount'], 0);
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

    test('playlist returns null on missing data', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({'playlist': null}),
              ),
            );
          },
        ),
      );

      final result = await client.playlist('pl-missing');
      expect(result, isNull);
    });

    test('createPlaylist returns new playlist id', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'playlist': _playlistMap(id: 'pl-new', name: 'New Playlist'),
                }),
              ),
            );
          },
        ),
      );

      final id = await client.createPlaylist('New Playlist', ['t-1', 't-2']);

      expect(id, 'pl-new');

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('createPlaylist'),
      );
      expect(req.queryParameters['name'], 'New Playlist');
      expect(req.queryParameters['songId'], ['t-1', 't-2']);
    });

    test(
      'createPlaylist returns null when playlist missing from response',
      () async {
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

        final id = await client.createPlaylist('Empty', []);
        expect(id, isNull);
      },
    );

    test('deletePlaylist calls endpoint with id', () async {
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

      await client.deletePlaylist('pl-1');

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('deletePlaylist'),
      );
      expect(req.queryParameters['id'], 'pl-1');
    });

    test('renamePlaylist calls updatePlaylist with name', () async {
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

      await client.renamePlaylist('pl-1', 'Renamed');

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('updatePlaylist'),
      );
      expect(req.queryParameters['playlistId'], 'pl-1');
      expect(req.queryParameters['name'], 'Renamed');
    });

    test('addToPlaylist sends songIdToAdd list', () async {
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

      await client.addToPlaylist('pl-1', ['t-1', 't-2', 't-3']);

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('updatePlaylist'),
      );
      expect(req.queryParameters['playlistId'], 'pl-1');
      expect(req.queryParameters['songIdToAdd'], ['t-1', 't-2', 't-3']);
    });

    test('removeFromPlaylist fetches then removes by computed index', () async {
      final detail = {
        'playlist': {
          ..._playlistMap(id: 'pl-1', songCount: 3),
          'entry': [
            _trackMap(id: 't-1'),
            _trackMap(id: 't-target'),
            _trackMap(id: 't-3'),
          ],
        },
      };

      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            if (options.path.contains('getPlaylist')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: _okResponse(detail),
                ),
              );
            } else if (options.path.contains('updatePlaylist')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: _okResponse({}),
                ),
              );
            } else {
              handler.next(options);
            }
          },
        ),
      );

      await client.removeFromPlaylist('pl-1', ['t-target']);

      final updateReq = capturedRequests.firstWhere(
        (r) => r.path.contains('updatePlaylist'),
      );
      expect(updateReq.queryParameters['songIndexToRemove'], [1]);
      expect(updateReq.queryParameters['playlistId'], 'pl-1');
    });

    test('removeFromPlaylist skips when entryIds is empty', () async {
      await client.removeFromPlaylist('pl-1', []);
      // No requests should have been made
      expect(
        capturedRequests.where((r) => r.path.contains('playlist')),
        isEmpty,
      );
    });

    test('movePlaylistItem throws UnsupportedError', () async {
      expect(
        () => client.movePlaylistItem('pl-1', 't-1', 3),
        throwsA(isA<UnsupportedError>()),
      );
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

  group('Lyrics', () {
    test('lyrics parses synced lines with timestamps', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'lyricsList': {
                    'structuredLyrics': [
                      {
                        'synced': true,
                        'line': [
                          {'start': 0, 'value': 'First line'},
                          {'start': 5000, 'value': 'Second line'},
                          {'start': 120000, 'value': 'Two-minute line'},
                        ],
                      },
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final text = await client.lyrics('t-1');

      expect(text, isNotNull);
      expect(text, contains('[00:00.00]First line'));
      expect(text, contains('[00:05.00]Second line'));
      expect(text, contains('[02:00.00]Two-minute line'));
    });

    test('lyrics handles unsynced lines without timestamps', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'lyricsList': {
                    'structuredLyrics': [
                      {
                        'synced': false,
                        'line': [
                          {'value': 'Plain text line'},
                          {'value': 'Another line'},
                        ],
                      },
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final text = await client.lyrics('t-1');

      expect(text, isNotNull);
      expect(text, contains('Plain text line'));
      expect(text, contains('Another line'));
    });

    test('lyrics returns null when lyric list is empty', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'lyricsList': {'structuredLyrics': []},
                }),
              ),
            );
          },
        ),
      );

      final text = await client.lyrics('t-1');
      expect(text, isNull);
    });

    test('lyrics returns null on DioException', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );

      final text = await client.lyrics('t-1');
      expect(text, isNull);
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

    test('reportProgress calls scrobble with time param', () async {
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

      await client.reportProgress('t-1', const Duration(seconds: 90));

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('scrobble'),
      );
      expect(req.queryParameters['id'], 't-1');
      expect(req.queryParameters['submission'], false);
      expect(req.queryParameters['time'], '90000');
    });

    test('reportProgress skips API call when isPaused=true', () async {
      await client.reportProgress(
        't-1',
        const Duration(seconds: 30),
        isPaused: true,
      );
      // SubsonicClient skips when paused — no scrobble call
      expect(capturedRequests.any((r) => r.path.contains('scrobble')), isFalse);
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

    test('trackStreamUrl with maxBitrateKbps includes format=mp3', () {
      final url = client.trackStreamUrl('t-1', maxBitrateKbps: 256);
      final uri = Uri.parse(url);
      expect(uri.queryParameters['maxBitRate'], '256');
      expect(uri.queryParameters['format'], 'mp3');
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

    test('coverArtUrl returns null for empty id', () {
      expect(client.coverArtUrl(''), isNull);
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

    test('missing subsonic-response envelope throws StateError', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{},
              ),
            );
          },
        ),
      );

      expect(() => client.recentlyAddedAlbums(), throwsA(isA<StateError>()));
    });

    test('DioException is enriched and rethrown', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );

      expect(
        () => client.recentlyAddedAlbums(),
        throwsA(
          isA<DioException>().having(
            (e) => e.message,
            'message',
            contains('Subsonic API error'),
          ),
        ),
      );
    });
  });

  group('Server', () {
    test('ping returns updated server info and probes extensions', () async {
      final result = await client.ping();

      expect(result.isReachable, isTrue);
      expect(result.name, 'srv');
      expect(result.baseUrl, 'http://srv:4533');
      expect(result.version, '0.51.0');

      final pingReq = capturedRequests.firstWhere(
        (r) => r.path.contains('ping'),
      );
      expect(pingReq.queryParameters['u'], 'testuser');
      expect(pingReq.queryParameters['f'], 'json');

      final extReq = capturedRequests.firstWhere(
        (r) => r.path.contains('getOpenSubsonicExtensions'),
      );
      expect(extReq, isNotNull);
    });

    test('userViews returns default Music view', () async {
      final views = await client.userViews();

      expect(views, hasLength(1));
      expect(views[0].id, 'music');
      expect(views[0].name, 'Music');
      expect(views[0].collectionType, 'music');
    });

    test('instantMix returns similar songs', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _okResponse({
                  'similarSongs2': {
                    'song': [
                      _trackMap(id: 't-1', title: 'Similar One'),
                      _trackMap(id: 't-2', title: 'Similar Two'),
                    ],
                  },
                }),
              ),
            );
          },
        ),
      );

      final tracks = await client.instantMix('t-seed');

      expect(tracks, hasLength(2));
      expect(tracks[0].title, 'Similar One');

      final req = capturedRequests.firstWhere(
        (r) => r.path.contains('getSimilarSongs2'),
      );
      expect(req.queryParameters['id'], 't-seed');
      expect(req.queryParameters['count'], 50);
    });

    test('instantMix returns empty on DioException', () async {
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.unknown,
              ),
            );
          },
        ),
      );

      final tracks = await client.instantMix('t-seed');
      expect(tracks, isEmpty);
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

  group('Track parsing', () {
    test('parseTrack handles lossless FLAC track', () {
      final track = client.parseTrack(
        _trackMap(
          id: 't-flac',
          title: 'Lossless Track',
          suffix: 'flac',
          bitRate: 1411,
          samplingRate: 44100,
          bitDepth: 16,
        ),
      );

      expect(track.id, 't-flac');
      expect(track.title, 'Lossless Track');
      expect(track.quality?.sourceCodec, 'flac');
      expect(track.quality?.bitrateKbps, isNull);
      expect(track.quality?.bitDepth, 16);
      expect(track.quality?.sampleRateKhz, 44);
    });

    test('parseTrack handles lossy MP3 track', () {
      final track = client.parseTrack(
        _trackMap(
          id: 't-mp3',
          title: 'Lossy Track',
          suffix: 'mp3',
          bitRate: 320,
        ),
      );

      expect(track.quality?.sourceCodec, 'mp3');
      expect(track.quality?.bitrateKbps, 320);
      expect(track.quality?.bitDepth, isNull);
      expect(track.quality?.sampleRateKhz, isNull);
    });

    test('parseTrack handles starred (favorited) track', () {
      final track = client.parseTrack(
        _trackMap(id: 't-fav', starred: '2025-01-01T00:00:00Z'),
      );

      expect(track.isFavorite, isTrue);
    });

    test('parseTrack handles unfavorited track', () {
      final track = client.parseTrack(_trackMap(id: 't-nofav'));
      expect(track.isFavorite, isFalse);
    });
  });
}
