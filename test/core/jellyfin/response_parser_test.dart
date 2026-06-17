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

    test('filters null entries from Items', () {
      final result = _parser().parseItemList({
        'Items': <dynamic>[_albumJson(), null, _albumJson(id: 'album-2')],
      });
      expect(result, hasLength(2));
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

    test('handles null RunTimeTicks', () {
      final album = _parser().parseAlbum(
        _albumJson(includeRunTimeTicks: false),
      );
      expect(album.totalDuration, Duration.zero);
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

    test('handles missing Id and Name with defaults', () {
      final track = _parser().parseTrack({'Album': 'A'});
      expect(track.id, '');
      expect(track.title, 'Unknown');
      expect(track.albumName, 'A');
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

    test('extracts imageUrl from ImageTags', () {
      final track = _parser().parseTrack(_trackJson());
      expect(track.imageUrl, contains('track-1/Images/Primary'));
    });

    test('returns null imageUrl when no images available', () {
      final track = _parser().parseTrack({'Id': 'a', 'Name': 'N'});
      expect(track.imageUrl, isNull);
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

    test('handles missing Id and Name with defaults', () {
      final pl = _parser().parsePlaylist({'ChildCount': 5});
      expect(pl.id, '');
      expect(pl.name, 'Unknown');
      expect(pl.trackCount, 5);
      expect(pl.duration, Duration.zero);
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
  });
}
