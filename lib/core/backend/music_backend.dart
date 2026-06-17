import '../jellyfin/models/items.dart';
import '../jellyfin/models/library.dart';

/// Identifies which server backend is connected.
///
/// `local` is a sentinel for the on-device LocalBackend — it has no
/// real "server" but it does implement [MusicBackend] so favorites and
/// playlists work the same as in server mode.
enum ServerType { jellyfin, subsonic, local, youtubeMusic }

/// Abstract music-server backend.
///
/// Both [JellyfinClient] and [SubsonicClient] implement this so the
/// provider / UI layer never needs to know which server type is behind
/// the connection. Every method signature mirrors the shapes already
/// consumed by `providers.dart`.
abstract class MusicBackend {
  /// Which server type this backend talks to.
  ServerType get serverType;

  // ── Library browsing ────────────────────────────────────────────────

  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20});
  Future<List<AfTrack>> recentlyPlayed({int limit = 20});
  Future<List<AfTrack>> resumeItems({int limit = 20});
  Future<List<AfArtist>> artists({int limit = 200});
  Future<List<AfPlaylist>> playlists({int limit = 200});
  Future<List<AfAlbum>> allAlbums({int limit = 500, int startIndex = 0});
  Future<List<AfTrack>> allTracks({int limit = 1000, int startIndex = 0});

  /// Returns the total number of tracks in the library without loading
  /// them into memory. Use this instead of [allTracks] when only the
  /// count is needed (e.g. profile stats, onboarding summary).
  Future<int> trackCount();

  Future<List<AfGenre>> genres({int limit = 200});
  Future<List<AfAlbum>> favoriteAlbums({int limit = 30});
  Future<List<AfTrack>> favoriteTracks({int limit = 500});

  // ── Detail views ────────────────────────────────────────────────────

  Future<({AfAlbum album, List<AfTrack> tracks})?> album(String id);
  Future<AfArtist?> artist(String id);

  /// Full per-track detail (container, file size, channels, codec,
  /// bitrate, sample rate, bit depth, path, genres, play count). Used
  /// by the "Show details" sheet — the basic [AfTrack] returned from
  /// list endpoints only carries display fields.
  Future<AfTrackDetails?> trackDetails(String id);

  Future<List<AfAlbum>> artistAlbums(String artistId, {int limit = 100});
  Future<List<AfTrack>> artistTopTracks(String artistId, {int limit = 5});
  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200});
  Future<({AfPlaylist playlist, List<AfTrack> tracks})?> playlist(String id);

  // ── Search ──────────────────────────────────────────────────────────

  Future<
    ({
      List<AfTrack> tracks,
      List<AfAlbum> albums,
      List<AfArtist> artists,
      List<AfPlaylist> playlists,
    })
  >
  search(String query);

  // ── Favorites ───────────────────────────────────────────────────────

  Future<void> setFavorite(String itemId, bool isFavorite);

  // ── Playlists ───────────────────────────────────────────────────────

  Future<void> addToPlaylist(String playlistId, List<String> trackIds);
  Future<String?> createPlaylist(String name, List<String> trackIds);
  Future<void> removeFromPlaylist(String playlistId, List<String> entryIds);
  Future<void> movePlaylistItem(String playlistId, String itemId, int newIndex);
  Future<void> deletePlaylist(String playlistId);
  Future<void> renamePlaylist(String playlistId, String newName);

  // ── Similar songs ───────────────────────────────────────────────────

  Future<List<AfTrack>> instantMix(String seedId, {int limit = 50});

  // ── Lyrics ──────────────────────────────────────────────────────────

  Future<String?> lyrics(String trackId);

  // ── Streaming ───────────────────────────────────────────────────────

  String trackStreamUrl(String trackId, {int? maxBitrateKbps});

  /// Headers callers can use for ad-hoc requests that bypass the main
  /// Dio instance (e.g. CachedNetworkImage for artwork). For Jellyfin
  /// this includes the Authorization header; for Subsonic auth is
  /// embedded in URLs, so this may be empty.
  Map<String, String> get authHeaders;

  // ── Playback reporting ──────────────────────────────────────────────

  Future<void> reportPlaybackStart(String trackId);
  Future<void> reportProgress(
    String trackId,
    Duration position, {
    bool isPaused = false,
  });
  Future<void> reportPlaybackStop(
    String trackId,
    Duration position, {
    bool submission = true,
  });

  // ── Play queue sync ─────────────────────────────────────────────────

  Future<void> savePlayQueue(
    List<String> trackIds, {
    int? currentIndex,
    Duration? position,
  });
  Future<({List<AfTrack> tracks, int currentIndex, Duration position})?>
  getPlayQueue();

  // ── User views (Jellyfin-specific; Subsonic returns a stub) ─────────

  Future<List<LibraryView>> userViews();

  // ── User avatar (Jellyfin-specific; others are local-only overrides) ──

  Future<void> uploadUserAvatar(List<int> bytes, String mimeType);
  Future<void> deleteUserAvatar();

  // ── Lifecycle ───────────────────────────────────────────────────────

  void clearCache();
  void close();
}
