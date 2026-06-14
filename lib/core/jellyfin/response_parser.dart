import '../jellyfin/models/items.dart';
import '../jellyfin/models/quality.dart';
import 'url_builder.dart';

/// Parses Jellyfin JSON responses into domain models.
///
/// Stateless — all methods take the raw JSON and return typed models.
/// Requires a [JellyfinUrlBuilder] instance for image URL construction.
class JellyfinResponseParser {
  JellyfinResponseParser(this._urlBuilder);
  final JellyfinUrlBuilder _urlBuilder;

  static const trackFields =
      'PrimaryImageAspectRatio,MediaSources,RunTimeTicks,IndexNumber,ParentIndexNumber,ProductionYear,DateCreated,UserData';

  static const albumFields =
      'PrimaryImageAspectRatio,RunTimeTicks,ChildCount,ProductionYear,DateCreated,AlbumArtist,AlbumArtists,UserData';

  /// Extract `Items` list from a paged Jellyfin response.
  List<Map<String, dynamic>> parseItemList(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final items = data['Items'] as List? ?? const [];
    return normaliseItems(items);
  }

  /// Same as [parseItemList] but for endpoints that return a raw
  /// top-level JSON array (e.g. `/Users/{id}/Items/Latest`) instead of
  /// the usual `{Items: [...]}` envelope.
  List<Map<String, dynamic>> parseRawItemList(List<dynamic>? data) =>
      normaliseItems(data ?? const []);

  List<Map<String, dynamic>> normaliseItems(Iterable<dynamic> items) => items
      .whereType<Map<String, dynamic>>()
      .map((m) => m.cast<String, dynamic>())
      .toList(growable: false);

  AfAlbum parseAlbum(Map<String, dynamic> m) {
    final id = (m['Id'] as String?) ?? '';
    final ticks = m['RunTimeTicks'];
    final duration = ticks is num
        ? Duration(microseconds: ticks ~/ 10)
        : Duration.zero;
    final dateCreated = m['DateCreated'] as String?;
    final userData = (m['UserData'] as Map?)?.cast<String, dynamic>();
    return AfAlbum(
      id: id,
      name: (m['Name'] as String?) ?? 'Unknown',
      artistName: albumArtistName(m),
      artistId: albumArtistId(m),
      trackCount: (m['ChildCount'] as int?) ?? 0,
      year: m['ProductionYear'] as int?,
      totalDuration: duration,
      imageUrl: _urlBuilder.imageUrlFor(m, 'Primary', maxWidth: 480),
      dateAdded: dateCreated != null ? DateTime.tryParse(dateCreated) : null,
      isFavorite: (userData?['IsFavorite'] as bool?) ?? false,
    );
  }

  AfArtist parseArtist(Map<String, dynamic> m) {
    return AfArtist(
      id: (m['Id'] as String?) ?? '',
      name: (m['Name'] as String?) ?? 'Unknown',
      albumCount: (m['AlbumCount'] as int?) ?? 0,
      trackCount: (m['SongCount'] as int?) ?? (m['ChildCount'] as int?) ?? 0,
      imageUrl: _urlBuilder.imageUrlFor(m, 'Primary', maxWidth: 480),
      bio: m['Overview'] as String?,
    );
  }

  AfTrack parseTrack(Map<String, dynamic> m) {
    final ticks = m['RunTimeTicks'];
    final duration = ticks is num
        ? Duration(microseconds: ticks ~/ 10)
        : Duration.zero;
    final userData = (m['UserData'] as Map?)?.cast<String, dynamic>();
    final dateCreated = m['DateCreated'] as String?;
    final artistIds = (m['ArtistItems'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .map((i) => i['Id'])
        .whereType<String>()
        .toList();
    return AfTrack(
      id: (m['Id'] as String?) ?? '',
      title: (m['Name'] as String?) ?? 'Unknown',
      artistName: trackArtistName(m),
      albumName: (m['Album'] as String?) ?? '',
      albumId: m['AlbumId'] as String?,
      artistId: (artistIds != null && artistIds.isNotEmpty)
          ? artistIds.first
          : null,
      trackNumber: m['IndexNumber'] as int?,
      duration: duration,
      quality: parseQuality(m),
      imageUrl:
          _urlBuilder.imageUrlFor(m, 'Primary', maxWidth: 480) ??
          _urlBuilder.albumImageUrl(m, maxWidth: 480),
      isFavorite: (userData?['IsFavorite'] as bool?) ?? false,
      dateAdded: dateCreated != null ? DateTime.tryParse(dateCreated) : null,
    );
  }

  AfPlaylist parsePlaylist(Map<String, dynamic> m) {
    final ticks = m['CumulativeRunTimeTicks'] ?? m['RunTimeTicks'];
    final duration = ticks is num
        ? Duration(microseconds: ticks ~/ 10)
        : Duration.zero;
    return AfPlaylist(
      id: (m['Id'] as String?) ?? '',
      name: (m['Name'] as String?) ?? 'Unknown',
      trackCount: (m['ChildCount'] as int?) ?? 0,
      duration: duration,
      imageUrl: _urlBuilder.imageUrlFor(m, 'Primary', maxWidth: 480),
      isPublic: (m['IsPublic'] as bool?) ?? false,
    );
  }

  TrackQuality? parseQuality(Map<String, dynamic> m) {
    final sources = m['MediaSources'] as List?;
    if (sources == null || sources.isEmpty) return null;
    final mapSources = sources.whereType<Map<String, dynamic>>().toList();
    if (mapSources.isEmpty) return null;
    final src = mapSources.first.cast<String, dynamic>();
    final streams = (src['MediaStreams'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((s) => s.cast<String, dynamic>())
        .where((s) => (s['Type'] as String?) == 'Audio')
        .toList();
    if (streams.isEmpty) return null;
    final audio = streams.first;
    final codec =
        ((audio['Codec'] as String?) ?? (src['Container'] as String?) ?? '')
            .toLowerCase();
    final bitrate = audio['BitRate'] as int? ?? src['Bitrate'] as int?;
    final sampleRate = audio['SampleRate'] as int?;
    final bitDepth = audio['BitDepth'] as int?;
    final isLossless = codec == 'flac' || codec == 'alac' || codec == 'wav';
    return TrackQuality(
      sourceCodec: codec,
      bitrateKbps: !isLossless && bitrate != null ? bitrate ~/ 1000 : null,
      bitDepth: isLossless ? bitDepth : null,
      sampleRateKhz: isLossless && sampleRate != null
          ? sampleRate ~/ 1000
          : null,
    );
  }

  String albumArtistName(Map<String, dynamic> m) {
    final artists = m['AlbumArtists'] as List?;
    if (artists != null && artists.isNotEmpty) {
      final mapArtists = artists.whereType<Map<String, dynamic>>().toList();
      if (mapArtists.isNotEmpty) {
        final fm = mapArtists.first;
        final name = fm['Name'] as String?;
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return (m['AlbumArtist'] as String?) ??
        (m['Artists'] as List?)?.cast<String>().join(', ') ??
        '';
  }

  String? albumArtistId(Map<String, dynamic> m) {
    final artists = m['AlbumArtists'] as List?;
    if (artists != null && artists.isNotEmpty) {
      final mapArtists = artists.whereType<Map<String, dynamic>>().toList();
      if (mapArtists.isNotEmpty) {
        return mapArtists.first['Id'] as String?;
      }
    }
    return null;
  }

  String trackArtistName(Map<String, dynamic> m) {
    final artists = m['ArtistItems'] as List?;
    if (artists != null && artists.isNotEmpty) {
      final names = artists
          .whereType<Map<String, dynamic>>()
          .map((a) => a['Name'] as String?)
          .whereType<String>()
          .where((s) => s.isNotEmpty);
      if (names.isNotEmpty) return names.join(', ');
    }
    final flat = (m['Artists'] as List?)?.cast<String>();
    if (flat != null && flat.isNotEmpty) return flat.join(', ');
    return (m['AlbumArtist'] as String?) ?? '';
  }
}
