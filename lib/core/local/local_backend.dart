import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/library.dart';
import '../lyrics/embedded_lyrics_parser.dart';
import 'local_db.dart';
import 'local_library.dart';
import 'saf_picker.dart';

/// On-device implementation of [MusicBackend] for local mode.
///
/// Browsing (albums / artists / tracks / genres / search) delegates to
/// [LocalLibrary] (which already knew how to read the SQLite cache).
/// Favorites and user playlists are owned by this backend via the
/// `favorites` / `playlists` / `playlist_entries` tables added in
/// schema v2.
///
/// Streaming: the rest of the player already knows that local track
/// ids ARE `content://` URIs that mpv can open directly, so the
/// "stream url" is the id itself. `playActions.playQueue` and the
/// track context menu both go through [trackStreamUrl] now, so wiring
/// the LocalBackend through `musicBackendProvider` is what lets the
/// existing UI flip from "server only" to "works in either mode".
class LocalBackend implements MusicBackend {
  LocalBackend({required this.library, required this.db});
  final LocalLibrary library;
  final LocalDb db;
  static const _uuid = Uuid();

  // ── Identification ────────────────────────────────────────────────

  @override
  ServerType get serverType => ServerType.local;

  @override
  Map<String, String> get authHeaders => const <String, String>{};

  // ── Streaming ─────────────────────────────────────────────────────

  @override
  String trackStreamUrl(String trackId, {int? maxBitrateKbps}) => trackId;

  // ── Library browsing ──────────────────────────────────────────────
  //
  // The "recently added / recently played" rails on Home don't have a
  // real signal in local mode (no per-user play history) — we just
  // surface the catalogue ordered the way LocalLibrary already returns
  // it. Favorites are populated from the new local favorites table.

  @override
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) =>
      // Sort by MAX(tracks.last_modified) per album in SQL. There's no
      // `added_at` column on tracks (would need a schema bump), but file
      // mtime is a workable proxy and matches the "albums I downloaded
      // recently" intuition that the Home hero is selling.
      db.recentlyAddedAlbums(limit: limit);

  @override
  Future<List<AfTrack>> recentlyPlayed({int limit = 20}) async {
    final tracks = await library.tracks(limit: limit);
    return _hydrateFavorites(tracks);
  }

  @override
  Future<List<AfTrack>> resumeItems({int limit = 20}) async => const [];

  @override
  Future<List<AfArtist>> artists({int limit = 200}) =>
      db.allArtists(limit: limit);

  @override
  Future<List<AfPlaylist>> playlists({int limit = 200}) =>
      // One SQL with LEFT JOIN to compute track count + duration per
      // playlist, instead of allPlaylists() + N+1 playlistStats().
      db.allPlaylistsWithStats(limit: limit);

  @override
  Future<List<AfAlbum>> allAlbums({int limit = 500, int startIndex = 0}) =>
      // Paginate at the SQL layer instead of returning every album
      // and slicing in Dart.
      db.allAlbums(limit: limit, offset: startIndex);

  @override
  Future<List<AfTrack>> allTracks({
    int limit = 1000,
    int startIndex = 0,
  }) async {
    // SQL OFFSET; the previous (limit + startIndex) + sublist pattern
    // grew the loaded row count with the scroll position.
    final slice = await db.allTracks(limit: limit, offset: startIndex);
    return _hydrateFavorites(slice);
  }

  @override
  Future<List<AfGenre>> genres({int limit = 200}) =>
      db.allGenres(limit: limit);

  @override
  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) =>
      // One SQL with an `IN (SELECT item_id FROM favorites)` subquery
      // — only the favorited albums are aggregated, instead of
      // GROUP BYing every album in the library and then keeping the
      // 30 that match.
      db.favoriteAlbums(limit: limit);

  @override
  Future<List<AfTrack>> favoriteTracks({int limit = 500}) =>
      db.favoriteTracks(limit: limit);

  // ── Detail views ──────────────────────────────────────────────────
  //
  // Album / artist IDs encode their natural keys (`local:album:NAME:ARTIST`,
  // `local:artist:NAME`) so the detail screens don't need a separate
  // join table for "what's in this album".

  @override
  Future<({AfAlbum album, List<AfTrack> tracks})?> album(String id) async {
    final parsed = _parseAlbumId(id);
    if (parsed == null) return null;
    // Look the album up directly instead of GROUP BYing every album in
    // the library to find one row. Tracks are loaded in parallel; one
    // favoriteIds() query is shared between the album row's
    // isFavorite flag and the per-track hydration below.
    final albumMeta = await db.albumByKey(parsed.name, parsed.artist);
    final tracks = await library.tracksByAlbum(parsed.name, parsed.artist);
    final favIds = await db.favoriteIds();
    if (tracks.isEmpty) return null;
    final album =
        albumMeta ??
        AfAlbum(
          id: id,
          name: parsed.name,
          artistName: parsed.artist,
          trackCount: tracks.length,
          totalDuration: tracks.fold<Duration>(
            Duration.zero,
            (acc, t) => acc + t.duration,
          ),
        );
    final hydrated = favIds.isEmpty
        ? tracks
        : tracks
              .map(
                (t) => favIds.contains(t.id) ? t.copyWith(isFavorite: true) : t,
              )
              .toList();
    return (
      album: album.copyWith(isFavorite: favIds.contains(id)),
      tracks: hydrated,
    );
  }

  @override
  Future<AfArtist?> artist(String id) async {
    final name = _parseArtistId(id);
    if (name == null) return null;
    // Single-row aggregation instead of GROUP BYing every artist in
    // the library to find one row.
    return db.artistByName(name);
  }

  @override
  Future<AfTrackDetails?> trackDetails(String id) => db.trackDetailsById(id);

  @override
  Future<List<AfAlbum>> artistAlbums(String artistId, {int limit = 100}) async {
    final name = _parseArtistId(artistId);
    if (name == null) return const [];
    // Push the artist filter down to SQL instead of GROUP BYing every
    // album in the library and filtering in Dart.
    return db.albumsByArtist(name, limit: limit);
  }

  @override
  Future<List<AfTrack>> artistTopTracks(
    String artistId, {
    int limit = 5,
  }) async {
    final name = _parseArtistId(artistId);
    if (name == null) return const [];
    final tracks = await library.tracksByArtist(name);
    return _hydrateFavorites(tracks.take(limit).toList());
  }

  @override
  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200}) =>
      // Genre is per-track in local mode; the SQL aggregation in
      // [LocalDb.albumsByGenre] groups by the same (album, album-artist
      // ?? artist) key as [LocalDb.allAlbums] so trackCount / totalDuration
      // / cover-art match what the rest of the app expects.
      db.albumsByGenre(genre, limit: limit);

  @override
  Future<({AfPlaylist playlist, List<AfTrack> tracks})?> playlist(
    String id,
  ) async {
    final p = await db.getPlaylist(id);
    if (p == null) return null;
    final entries = await db.playlistTracks(id);
    final tracks = entries.map((e) => e.track).toList();
    return (
      playlist: AfPlaylist(
        id: p.id,
        name: p.name,
        trackCount: tracks.length,
        duration: tracks.fold<Duration>(
          Duration.zero,
          (acc, t) => acc + t.duration,
        ),
      ),
      tracks: tracks,
    );
  }

  // ── Search ────────────────────────────────────────────────────────

  @override
  Future<
    ({
      List<AfTrack> tracks,
      List<AfAlbum> albums,
      List<AfArtist> artists,
      List<AfPlaylist> playlists,
    })
  >
  search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return (
        tracks: <AfTrack>[],
        albums: <AfAlbum>[],
        artists: <AfArtist>[],
        playlists: <AfPlaylist>[],
      );
    }
    // Push the filter down to SQL for each result type so we don't
    // load the entire local library on every keystroke. tracks already
    // do this via library.search() / searchTracks(). The album / artist
    // / playlist branches used to pull `allAlbums()`, `allArtists()`,
    // and `allPlaylists()` + N+1 `playlistStats()` for every search.
    final tracks = await library.search(q);
    final hydratedTracks = await _hydrateFavorites(tracks);
    final albums = await db.searchAlbums(q);
    final artists = await db.searchArtists(q);
    final playlistMatches = await db.searchPlaylists(q);
    return (
      tracks: hydratedTracks,
      albums: albums,
      artists: artists,
      playlists: playlistMatches,
    );
  }

  // ── Favorites ─────────────────────────────────────────────────────

  @override
  Future<void> setFavorite(String itemId, bool isFavorite) =>
      db.setFavorite(itemId, isFavorite);

  // ── Playlists ─────────────────────────────────────────────────────

  @override
  Future<String?> createPlaylist(String name, List<String> trackIds) async {
    final id = 'local:playlist:${_uuid.v4()}';
    await db.createPlaylist(id, name);
    if (trackIds.isNotEmpty) {
      await db.addToPlaylist(id, trackIds, makeEntryId: () => _uuid.v4());
    }
    return id;
  }

  @override
  Future<void> addToPlaylist(String playlistId, List<String> trackIds) =>
      db.addToPlaylist(playlistId, trackIds, makeEntryId: () => _uuid.v4());

  @override
  Future<void> removeFromPlaylist(String playlistId, List<String> entryIds) =>
      db.removePlaylistEntries(playlistId, entryIds);

  @override
  Future<void> movePlaylistItem(
    String playlistId,
    String itemId,
    int newIndex,
  ) => db.movePlaylistEntry(playlistId, itemId, newIndex);

  @override
  Future<void> deletePlaylist(String playlistId) =>
      db.deletePlaylist(playlistId);

  @override
  Future<void> renamePlaylist(String playlistId, String newName) =>
      db.renamePlaylist(playlistId, newName);

  // ── Similar songs ─────────────────────────────────────────────────
  //
  // Without a server we can't compute a real "instant mix"; surface a
  // shuffled artist-radio so tapping the action still does something
  // useful.

  @override
  Future<List<AfTrack>> instantMix(String seedId, {int limit = 50}) async {
    final tracks = await db.getSimilarTracks(seedId, limit: limit);
    return _hydrateFavorites(tracks);
  }

  // ── Lyrics ────────────────────────────────────────────────────────
  //
  // Resolves lyrics for local playback:
  // 1. If using SAF (Android), delegates to SafPicker to search for a
  //    sidecar .lrc file or parse embedded tag lyrics.
  // 2. Otherwise (desktop/raw path), checks for a local sidecar .lrc
  //    file or extracts embedded tag lyrics using EmbeddedLyricsParser.

  @override
  Future<String?> lyrics(String trackId) async {
    if (trackId.startsWith('content://')) {
      return SafPicker.readLyrics(trackId);
    }

    try {
      // 1. Try sidecar .lrc next to file
      final file = File(trackId);
      if (await file.exists()) {
        final dir = file.parent.path;
        final baseName = p.basenameWithoutExtension(file.path);

        // Try lowercase .lrc
        final lrcFile = File(p.join(dir, '$baseName.lrc'));
        if (await lrcFile.exists()) {
          return await lrcFile.readAsString();
        }

        // Try uppercase .LRC
        final lrcFileUpper = File(p.join(dir, '$baseName.LRC'));
        if (await lrcFileUpper.exists()) {
          return await lrcFileUpper.readAsString();
        }

        // 2. Fallback to embedded lyrics
        return await EmbeddedLyricsParser.extractLyrics(trackId);
      }
    } on Exception catch (e, stack) {
      afLog(
        'local',
        'failed to read local lyrics for track $trackId',
        error: e,
        stackTrace: stack,
      );
    }
    return null;
  }

  /// Saves the sidecar lyrics back to the track's folder.
  Future<bool> saveSidecarLrc(String trackId, String content) async {
    if (trackId.startsWith('content://')) {
      return SafPicker.saveSidecarLrc(trackId, content);
    }

    try {
      final file = File(trackId);
      if (await file.exists()) {
        final dir = file.parent.path;
        final baseName = p.basenameWithoutExtension(file.path);
        final lrcFile = File(p.join(dir, '$baseName.lrc'));
        await lrcFile.writeAsString(content);
        return true;
      }
    } on Exception catch (e, stack) {
      afLog(
        'local',
        'failed to write local sidecar lrc',
        error: e,
        stackTrace: stack,
      );
    }
    return false;
  }

  // ── Playback reporting ────────────────────────────────────────────
  //
  // No server, no telemetry destination. The JellyfinPlaybackReporter
  // resolves through `musicBackendProvider` so making these no-ops is
  // enough to keep the reporter happy in local mode.

  @override
  Future<void> reportPlaybackStart(String trackId) async {}

  @override
  Future<void> reportProgress(
    String trackId,
    Duration position, {
    bool isPaused = false,
  }) async {}

  @override
  Future<void> reportPlaybackStop(
    String trackId,
    Duration position, {
    bool submission = true,
  }) async {}

  // ── Play queue sync ─────────────────────────────────────────────────

  @override
  Future<void> savePlayQueue(
    List<String> trackIds, {
    int? currentIndex,
    Duration? position,
  }) async {}

  @override
  Future<({List<AfTrack> tracks, int currentIndex, Duration position})?>
  getPlayQueue() async => null;

  // ── User views ────────────────────────────────────────────────────

  @override
  Future<List<LibraryView>> userViews() async => const [];

  @override
  Future<void> uploadUserAvatar(List<int> bytes, String mimeType) async {}

  @override
  Future<void> deleteUserAvatar() async {}

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  void clearCache() {}

  @override
  void close() {}

  // ── Helpers ───────────────────────────────────────────────────────

  Future<List<AfTrack>> _hydrateFavorites(List<AfTrack> tracks) async {
    if (tracks.isEmpty) return tracks;
    final favIds = await db.favoriteIdsCached();
    if (favIds.isEmpty) return tracks;
    return tracks
        .map((t) => favIds.contains(t.id) ? t.copyWith(isFavorite: true) : t)
        .toList();
  }

  /// `local:album:NAME:ARTIST` → (NAME, ARTIST). Returns null for any
  /// id that isn't a local album id. Splits on the LAST colon so album
  /// names containing colons ("Greatest Hits: The Best") parse correctly.
  ({String name, String artist})? _parseAlbumId(String id) {
    const prefix = 'local:album:';
    if (!id.startsWith(prefix)) return null;
    final rest = id.substring(prefix.length);
    final sep = rest.lastIndexOf(':');
    if (sep < 0) return null;
    return (name: rest.substring(0, sep), artist: rest.substring(sep + 1));
  }

  /// `local:artist:NAME` → NAME. Returns null for any id that isn't a
  /// local artist id.
  String? _parseArtistId(String id) {
    const prefix = 'local:artist:';
    if (!id.startsWith(prefix)) return null;
    return id.substring(prefix.length);
  }
}
