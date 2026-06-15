import 'package:drift/drift.dart';

import '../../utils/sql.dart';
import '../jellyfin/models/items.dart';
import 'app_database.dart';
import 'artist_repository.dart';
import 'genre_repository.dart';
import 'local_db_albums.dart';
import 'local_db_co_occurrences.dart';
import 'local_db_playlists.dart';
import 'local_db_lastfm.dart';
import 'local_db_track_stats.dart';
import 'local_db_tracks.dart';

/// Local database for caching scanned music metadata.
/// Refactored to wrap Drift's [AppDatabase].
class LocalDb {
  LocalDb({required this.db}) {
    tracks = TrackRepository(db);
    albums = AlbumRepository(db);
    playlists = PlaylistRepository(db, tracks, favoriteIdsCached);
    trackStats = TrackStatsRepository(db);
    coOccurrences = CoOccurrenceRepository(db);
    lastfm = LastFmCacheRepository(db);
    _artistRepo = ArtistRepository(db);
    _genreRepo = GenreRepository(db);
  }
  final AppDatabase db;

  Set<String>? _favoriteIdsCache;

  late final TrackRepository tracks;
  late final AlbumRepository albums;
  late final PlaylistRepository playlists;
  late final TrackStatsRepository trackStats;
  late final CoOccurrenceRepository coOccurrences;
  late final LastFmCacheRepository lastfm;
  late final ArtistRepository _artistRepo;
  late final GenreRepository _genreRepo;

  // ── Folders ─────────────────────────────────────────────────────────────

  Future<void> addFolder(String uri, String displayPath) async {
    await db
        .into(db.folders)
        .insert(
          FoldersCompanion.insert(
            uri: uri,
            displayPath: displayPath,
            addedAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.replace,
        );
  }

  Future<void> removeFolder(String uri) async {
    await db.transaction(() async {
      await (db.delete(db.folders)..where((f) => f.uri.equals(uri))).go();
      await db.customStatement(
        r"DELETE FROM tracks WHERE id LIKE ? ESCAPE '\'",
        ['${escapeSqlLike(uri)}%'],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getFolders() async {
    final folders = await (db.select(
      db.folders,
    )..orderBy([(t) => OrderingTerm.asc(t.addedAt)])).get();
    return folders
        .map(
          (f) => {
            'uri': f.uri,
            'display_path': f.displayPath,
            'added_at': f.addedAt,
          },
        )
        .toList();
  }

  // ── Tracks CRUD ─────────────────────────────────────────────────────────

  Future<void> upsertTrack(Map<String, dynamic> track) =>
      tracks.upsertTrack(track);

  Future<void> upsertTracks(List<Map<String, dynamic>> trackList) =>
      tracks.upsertTracks(trackList);

  Future<void> deleteTrack(String id) => tracks.deleteTrack(id);

  Future<List<String>> trackIdsByPrefix(String prefix) =>
      tracks.trackIdsByPrefix(prefix);

  Future<void> deleteAllTracks() => tracks.deleteAllTracks();

  Future<void> updateCoverPath(String trackId, String? coverPath) =>
      tracks.updateCoverPath(trackId, coverPath);

  Future<int> nullStaleCoverPaths() => tracks.nullStaleCoverPaths();

  Future<int> propagateAlbumArt() => tracks.propagateAlbumArt();

  Future<int?> getTrackLastModified(String id) =>
      tracks.getTrackLastModified(id);

  Future<Map<String, ({int? lastModified, bool hasCover})>>
  getTrackScanInfoByPrefix(String prefix) =>
      tracks.getTrackScanInfoByPrefix(prefix);

  Future<void> deleteTracksByIds(List<String> ids) =>
      tracks.deleteTracksByIds(ids);

  // ── Tracks Query ────────────────────────────────────────────────────────

  Future<List<AfTrack>> allTracks({int limit = 500, int offset = 0}) =>
      tracks.allTracks(limit: limit, offset: offset);

  Future<AfTrack?> trackById(String id) => tracks.trackById(id);

  Future<List<AfTrack>> tracksByIds(List<String> ids) =>
      tracks.tracksByIds(ids);

  Future<AfTrackDetails?> trackDetailsById(String id) =>
      tracks.trackDetailsById(id);

  Future<List<AfTrack>> tracksByAlbum(String albumName, String artistName) =>
      tracks.tracksByAlbum(albumName, artistName);

  Future<List<AfTrack>> tracksByArtist(String artistName, {int? limit}) =>
      tracks.tracksByArtist(artistName, limit: limit);

  Future<Map<String, List<AfTrack>>> tracksByArtists(Set<String> artistNames) =>
      tracks.tracksByArtists(artistNames);

  Future<List<AfTrack>> tracksByGenre(String genre) =>
      tracks.tracksByGenre(genre);

  Future<List<AfTrack>> getSimilarTracks(String seedId, {int limit = 50}) =>
      tracks.getSimilarTracks(seedId, limit: limit);

  Future<List<AfTrack>> searchTracks(String query) =>
      tracks.searchTracks(query);

  Future<int> trackCount() => tracks.trackCount();

  // ── Albums Query ────────────────────────────────────────────────────────

  Future<List<AfAlbum>> allAlbums({int? limit, int offset = 0}) =>
      albums.allAlbums(limit: limit, offset: offset);

  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) =>
      albums.recentlyAddedAlbums(limit: limit);

  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200}) =>
      albums.albumsByGenre(genre, limit: limit);

  Future<List<AfAlbum>> albumsByArtist(String artistName, {int limit = 200}) =>
      albums.albumsByArtist(artistName, limit: limit);

  Future<AfAlbum?> albumByKey(String name, String artistName) =>
      albums.albumByKey(name, artistName);

  Future<List<AfAlbum>> searchAlbums(String query, {int limit = 50}) =>
      albums.searchAlbums(query, limit: limit);

  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) =>
      albums.favoriteAlbums(limit: limit);

  // ── Artists ─────────────────────────────────────────────────────────────

  /// Backward-compatible delegate to [ArtistRepository].
  Future<List<AfArtist>> allArtists({int limit = 5000}) =>
      _artistRepo.allArtists(limit: limit);

  /// Backward-compatible delegate to [ArtistRepository].
  Future<AfArtist?> artistByName(String name) => _artistRepo.artistByName(name);

  /// Backward-compatible delegate to [ArtistRepository].
  Future<List<AfArtist>> searchArtists(String query, {int limit = 50}) =>
      _artistRepo.searchArtists(query, limit: limit);

  // ── Genres ──────────────────────────────────────────────────────────────

  /// Backward-compatible delegate to [GenreRepository].
  Future<List<AfGenre>> allGenres({int limit = 500}) =>
      _genreRepo.allGenres(limit: limit);

  // ── Favorites ─────────────────────────────────────────────────────────

  Future<bool> isFavorite(String itemId) async {
    final row = await (db.select(
      db.favorites,
    )..where((f) => f.itemId.equals(itemId))).getSingleOrNull();
    return row != null;
  }

  Future<Set<String>> favoriteIds() async {
    final rows = await db.select(db.favorites).get();
    return rows.map((r) => r.itemId).toSet();
  }

  /// Cached variant of [favoriteIds] — avoids repeated full-table scans.
  Future<Set<String>> favoriteIdsCached() async {
    return _favoriteIdsCache ??= await favoriteIds();
  }

  /// Must be called whenever the favorites table is mutated so the cache
  /// stays consistent.
  void invalidateFavoriteIdsCache() {
    _favoriteIdsCache = null;
  }

  Future<void> setFavorite(String itemId, bool isFavorite) async {
    if (isFavorite) {
      await db
          .into(db.favorites)
          .insert(
            FavoritesCompanion.insert(
              itemId: itemId,
              addedAt: DateTime.now().millisecondsSinceEpoch,
            ),
            mode: InsertMode.replace,
          );
    } else {
      await (db.delete(
        db.favorites,
      )..where((f) => f.itemId.equals(itemId))).go();
    }
    invalidateFavoriteIdsCache();
  }

  Future<List<AfTrack>> favoriteTracks({int limit = 500}) async {
    final favIds = await favoriteIdsCached();
    if (favIds.isEmpty) return const [];
    final rows =
        await (db.select(db.tracks)
              ..where((t) => t.id.isIn(favIds))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.title.collate(Collate.noCase),
                  mode: OrderingMode.asc,
                ),
              ])
              ..limit(limit))
            .get();
    return rows.map((r) => tracks.rowToTrack(r, isFavorite: true)).toList();
  }

  // ── Playback History & Lost Memories ───────────────────────────────────

  /// Fetches tracks played exactly N years ago on the same calendar day.
  Future<List<AfTrack>> getLostMemories({int limit = 50}) async {
    final now = DateTime.now();
    // Build integer timestamp bounds (epoch ms) for each memory date.
    // Using WHERE played_at >= start AND played_at < end lets SQLite use
    // the idx_playback_history_played_at index, unlike the old date() wrapper.
    final ranges = <({int start, int end})>[];
    for (var i = 1; i <= 5; i++) {
      final dayStart = DateTime(now.year - i, now.month, now.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      ranges.add((
        start: dayStart.millisecondsSinceEpoch,
        end: dayEnd.millisecondsSinceEpoch,
      ));
    }

    // Build: WHERE (played_at >= ?1 AND played_at < ?2) OR ...
    final conditions = ranges
        .map((r) => '(played_at >= ${r.start} AND played_at < ${r.end})')
        .join(' OR ');
    final query =
        '''
      SELECT track_id, title, artist, album, duration_ms, image_url, MAX(played_at) as last_played
      FROM playback_history
      WHERE $conditions
      GROUP BY track_id
      ORDER BY last_played DESC
      LIMIT ?
    ''';

    final variables = [Variable<int>(limit)];

    final rows = await db
        .customSelect(
          query,
          variables: variables,
          readsFrom: {db.playbackHistory},
        )
        .get();

    final result = <AfTrack>[];
    final favIds = await favoriteIdsCached();

    for (final r in rows) {
      final trackId = r.read<String>('track_id');
      final title = r.read<String?>('title') ?? 'Unknown';
      final artistName = r.read<String?>('artist') ?? 'Unknown';
      final albumName = r.read<String?>('album') ?? 'Unknown';
      final durationMs = r.read<int?>('duration_ms') ?? 0;
      final imageUrl = r.read<String?>('image_url');

      result.add(
        AfTrack(
          id: trackId,
          title: title,
          artistName: artistName,
          albumName: albumName,
          duration: Duration(milliseconds: durationMs),
          imageUrl: imageUrl,
          isFavorite: favIds.contains(trackId),
        ),
      );
    }
    return result;
  }

  /// Fetches track IDs that have been skipped within the specified [threshold].
  Future<List<String>> getRecentlySkippedTrackIds({
    Duration threshold = const Duration(days: 14),
  }) async {
    final cutoff = DateTime.now().subtract(threshold).millisecondsSinceEpoch;
    final rows = await db
        .customSelect(
          'SELECT DISTINCT track_id FROM playback_history WHERE skipped = 1 AND played_at >= ?',
          variables: [Variable<int>(cutoff)],
          readsFrom: {db.playbackHistory},
        )
        .get();
    return rows.map((r) => r.read<String>('track_id')).toList();
  }

  /// Delete playback history older than [keepDuration] (default 90 days).
  ///
  /// Called on startup to prevent unbounded table growth. Uses a single
  /// DELETE with a WHERE clause — efficient even on large tables thanks to
  /// the `idx_playback_history_played_at` index.
  Future<int> pruneOldPlaybackHistory({
    Duration keepDuration = const Duration(days: 90),
  }) async {
    final cutoff = DateTime.now().subtract(keepDuration).millisecondsSinceEpoch;
    final deleted = await db
        .customStatement('DELETE FROM playback_history WHERE played_at < ?', [
          Variable<int>(cutoff),
        ])
        .then((_) => 0); // customStatement returns void
    // Count deleted rows via changes() is not exposed by Drift — return 0
    // to indicate completion. Callers don't need the count.
    return deleted;
  }

  // ── Playlist queries (delegated) ────────────────────────────────────────

  Future<List<PlaylistEntity>> allPlaylists() => playlists.allPlaylists();

  Future<PlaylistEntity?> getPlaylist(String id) => playlists.getPlaylist(id);

  Future<void> createPlaylist(String id, String name) =>
      playlists.createPlaylist(id, name);

  Future<void> renamePlaylist(String id, String newName) =>
      playlists.renamePlaylist(id, newName);

  Future<void> deletePlaylist(String id) => playlists.deletePlaylist(id);

  Future<({int count, int durationMs})> playlistStats(String playlistId) =>
      playlists.playlistStats(playlistId);

  Future<List<({String entryId, AfTrack track})>> playlistTracks(
    String playlistId,
  ) => playlists.playlistTracks(playlistId);

  Future<void> addToPlaylist(
    String playlistId,
    List<String> trackIds, {
    required String Function() makeEntryId,
  }) => playlists.addToPlaylist(playlistId, trackIds, makeEntryId: makeEntryId);

  Future<void> removePlaylistEntries(
    String playlistId,
    List<String> entryIds,
  ) => playlists.removePlaylistEntries(playlistId, entryIds);

  Future<void> movePlaylistEntry(
    String playlistId,
    String entryId,
    int newIndex,
  ) => playlists.movePlaylistEntry(playlistId, entryId, newIndex);

  Future<List<AfPlaylist>> allPlaylistsWithStats({int limit = 200}) =>
      playlists.allPlaylistsWithStats(limit: limit);

  Future<List<AfPlaylist>> searchPlaylists(String query, {int limit = 50}) =>
      playlists.searchPlaylists(query, limit: limit);

  // ── Listening Statistics fallback from local history ────────────────────

  Future<List<({String artist, String title, int playCount, String? imageUrl})>>
  getTopTracksFromHistory({int limit = 10}) async {
    final rows = await db
        .customSelect(
          '''
      SELECT artist, title, COUNT(*) as play_count, MIN(image_url) as image_url
      FROM playback_history
      WHERE skipped = 0 AND title IS NOT NULL AND title != ''
      GROUP BY artist, title
      ORDER BY play_count DESC
      LIMIT ?
      ''',
          variables: [Variable<int>(limit)],
          readsFrom: {db.playbackHistory},
        )
        .get();
    return rows
        .map(
          (r) => (
            artist: r.read<String?>('artist') ?? 'Unknown Artist',
            title: r.read<String?>('title') ?? 'Unknown Track',
            playCount: r.read<int>('play_count'),
            imageUrl: r.read<String?>('image_url'),
          ),
        )
        .toList();
  }

  Future<List<({String artist, int playCount})>> getTopArtistsFromHistory({
    int limit = 10,
  }) async {
    final rows = await db
        .customSelect(
          '''
      SELECT artist, COUNT(*) as play_count
      FROM playback_history
      WHERE skipped = 0 AND artist IS NOT NULL AND artist != ''
      GROUP BY artist
      ORDER BY play_count DESC
      LIMIT ?
      ''',
          variables: [Variable<int>(limit)],
          readsFrom: {db.playbackHistory},
        )
        .get();
    return rows
        .map(
          (r) => (
            artist: r.read<String>('artist'),
            playCount: r.read<int>('play_count'),
          ),
        )
        .toList();
  }

  Future<List<({String artist, String album, int playCount, String? imageUrl})>>
  getTopAlbumsFromHistory({int limit = 10}) async {
    final rows = await db
        .customSelect(
          '''
      SELECT artist, album, COUNT(*) as play_count, MIN(image_url) as image_url
      FROM playback_history
      WHERE skipped = 0 AND album IS NOT NULL AND album != ''
      GROUP BY artist, album
      ORDER BY play_count DESC
      LIMIT ?
      ''',
          variables: [Variable<int>(limit)],
          readsFrom: {db.playbackHistory},
        )
        .get();
    return rows
        .map(
          (r) => (
            artist: r.read<String?>('artist') ?? 'Unknown Artist',
            album: r.read<String>('album'),
            playCount: r.read<int>('play_count'),
            imageUrl: r.read<String?>('image_url'),
          ),
        )
        .toList();
  }

  Future<AfTrack?> searchTrackByArtistAndTitle(
    String artist,
    String title,
  ) async {
    final rows = await db
        .customSelect(
          r'''
      SELECT id, title, artist, album, album_artist, track_number,
             duration_ms, year, genre, cover_path, codec, bitrate, sample_rate
      FROM tracks 
      WHERE artist = ?1 COLLATE NOCASE 
        AND title = ?2 COLLATE NOCASE 
      LIMIT 1
      ''',
          variables: [Variable<String>(artist), Variable<String>(title)],
          readsFrom: {db.tracks},
        )
        .get();
    if (rows.isEmpty) return null;
    return tracks.rawRowToTrack(rows.first);
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> close() async {
    await db.close();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  AfTrack rowToTrack(TrackEntity r, {bool isFavorite = false}) =>
      tracks.rowToTrack(r, isFavorite: isFavorite);
}
