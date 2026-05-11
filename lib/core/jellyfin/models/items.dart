import 'quality.dart';

/// A music album.
class AfAlbum {
  final String id;
  final String name;
  final String artistName;
  final String? artistId;
  final int trackCount;
  final int? year;
  final Duration totalDuration;
  final String? imageUrl;
  final TrackQuality? quality;
  final DateTime? dateAdded;

  const AfAlbum({
    required this.id,
    required this.name,
    required this.artistName,
    required this.trackCount,
    this.artistId,
    this.year,
    this.totalDuration = Duration.zero,
    this.imageUrl,
    this.quality,
    this.dateAdded,
  });

  String get metadataLine {
    final parts = <String>[];
    if (year != null) parts.add('$year');
    parts.add('$trackCount tracks');
    final mins = totalDuration.inMinutes;
    if (mins > 0) parts.add('$mins min');
    if (quality != null) parts.add(quality!.chipLabel);
    return parts.join(' · ');
  }
}

/// A music artist.
class AfArtist {
  final String id;
  final String name;
  final int albumCount;
  final int trackCount;
  final String? imageUrl;
  final String? bio;

  const AfArtist({
    required this.id,
    required this.name,
    this.albumCount = 0,
    this.trackCount = 0,
    this.imageUrl,
    this.bio,
  });

  String get statLine {
    final albums = albumCount == 1 ? '1 Album' : '$albumCount Albums';
    final tracks = trackCount == 1 ? '1 Track' : '$trackCount Tracks';
    return '$albums · $tracks';
  }
}

/// A single audio track.
class AfTrack {
  final String id;
  final String title;
  final String artistName;
  final String albumName;
  final String? albumId;
  final String? artistId;
  final int? trackNumber;
  final Duration duration;
  final TrackQuality? quality;
  final String? imageUrl;
  final bool isFavorite;
  final bool isDownloaded;
  final DateTime? dateAdded;
  /// Per-bar waveform peaks for the visualiser. Currently populated only
  /// by [DemoLibrary] tracks — Jellyfin does not expose audio peak data
  /// in its API. For Jellyfin tracks this is always `null` and the Now
  /// Playing screen falls back to [DemoLibrary.peaksFor] (deterministic
  /// per track ID) so the visualiser still has a shape to draw. Kept on
  /// the model so an offline demo experience renders the *real* peak
  /// pattern instead of going through the fallback path.
  final List<int>? peaks;

  const AfTrack({
    required this.id,
    required this.title,
    required this.artistName,
    required this.albumName,
    this.albumId,
    this.artistId,
    this.trackNumber,
    this.duration = Duration.zero,
    this.quality,
    this.imageUrl,
    this.isFavorite = false,
    this.isDownloaded = false,
    this.dateAdded,
    this.peaks,
  });

  AfTrack copyWith({
    String? id,
    String? title,
    String? artistName,
    String? albumName,
    String? albumId,
    String? artistId,
    int? trackNumber,
    Duration? duration,
    TrackQuality? quality,
    String? imageUrl,
    bool? isFavorite,
    bool? isDownloaded,
    DateTime? dateAdded,
    List<int>? peaks,
  }) =>
      AfTrack(
        id: id ?? this.id,
        title: title ?? this.title,
        artistName: artistName ?? this.artistName,
        albumName: albumName ?? this.albumName,
        albumId: albumId ?? this.albumId,
        artistId: artistId ?? this.artistId,
        trackNumber: trackNumber ?? this.trackNumber,
        duration: duration ?? this.duration,
        quality: quality ?? this.quality,
        imageUrl: imageUrl ?? this.imageUrl,
        isFavorite: isFavorite ?? this.isFavorite,
        isDownloaded: isDownloaded ?? this.isDownloaded,
        dateAdded: dateAdded ?? this.dateAdded,
        peaks: peaks ?? this.peaks,
      );

  /// "Artist · Album · 3:42" — the standard subtitle for a track row.
  String subtitle({bool withDuration = true}) {
    final mm = duration.inMinutes;
    final ss = (duration.inSeconds % 60).toString().padLeft(2, '0');
    if (withDuration && duration > Duration.zero) {
      return '$artistName · $albumName · $mm:$ss';
    }
    return '$artistName · $albumName';
  }
}

/// A user-owned playlist.
class AfPlaylist {
  final String id;
  final String name;
  final int trackCount;
  final Duration duration;
  final String? imageUrl;
  final List<String>? mosaicImageUrls; // up to 4 cover images for the 4-quadrant montage
  final bool isPublic;

  const AfPlaylist({
    required this.id,
    required this.name,
    this.trackCount = 0,
    this.duration = Duration.zero,
    this.imageUrl,
    this.mosaicImageUrls,
    this.isPublic = false,
  });
}

/// A music genre — used for the Genres row on Home.
class AfGenre {
  final String name;
  final String tint; // hex, used for the color block
  const AfGenre(this.name, this.tint);
}
