import '../../../utils/time_format.dart';
import 'quality.dart';

/// A music album.
class AfAlbum {
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
    this.isFavorite = false,
  });
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
  final bool isFavorite;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AfAlbum && other.id == id;

  @override
  int get hashCode => id.hashCode;

  AfAlbum copyWith({
    String? id,
    String? name,
    String? artistName,
    String? artistId,
    int? trackCount,
    int? year,
    Duration? totalDuration,
    String? imageUrl,
    TrackQuality? quality,
    DateTime? dateAdded,
    bool? isFavorite,
  }) => AfAlbum(
    id: id ?? this.id,
    name: name ?? this.name,
    artistName: artistName ?? this.artistName,
    artistId: artistId ?? this.artistId,
    trackCount: trackCount ?? this.trackCount,
    year: year ?? this.year,
    totalDuration: totalDuration ?? this.totalDuration,
    imageUrl: imageUrl ?? this.imageUrl,
    quality: quality ?? this.quality,
    dateAdded: dateAdded ?? this.dateAdded,
    isFavorite: isFavorite ?? this.isFavorite,
  );

  String get metadataLine {
    final parts = <String>[];
    if (year != null) parts.add('$year');
    parts.add(trackCount == 1 ? '1 track' : '$trackCount tracks');
    final mins = totalDuration.inMinutes;
    if (mins > 0) parts.add('$mins min');
    if (quality != null) parts.add(quality!.chipLabel);
    return parts.join(' · ');
  }
}

/// A music artist.
class AfArtist {
  const AfArtist({
    required this.id,
    required this.name,
    this.albumCount = 0,
    this.trackCount = 0,
    this.imageUrl,
    this.bio,
  });
  final String id;
  final String name;
  final int albumCount;
  final int trackCount;
  final String? imageUrl;
  final String? bio;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AfArtist && other.id == id;

  @override
  int get hashCode => id.hashCode;

  String get statLine {
    final albums = albumCount == 1 ? '1 Album' : '$albumCount Albums';
    final tracks = trackCount == 1 ? '1 Track' : '$trackCount Tracks';
    return '$albums · $tracks';
  }
}

/// A single audio track.
class AfTrack {
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
    this.genre,
  });
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

  /// Genre tag from the track metadata. Populated for local mode tracks
  /// from the SQLite entity; server mode tracks may or may not carry it.
  final String? genre;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AfTrack && other.id == id;

  @override
  int get hashCode => id.hashCode;

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
    String? genre,
  }) => AfTrack(
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
    genre: genre ?? this.genre,
  );

  /// "Artist · Album · 3:42" — the standard subtitle for a track row.
  /// For tracks longer than an hour (live sets, mixes) [formatTrackDuration]
  /// kicks in and renders the duration as `hh:mm:ss` instead of running
  /// the minutes count off the edge of a row (e.g. `83:12` → `1:23:12`).
  String subtitle({bool withDuration = true}) {
    if (withDuration && duration > Duration.zero) {
      return '$artistName · $albumName · ${formatTrackDuration(duration)}';
    }
    return '$artistName · $albumName';
  }
}

/// A user-owned playlist.
class AfPlaylist {
  const AfPlaylist({
    required this.id,
    required this.name,
    this.trackCount = 0,
    this.duration = Duration.zero,
    this.imageUrl,
    this.mosaicImageUrls,
    this.isPublic = false,
  });
  final String id;
  final String name;
  final int trackCount;
  final Duration duration;
  final String? imageUrl;
  final List<String>?
  mosaicImageUrls; // up to 4 cover images for the 4-quadrant montage
  final bool isPublic;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AfPlaylist && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Singular/plural-aware subtitle ("1 track" / "12 tracks"). Used wherever
  /// playlists appear in lists so the labels stay grammatical for one-track
  /// playlists.
  String get trackCountLabel =>
      trackCount == 1 ? '1 track' : '$trackCount tracks';
}

/// A music genre — used for the Genres row on Home and Library.
class AfGenre {
  // representative album art for this genre
  const AfGenre(this.name, this.tint, {this.imageUrl});
  final String name;
  final String tint; // hex, used as fallback color
  final String? imageUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AfGenre && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// Full song-level metadata + file details — backs the "Show details"
/// context-menu sheet on track rows and the equivalent affordance on
/// the Now Playing screen.
///
/// Wraps an [AfTrack] (so existing UI primitives can still be reused)
/// and carries the extra fields the rest of the app doesn't need on
/// every list row: container, file size, channels, playcount, full
/// path, genres, etc.
class AfTrackDetails {
  const AfTrackDetails({
    required this.track,
    this.container,
    this.sizeBytes,
    this.channels,
    this.sampleRateHz,
    this.bitDepth,
    this.bitrateBps,
    this.path,
    this.genres = const [],
    this.playCount,
    this.lastPlayedAt,
    this.year,
    this.discNumber,
    this.albumArtist,
    this.composer,
    this.isTranscoded = false,
  });

  /// Basic track surface (title, artist, album, duration, quality,
  /// favorite, etc.) — already populated everywhere else.
  final AfTrack track;

  /// Source-file container format ("flac", "mp3", "m4a", …).
  /// Distinct from the audio codec (e.g. m4a container, AAC codec).
  final String? container;

  /// Original file size in bytes on the server / device.
  final int? sizeBytes;

  /// Audio channel count (1 = mono, 2 = stereo, 6 = 5.1, …).
  final int? channels;

  /// Sample rate in Hz — preserved with full precision (the
  /// `TrackQuality.sampleRateKhz` field is rounded to kHz for the
  /// chip label).
  final int? sampleRateHz;

  /// Bit depth in bits — preserved even for lossy formats where the
  /// quality chip omits it.
  final int? bitDepth;

  /// Encoded bitrate in bits-per-second (full precision; the chip
  /// only carries kbps).
  final int? bitrateBps;

  /// On-server / on-device absolute file path. Surfaced for sanity
  /// checking that the right file is being played; redacted in the
  /// future if remote-server admins object.
  final String? path;

  /// Genres tagged on the track.
  final List<String> genres;

  /// Number of times the user has played this track. Server-owned;
  /// Jellyfin populates `UserData.PlayCount`, Subsonic uses
  /// `playCount`.
  final int? playCount;

  /// Last played time. Server-owned.
  final DateTime? lastPlayedAt;

  /// Release year (e.g. 2024).
  final int? year;

  /// Disc number (ParentIndexNumber in Jellyfin, discNumber in Subsonic).
  final int? discNumber;

  /// Album artist (AlbumArtist in Jellyfin, albumArtist in Subsonic).
  final String? albumArtist;

  /// Composer (Jellyfin: People → Composer; Subsonic: composer).
  final String? composer;

  /// Whether the server transcodes the stream (Jellyfin: TranscodingUrl present).
  final bool isTranscoded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AfTrackDetails && other.track.id == track.id;

  @override
  int get hashCode => track.id.hashCode;

  /// `1.23 MB` / `512 KB` / `1.5 GB` formatting for [sizeBytes]. Uses
  /// 1024-based units (KiB/MiB) but renders the friendlier `MB` suffix
  /// for parity with Android's file pickers.
  String? get formattedSize {
    final s = sizeBytes;
    if (s == null || s <= 0) return null;
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (s >= gb) return '${(s / gb).toStringAsFixed(2)} GB';
    if (s >= mb) return '${(s / mb).toStringAsFixed(2)} MB';
    if (s >= kb) return '${(s / kb).toStringAsFixed(0)} KB';
    return '$s B';
  }

  /// "2" → "Stereo", "1" → "Mono", "6" → "5.1 Surround", otherwise the
  /// raw count with " channels" suffix.
  String? get formattedChannels {
    final c = channels;
    if (c == null) return null;
    return switch (c) {
      1 => 'Mono',
      2 => 'Stereo',
      6 => '5.1 Surround',
      8 => '7.1 Surround',
      _ => '$c channels',
    };
  }
}
