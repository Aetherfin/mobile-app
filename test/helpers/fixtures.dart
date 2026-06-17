import 'package:aetherfin/core/jellyfin/models/items.dart';

/// Creates an [AfTrack] with sensible defaults. Override any field as needed.
AfTrack createTestTrack({
  String? id,
  String? title,
  String? artistName,
  String? albumName,
  Duration? duration,
  bool isFavorite = false,
}) {
  return AfTrack(
    id: id ?? 'track-1',
    title: title ?? 'Test Track',
    artistName: artistName ?? 'Test Artist',
    albumName: albumName ?? 'Test Album',
    duration: duration ?? const Duration(minutes: 3),
    isFavorite: isFavorite,
  );
}

/// Creates an [AfAlbum] with sensible defaults.
AfAlbum createTestAlbum({
  String? id,
  String? name,
  String? artistName,
  int trackCount = 10,
  bool isFavorite = false,
}) {
  return AfAlbum(
    id: id ?? 'album-1',
    name: name ?? 'Test Album',
    artistName: artistName ?? 'Test Artist',
    trackCount: trackCount,
    totalDuration: Duration(minutes: trackCount * 4),
    isFavorite: isFavorite,
  );
}

/// Creates an [AfArtist] with sensible defaults.
AfArtist createTestArtist({
  String? id,
  String? name,
  int albumCount = 3,
  int trackCount = 30,
}) {
  return AfArtist(
    id: id ?? 'artist-1',
    name: name ?? 'Test Artist',
    albumCount: albumCount,
    trackCount: trackCount,
  );
}

/// Creates an [AfPlaylist] with sensible defaults.
AfPlaylist createTestPlaylist({String? id, String? name, int trackCount = 5}) {
  return AfPlaylist(
    id: id ?? 'playlist-1',
    name: name ?? 'Test Playlist',
    trackCount: trackCount,
  );
}

/// Creates a list of test tracks with sequential IDs.
List<AfTrack> createTestTrackList({int count = 3}) {
  return List.generate(
    count,
    (i) => createTestTrack(
      id: 'track-${i + 1}',
      title: 'Track ${i + 1}',
      artistName: 'Artist ${i + 1}',
    ),
  );
}

/// Creates a list of test albums with sequential IDs.
List<AfAlbum> createTestAlbumList({int count = 3}) {
  return List.generate(
    count,
    (i) => createTestAlbum(
      id: 'album-${i + 1}',
      name: 'Album ${i + 1}',
      artistName: 'Artist ${i + 1}',
    ),
  );
}
