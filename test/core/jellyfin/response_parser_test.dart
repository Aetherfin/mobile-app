import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/response_parser.dart';
import 'package:aetherfin/core/jellyfin/url_builder.dart';

JellyfinResponseParser _parser({String baseUrl = 'http://srv:8096'}) =>
    JellyfinResponseParser(
      JellyfinUrlBuilder(
        baseUrl: baseUrl,
        deviceId: 'dev-1',
        clientVersion: '9.9.9-test',
        accessToken: 't-abc',
        userId: 'u-1',
      ),
    );

Map<String, dynamic> _albumJson({
  String id = 'album-1',
  String name = 'Test Album',
  bool hasArtists = true,
  bool hasUserData = true,
  bool isFavorite = false,
  bool includeRunTimeTicks = true,
  int? runTimeTicks,
}) => {
  'Id': id,
  'Name': name,
  if (hasArtists)
    'AlbumArtists': [
      {'Id': 'artist-1', 'Name': 'Test Artist'},
    ],
  'AlbumArtist': 'Test Artist',
  'ChildCount': 12,
  'ProductionYear': 2024,
  if (includeRunTimeTicks) 'RunTimeTicks': runTimeTicks ?? 4200000000,
  'DateCreated': '2024-01-15T10:30:00Z',
  'ImageTags': {'Primary': 'tag-abc'},
  if (hasUserData) 'UserData': {'IsFavorite': isFavorite},
};

Map<String, dynamic> _artistJson({
  String id = 'artist-1',
  String name = 'Test Artist',
  bool hasOverview = true,
}) => {
  'Id': id,
  'Name': name,
  'AlbumCount': 5,
  'SongCount': 42,
  'ImageTags': {'Primary': 'tag-artist'},
  if (hasOverview) 'Overview': 'A great artist.',
};

Map<String, dynamic> _trackJson({
  String id = 'track-1',
  String title = 'Test Song',
  bool withMediaSources = true,
  bool withArtistItems = true,
  bool withAlbumImage = false,
  bool hasUserData = true,
  bool isFavorite = false,
  bool includeRunTimeTicks = true,
  int? runTimeTicks,
  String? codec,
}) => {
  'Id': id,
  'Name': title,
  'Album': 'Test Album',
  'AlbumId': 'album-1',
  'IndexNumber': 3,
  'ParentIndexNumber': 1,
  if (includeRunTimeTicks) 'RunTimeTicks': runTimeTicks ?? 2100000000,
  'DateCreated': '2024-06-20T14:00:00Z',
  'ImageTags': {'Primary': 'tag-track'},
  if (withAlbumImage) 'AlbumPrimaryImageTag': 'tag-album',
  if (withArtistItems)
    'ArtistItems': [
      {'Id': 'artist-1', 'Name': 'Test Artist'},
    ]
  else
    'Artists': ['Test Artist'],
  if (withMediaSources)
    'MediaSources': [
      {
        'Container': 'flac',
        'Bitrate': 800000,
        'MediaStreams': [
          {
            'Type': 'Audio',
            'Codec': codec ?? 'flac',
            'BitRate': 800000,
            'SampleRate': 44100,
            'BitDepth': 16,
          },
        ],
      },
    ],
  if (hasUserData) 'UserData': {'IsFavorite': isFavorite},
};

Map<String, dynamic> _playlistJson({
  String id = 'playlist-1',
  String name = 'My Playlist',
  bool useCumulative = true,
  bool isPublic = false,
}) => {
  'Id': id,
  'Name': name,
  'ChildCount': 20,
  if (useCumulative) 'CumulativeRunTimeTicks': 42000000000,
  'RunTimeTicks': 100000000,
  'ImageTags': {'Primary': 'tag-pl'},
  'IsPublic': isPublic,
};

void main() {
  group('parseItemList', () {
    test('returns empty list for null data', () {
      final result = _parser().parseItemList(null);
      expect(result, isEmpty);
    });

    test('returns empty list for empty map', () {
      final result = _parser().parseItemList({});
      expect(result, isEmpty);
    });

    test('returns empty list when Items is null', () {
      final result = _parser().parseItemList({'Items': null});
      expect(result, isEmpty);
    });

    test('returns empty list when Items is empty array', () {
      final result = _parser().parseItemList({'Items': <dynamic>[]});
      expect(result, isEmpty);
    });

    test('parses Items list from envelope', () {
      final result = _parser().parseItemList({
        'Items': <dynamic>[_albumJson(), _albumJson(id: 'album-2')],
      });
      expect(result, hasLength(2));
      expect(result[0]['Id'], 'album-1');
      expect(result[1]['Id'], 'album-2');
    });

    test('filters null entries from Items', () {
      final result = _parser().parseItemList({
        'Items': <dynamic>[_albumJson(), null, _albumJson(id: 'album-2')],
      });
      expect(result, hasLength(2));
    });

    test('filters non-Map entries from Items', () {
      final result = _parser().parseItemList({
        'Items': <dynamic>[
          _albumJson(),
          'string',
          42,
          _albumJson(id: 'album-2'),
        ],
      });
      expect(result, hasLength(2));
    });
  });

  group('parseRawItemList', () {
    test('returns empty list for null data', () {
      final result = _parser().parseRawItemList(null);
      expect(result, isEmpty);
    });

    test('returns empty list for empty array', () {
      final result = _parser().parseRawItemList([]);
      expect(result, isEmpty);
    });

    test('parses top-level JSON array', () {
      final result = _parser().parseRawItemList(<dynamic>[
        _albumJson(),
        _albumJson(id: 'album-2'),
      ]);
      expect(result, hasLength(2));
      expect(result[0]['Id'], 'album-1');
      expect(result[1]['Id'], 'album-2');
    });
  });

  group('normaliseItems', () {
    test('filters non-Map entries and casts types', () {
      final result = _parser().normaliseItems([
        {'Id': 'a'},
        'bogus',
        42,
        null,
        {'Id': 'b'},
      ]);
      expect(result, hasLength(2));
      expect(result[0]['Id'], 'a');
      expect(result[1]['Id'], 'b');
    });

    test('returns empty for empty input', () {
      final result = _parser().normaliseItems([]);
      expect(result, isEmpty);
    });
  });

  group('parseAlbum', () {
    test('parses full album JSON into AfAlbum', () {
      final album = _parser().parseAlbum(_albumJson());
      expect(album.id, 'album-1');
      expect(album.name, 'Test Album');
      expect(album.artistName, 'Test Artist');
      expect(album.artistId, 'artist-1');
      expect(album.trackCount, 12);
      expect(album.year, 2024);
      expect(album.totalDuration, const Duration(seconds: 420));
      expect(album.isFavorite, false);
      expect(album.dateAdded, DateTime.utc(2024, 1, 15, 10, 30, 0));
      expect(album.imageUrl, isNotNull);
      expect(album.imageUrl!.contains('album-1'), isTrue);
    });

    test('handles favorite true', () {
      final album = _parser().parseAlbum(_albumJson(isFavorite: true));
      expect(album.isFavorite, isTrue);
    });

    test('handles missing UserData', () {
      final album = _parser().parseAlbum(_albumJson(hasUserData: false));
      expect(album.isFavorite, false);
    });

    test('handles missing Id and Name with defaults', () {
      final album = _parser().parseAlbum({'ChildCount': 5});
      expect(album.id, '');
      expect(album.name, 'Unknown');
      expect(album.artistName, '');
      expect(album.artistId, isNull);
      expect(album.trackCount, 5);
      expect(album.year, isNull);
      expect(album.totalDuration, Duration.zero);
      expect(album.isFavorite, false);
      expect(album.dateAdded, isNull);
      expect(album.imageUrl, isNull);
    });

    test('converts RunTimeTicks to Duration correctly', () {
      const oneHourTicks = 36000000000;
      final album = _parser().parseAlbum(
        _albumJson(runTimeTicks: oneHourTicks),
      );
      expect(album.totalDuration, const Duration(hours: 1));
    });

    test('handles RunTimeTicks as int zero', () {
      final album = _parser().parseAlbum(_albumJson(runTimeTicks: 0));
      expect(album.totalDuration, Duration.zero);
    });

    test('handles null RunTimeTicks', () {
      final album = _parser().parseAlbum(
        _albumJson(includeRunTimeTicks: false),
      );
      expect(album.totalDuration, Duration.zero);
    });

    test('handles missing ChildCount', () {
      final album = _parser().parseAlbum({'Id': 'a', 'Name': 'A'});
      expect(album.trackCount, 0);
    });

    test('handles missing ProductionYear', () {
      final album = _parser().parseAlbum({'Id': 'a', 'Name': 'A'});
      expect(album.year, isNull);
    });

    test('handles missing DateCreated', () {
      final album = _parser().parseAlbum({'Id': 'a', 'Name': 'A'});
      expect(album.dateAdded, isNull);
    });

    test('extracts imageUrl from ImageTags', () {
      final album = _parser().parseAlbum(_albumJson());
      expect(album.imageUrl, contains('album-1/Images/Primary'));
      expect(album.imageUrl, contains('tag=tag-abc'));
    });

    test('returns null imageUrl when no ImageTags', () {
      final album = _parser().parseAlbum({'Id': 'a', 'Name': 'A'});
      expect(album.imageUrl, isNull);
    });

    test('extracts artistName from AlbumArtists first entry', () {
      final album = _parser().parseAlbum(_albumJson());
      expect(album.artistName, 'Test Artist');
    });

    test('falls back to AlbumArtist string when AlbumArtists is empty', () {
      final json = _albumJson()..remove('AlbumArtists');
      final album = _parser().parseAlbum(json);
      expect(album.artistName, 'Test Artist');
    });

    test('falls back to Artists list when no AlbumArtists or AlbumArtist', () {
      final json = {
        'Id': 'a',
        'Name': 'A',
        'Artists': ['Fallback Artist'],
      };
      final album = _parser().parseAlbum(json);
      expect(album.artistName, 'Fallback Artist');
    });

    test('extracts artistId from AlbumArtists first entry', () {
      final album = _parser().parseAlbum(_albumJson());
      expect(album.artistId, 'artist-1');
    });

    test('returns null artistId when AlbumArtists has no Id', () {
      final json = {
        'Id': 'a',
        'Name': 'A',
        'AlbumArtists': [
          {'Name': 'No Id Artist'},
        ],
      };
      final album = _parser().parseAlbum(json);
      expect(album.artistId, isNull);
    });

    test('returns null artistId when AlbumArtists is missing', () {
      final json = {'Id': 'a', 'Name': 'A'};
      final album = _parser().parseAlbum(json);
      expect(album.artistId, isNull);
    });
  });

  group('parseArtist', () {
    test('parses full artist JSON into AfArtist', () {
      final artist = _parser().parseArtist(_artistJson());
      expect(artist.id, 'artist-1');
      expect(artist.name, 'Test Artist');
      expect(artist.albumCount, 5);
      expect(artist.trackCount, 42);
      expect(artist.bio, 'A great artist.');
      expect(artist.imageUrl, isNotNull);
      expect(artist.imageUrl!.contains('artist-1'), isTrue);
    });

    test('handles missing Id and Name with defaults', () {
      final artist = _parser().parseArtist({'AlbumCount': 3});
      expect(artist.id, '');
      expect(artist.name, 'Unknown');
      expect(artist.albumCount, 3);
      expect(artist.trackCount, 0);
    });

    test('handles missing AlbumCount', () {
      final artist = _parser().parseArtist({'Id': 'a', 'Name': 'A'});
      expect(artist.albumCount, 0);
    });

    test('falls back to ChildCount when SongCount is missing', () {
      final artist = _parser().parseArtist({
        'Id': 'a',
        'Name': 'A',
        'ChildCount': 7,
      });
      expect(artist.trackCount, 7);
    });

    test('prefers SongCount over ChildCount', () {
      final artist = _parser().parseArtist({
        'Id': 'a',
        'Name': 'A',
        'SongCount': 10,
        'ChildCount': 5,
      });
      expect(artist.trackCount, 10);
    });

    test('handles missing Overview', () {
      final artist = _parser().parseArtist(_artistJson(hasOverview: false));
      expect(artist.bio, isNull);
    });

    test('handles null Overview', () {
      final artist = _parser().parseArtist({
        'Id': 'a',
        'Name': 'A',
        'Overview': null,
      });
      expect(artist.bio, isNull);
    });

    test('returns null imageUrl when no ImageTags', () {
      final artist = _parser().parseArtist({'Id': 'a', 'Name': 'A'});
      expect(artist.imageUrl, isNull);
    });
  });

  group('parseTrack', () {
    test('parses full track JSON into AfTrack', () {
      final track = _parser().parseTrack(_trackJson());
      expect(track.id, 'track-1');
      expect(track.title, 'Test Song');
      expect(track.artistName, 'Test Artist');
      expect(track.artistId, 'artist-1');
      expect(track.albumName, 'Test Album');
      expect(track.albumId, 'album-1');
      expect(track.trackNumber, 3);
      expect(track.duration, const Duration(seconds: 210));
      expect(track.isFavorite, false);
      expect(track.dateAdded, DateTime.utc(2024, 6, 20, 14, 0, 0));
      expect(track.imageUrl, isNotNull);
    });

    test('parses quality from MediaSources', () {
      final track = _parser().parseTrack(_trackJson(codec: 'flac'));
      expect(track.quality, isNotNull);
      expect(track.quality!.sourceCodec, 'flac');
      expect(track.quality!.bitDepth, 16);
      expect(track.quality!.sampleRateKhz, 44);
      expect(track.quality!.bitrateKbps, isNull);
    });

    test('handles AAC lossy quality', () {
      final track = _parser().parseTrack(_trackJson(codec: 'aac'));
      expect(track.quality, isNotNull);
      expect(track.quality!.sourceCodec, 'aac');
      expect(track.quality!.bitrateKbps, 800);
      expect(track.quality!.bitDepth, isNull);
      expect(track.quality!.sampleRateKhz, isNull);
    });

    test('handles missing Id and Name with defaults', () {
      final track = _parser().parseTrack({'Album': 'A'});
      expect(track.id, '');
      expect(track.title, 'Unknown');
      expect(track.albumName, 'A');
    });

    test('handles missing Album', () {
      final track = _parser().parseTrack({'Id': 'a', 'Name': 'N'});
      expect(track.albumName, '');
    });

    test('handles missing AlbumId', () {
      final track = _parser().parseTrack({'Id': 'a', 'Name': 'N'});
      expect(track.albumId, isNull);
    });

    test('handles missing IndexNumber', () {
      final track = _parser().parseTrack({'Id': 'a', 'Name': 'N'});
      expect(track.trackNumber, isNull);
    });

    test('converts RunTimeTicks to Duration correctly', () {
      const fiveMinTicks = 3000000000;
      final track = _parser().parseTrack(
        _trackJson(runTimeTicks: fiveMinTicks),
      );
      expect(track.duration, const Duration(seconds: 300));
    });

    test('handles null RunTimeTicks', () {
      final track = _parser().parseTrack(
        _trackJson(includeRunTimeTicks: false),
      );
      expect(track.duration, Duration.zero);
    });

    test('handles favorite true via UserData', () {
      final track = _parser().parseTrack(_trackJson(isFavorite: true));
      expect(track.isFavorite, isTrue);
    });

    test('handles missing UserData', () {
      final track = _parser().parseTrack(_trackJson(hasUserData: false));
      expect(track.isFavorite, false);
    });

    test('extracts imageUrl from ImageTags', () {
      final track = _parser().parseTrack(_trackJson());
      expect(track.imageUrl, contains('track-1/Images/Primary'));
    });

    test('falls back to album image when no track ImageTags', () {
      final json = _trackJson(withAlbumImage: true);
      json.remove('ImageTags');
      final track = _parser().parseTrack(json);
      expect(track.imageUrl, contains('album-1/Images/Primary'));
      expect(track.imageUrl, contains('tag=tag-album'));
    });

    test('returns null imageUrl when no images available', () {
      final track = _parser().parseTrack({'Id': 'a', 'Name': 'N'});
      expect(track.imageUrl, isNull);
    });

    test('extracts artistId from ArtistItems first entry', () {
      final track = _parser().parseTrack(_trackJson());
      expect(track.artistId, 'artist-1');
    });

    test('sets null artistId when ArtistItems is empty', () {
      final json = _trackJson(withArtistItems: true);
      json['ArtistItems'] = <dynamic>[];
      final track = _parser().parseTrack(json);
      expect(track.artistId, isNull);
    });

    test('sets null artistId when no ArtistItems', () {
      final json = _trackJson(withArtistItems: false);
      final track = _parser().parseTrack(json);
      expect(track.artistId, isNull);
    });

    test('parses DateCreated correctly', () {
      final track = _parser().parseTrack(_trackJson());
      expect(track.dateAdded, DateTime.utc(2024, 6, 20, 14, 0, 0));
    });

    test('handles null DateCreated', () {
      final track = _parser().parseTrack({'Id': 'a', 'Name': 'N'});
      expect(track.dateAdded, isNull);
    });

    test('uses Artists flat list as fallback artistName', () {
      final json = {
        'Id': 'a',
        'Name': 'N',
        'Album': 'A',
        'Artists': ['Flat Artist1', 'Flat Artist2'],
      };
      final track = _parser().parseTrack(json);
      expect(track.artistName, 'Flat Artist1, Flat Artist2');
    });

    test('uses AlbumArtist as last resort for artistName', () {
      final json = {
        'Id': 'a',
        'Name': 'N',
        'Album': 'A',
        'AlbumArtist': 'Last Resort',
      };
      final track = _parser().parseTrack(json);
      expect(track.artistName, 'Last Resort');
    });

    test('returns empty artistName when no artist fields present', () {
      final track = _parser().parseTrack({
        'Id': 'a',
        'Name': 'N',
        'Album': 'A',
      });
      expect(track.artistName, '');
    });
  });

  group('parsePlaylist', () {
    test('parses full playlist JSON into AfPlaylist', () {
      final pl = _parser().parsePlaylist(_playlistJson());
      expect(pl.id, 'playlist-1');
      expect(pl.name, 'My Playlist');
      expect(pl.trackCount, 20);
      expect(pl.duration, const Duration(hours: 1, minutes: 10));
      expect(pl.isPublic, false);
      expect(pl.imageUrl, isNotNull);
    });

    test('prefers CumulativeRunTimeTicks over RunTimeTicks', () {
      final pl = _parser().parsePlaylist(_playlistJson(useCumulative: true));
      expect(pl.duration, const Duration(seconds: 4200));
    });

    test(
      'falls back to RunTimeTicks when CumulativeRunTimeTicks is missing',
      () {
        final pl = _parser().parsePlaylist(_playlistJson(useCumulative: false));
        expect(pl.duration, const Duration(seconds: 10));
      },
    );

    test('handles missing Id and Name with defaults', () {
      final pl = _parser().parsePlaylist({'ChildCount': 5});
      expect(pl.id, '');
      expect(pl.name, 'Unknown');
      expect(pl.trackCount, 5);
      expect(pl.duration, Duration.zero);
    });

    test('handles null duration ticks', () {
      final pl = _parser().parsePlaylist({'Id': 'p', 'Name': 'P'});
      expect(pl.duration, Duration.zero);
    });

    test('parses isPublic true', () {
      final pl = _parser().parsePlaylist(_playlistJson(isPublic: true));
      expect(pl.isPublic, isTrue);
    });

    test('parses isPublic false', () {
      final pl = _parser().parsePlaylist(_playlistJson(isPublic: false));
      expect(pl.isPublic, isFalse);
    });

    test('handles missing ChildCount', () {
      final pl = _parser().parsePlaylist({'Id': 'p', 'Name': 'P'});
      expect(pl.trackCount, 0);
    });

    test('returns null imageUrl when no ImageTags', () {
      final pl = _parser().parsePlaylist({'Id': 'p', 'Name': 'P'});
      expect(pl.imageUrl, isNull);
    });
  });

  group('parseQuality', () {
    test('returns null when MediaSources is missing', () {
      final q = _parser().parseQuality({'Id': 'a'});
      expect(q, isNull);
    });

    test('returns null when MediaSources is empty', () {
      final q = _parser().parseQuality({
        'Id': 'a',
        'MediaSources': <dynamic>[],
      });
      expect(q, isNull);
    });

    test('returns null when no Audio MediaStreams', () {
      final q = _parser().parseQuality({
        'MediaSources': [
          {
            'MediaStreams': [
              {'Type': 'Video', 'Codec': 'h264'},
            ],
          },
        ],
      });
      expect(q, isNull);
    });

    test('extracts FLAC lossless quality', () {
      final q = _parser().parseQuality({
        'MediaSources': [
          {
            'Container': 'flac',
            'MediaStreams': [
              {
                'Type': 'Audio',
                'Codec': 'flac',
                'BitRate': 800000,
                'SampleRate': 44100,
                'BitDepth': 16,
              },
            ],
          },
        ],
      });
      expect(q, isNotNull);
      expect(q!.sourceCodec, 'flac');
      expect(q.bitDepth, 16);
      expect(q.sampleRateKhz, 44);
      expect(q.bitrateKbps, isNull);
    });

    test('extracts ALAC lossless quality', () {
      final q = _parser().parseQuality({
        'MediaSources': [
          {
            'MediaStreams': [
              {
                'Type': 'Audio',
                'Codec': 'alac',
                'BitRate': 700000,
                'SampleRate': 96000,
                'BitDepth': 24,
              },
            ],
          },
        ],
      });
      expect(q, isNotNull);
      expect(q!.sourceCodec, 'alac');
      expect(q.bitDepth, 24);
      expect(q.sampleRateKhz, 96);
      expect(q.bitrateKbps, isNull);
    });

    test('extracts WAV lossless quality', () {
      final q = _parser().parseQuality({
        'MediaSources': [
          {
            'MediaStreams': [
              {
                'Type': 'Audio',
                'Codec': 'wav',
                'SampleRate': 48000,
                'BitDepth': 24,
              },
            ],
          },
        ],
      });
      expect(q, isNotNull);
      expect(q!.sourceCodec, 'wav');
      expect(q.bitDepth, 24);
      expect(q.sampleRateKhz, 48);
    });

    test('extracts AAC lossy quality with bitrate', () {
      final q = _parser().parseQuality({
        'MediaSources': [
          {
            'MediaStreams': [
              {
                'Type': 'Audio',
                'Codec': 'aac',
                'BitRate': 256000,
                'SampleRate': 44100,
                'BitDepth': 16,
              },
            ],
          },
        ],
      });
      expect(q, isNotNull);
      expect(q!.sourceCodec, 'aac');
      expect(q.bitrateKbps, 256);
      expect(q.bitDepth, isNull);
      expect(q.sampleRateKhz, isNull);
    });

    test(
      'falls back to source-level Bitrate when stream BitRate is missing',
      () {
        final q = _parser().parseQuality({
          'MediaSources': [
            {
              'Bitrate': 320000,
              'MediaStreams': [
                {'Type': 'Audio', 'Codec': 'mp3'},
              ],
            },
          ],
        });
        expect(q, isNotNull);
        expect(q!.bitrateKbps, 320);
      },
    );

    test('falls back to Container when no Codec on audio stream', () {
      final q = _parser().parseQuality({
        'MediaSources': [
          {
            'Container': 'OGG',
            'MediaStreams': [
              {'Type': 'Audio', 'BitRate': 128000},
            ],
          },
        ],
      });
      expect(q, isNotNull);
      expect(q!.sourceCodec, 'ogg');
    });

    test('returns null for empty MediaSources list entry', () {
      final q = _parser().parseQuality({
        'MediaSources': [null, 'string'],
      });
      expect(q, isNull);
    });
  });

  group('albumArtistName', () {
    test('returns name from AlbumArtists first entry', () {
      final name = _parser().albumArtistName({
        'AlbumArtists': [
          {'Name': 'First Artist'},
          {'Name': 'Second Artist'},
        ],
      });
      expect(name, 'First Artist');
    });

    test('returns empty string from AlbumArtists with null Name', () {
      final name = _parser().albumArtistName({
        'AlbumArtists': [
          {'Id': 'x'},
        ],
      });
      expect(name, '');
    });

    test('falls back to AlbumArtist string when AlbumArtists is empty', () {
      final name = _parser().albumArtistName({
        'AlbumArtists': <dynamic>[],
        'AlbumArtist': 'Fallback',
      });
      expect(name, 'Fallback');
    });

    test('falls back to AlbumArtist when AlbumArtists has no entries', () {
      final name = _parser().albumArtistName({'AlbumArtist': 'Fallback'});
      expect(name, 'Fallback');
    });

    test('falls back to Artists list joined with comma', () {
      final name = _parser().albumArtistName({
        'Artists': ['A1', 'A2'],
      });
      expect(name, 'A1, A2');
    });

    test('returns empty string when no artist fields present', () {
      final name = _parser().albumArtistName({});
      expect(name, '');
    });

    test('handles null first entry in AlbumArtists', () {
      final name = _parser().albumArtistName({
        'AlbumArtists': [
          null,
          {'Name': 'Valid'},
        ],
      });
      expect(name, 'Valid');
    });
  });

  group('albumArtistId', () {
    test('returns Id from AlbumArtists first entry', () {
      final id = _parser().albumArtistId({
        'AlbumArtists': [
          {'Id': 'artist-1', 'Name': 'A'},
        ],
      });
      expect(id, 'artist-1');
    });

    test('returns null when AlbumArtists entry has no Id', () {
      final id = _parser().albumArtistId({
        'AlbumArtists': [
          {'Name': 'A'},
        ],
      });
      expect(id, isNull);
    });

    test('returns null when AlbumArtists is empty', () {
      final id = _parser().albumArtistId({'AlbumArtists': <dynamic>[]});
      expect(id, isNull);
    });

    test('returns null when AlbumArtists is missing', () {
      final id = _parser().albumArtistId({});
      expect(id, isNull);
    });

    test('handles null first entry in AlbumArtists', () {
      final id = _parser().albumArtistId({
        'AlbumArtists': [
          null,
          {'Id': 'a2'},
        ],
      });
      expect(id, 'a2');
    });
  });

  group('trackArtistName', () {
    test('returns names from ArtistItems joined with comma', () {
      final name = _parser().trackArtistName({
        'ArtistItems': [
          {'Name': 'Artist A'},
          {'Name': 'Artist B'},
        ],
      });
      expect(name, 'Artist A, Artist B');
    });

    test('filters null names in ArtistItems', () {
      final name = _parser().trackArtistName({
        'ArtistItems': [
          {'Name': null},
          {'Name': 'Valid'},
          {'Id': 'x'},
        ],
      });
      expect(name, 'Valid');
    });

    test('falls back to Artists flat list when ArtistItems is empty', () {
      final name = _parser().trackArtistName({
        'ArtistItems': <dynamic>[],
        'Artists': ['Flat Artist'],
      });
      expect(name, 'Flat Artist');
    });

    test('falls back to Artists when ArtistItems is missing', () {
      final name = _parser().trackArtistName({
        'Artists': ['A1', 'A2'],
      });
      expect(name, 'A1, A2');
    });

    test('falls back to AlbumArtist', () {
      final name = _parser().trackArtistName({
        'AlbumArtist': 'Fallback Artist',
      });
      expect(name, 'Fallback Artist');
    });

    test('returns empty string when no artist fields', () {
      final name = _parser().trackArtistName({});
      expect(name, '');
    });

    test('returns comma-joined Artists list', () {
      final name = _parser().trackArtistName({
        'Artists': ['A', 'B', 'C'],
      });
      expect(name, 'A, B, C');
    });
  });
}
