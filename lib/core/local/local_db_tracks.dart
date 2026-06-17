import 'dart:io';

import 'package:drift/drift.dart';

import '../../utils/log.dart';
import '../../utils/sql.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/quality.dart';
import 'app_database.dart';

class TrackRepository {
  TrackRepository(this.db);
  final AppDatabase db;

  // ── CRUD ────────────────────────────────────────────────────────────────

  Future<void> upsertTrack(Map<String, dynamic> track) async {
    await db
        .into(db.tracks)
        .insert(_trackMapToCompanion(track), mode: InsertMode.replace);
  }

  Future<void> upsertTracks(List<Map<String, dynamic>> tracks) async {
    await db.batch((batch) {
      batch.insertAll(
        db.tracks,
        tracks.map(_trackMapToCompanion),
        mode: InsertMode.replace,
      );
    });
  }

  TracksCompanion _trackMapToCompanion(Map<String, dynamic> track) {
    return TracksCompanion.insert(
      id: track['id'] as String,
      title: track['title'] as String,
      artist: Value((track['artist'] as String?) ?? ''),
      album: Value((track['album'] as String?) ?? ''),
      albumArtist: Value((track['album_artist'] as String?) ?? ''),
      trackNumber: Value(track['track_number'] as int?),
      durationMs: Value((track['duration_ms'] as int?) ?? 0),
      year: Value(track['year'] as int?),
      genre: Value((track['genre'] as String?) ?? ''),
      filePath: track['file_path'] as String,
      fileSize: Value(track['file_size'] as int?),
      lastModified: Value(track['last_modified'] as int?),
      coverPath: Value(track['cover_path'] as String?),
      codec: Value((track['codec'] as String?) ?? ''),
      bitrate: Value(track['bitrate'] as int?),
      sampleRate: Value(track['sample_rate'] as int?),
      spectralHue: Value(track['spectral_hue'] as double?),
    );
  }

  Future<void> deleteTrack(String id) async {
    await (db.delete(db.tracks)..where((t) => t.id.equals(id))).go();
  }

  Future<List<String>> trackIdsByPrefix(String prefix) async {
    final rows = await db
        .customSelect(
          'SELECT id FROM tracks WHERE id LIKE ?1 ESCAPE \'\\\'',
          variables: [Variable<String>('${escapeSqlLike(prefix)}%')],
          readsFrom: {db.tracks},
        )
        .get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  Future<void> deleteAllTracks() async {
    await db.delete(db.tracks).go();
  }

  /// Update only the cover_path column for a single track without touching
  /// other columns. Used by the scanner to write a recovered cover path
  /// without corrupting the rest of the row.
  Future<void> updateCoverPath(String trackId, String? coverPath) async {
    await (db.update(db.tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion(coverPath: Value(coverPath)),
    );
  }

  /// Update only the spectral_hue column for a single track.
  /// Used to store pre-computed palette hue for instant lookup during playback.
  Future<void> updateSpectralHue(String trackId, double? hue) async {
    await (db.update(db.tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion(spectralHue: Value(hue)),
    );
  }

  /// Null out `cover_path` for tracks whose cover file no longer exists on
  /// disk. Called after cache eviction to prevent library views from trying
  /// to load deleted files. The next scan will re-extract cover art for
  /// these tracks.
  ///
  /// Processes in batches of 500 to avoid loading all tracks into memory.
  /// Batches updates to avoid N individual UPDATE statements.
  Future<int> nullStaleCoverPaths() async {
    const batchSize = 500;
    var totalNulled = 0;

    while (true) {
      final rows =
          await (db.select(db.tracks)
                ..where((t) => t.coverPath.isNotNull())
                ..limit(batchSize))
              .get();

      if (rows.isEmpty) break;

      final staleIds = <String>[];
      for (final row in rows) {
        final coverPath = row.coverPath;
        if (coverPath != null && !await File(coverPath).exists()) {
          staleIds.add(row.id);
        }
      }

      if (staleIds.isNotEmpty) {
        await (db.update(db.tracks)..where((t) => t.id.isIn(staleIds))).write(
          const TracksCompanion(coverPath: Value(null)),
        );
        totalNulled += staleIds.length;
      }
    }

    if (totalNulled > 0) {
      afLog('local', 'nulled $totalNulled stale cover_path entries');
    }
    return totalNulled;
  }

  /// Propagate cover art from tracks that have art to all tracks in the
  /// same album. For each album, if at least one track has cover art,
  /// copy that cover_path to all tracks without art.
  ///
  /// This ensures consistent album art across all tracks in an album,
  /// even if only one track has embedded cover art.
  Future<int> propagateAlbumArt() async {
    // Get all albums with their tracks' cover_path status
    final albumRows = await db
        .customSelect(
          '''
      SELECT album, artist, album_artist,
             COUNT(*) as total_tracks,
             SUM(CASE WHEN cover_path IS NOT NULL THEN 1 ELSE 0 END) as tracks_with_art
      FROM tracks
      WHERE album != ''
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      HAVING tracks_with_art > 0 AND tracks_with_art < total_tracks
      ''',
          readsFrom: {db.tracks},
        )
        .get();

    int propagated = 0;

    for (final albumRow in albumRows) {
      final albumName = albumRow.read<String>('album');
      final artistName =
          albumRow.read<String?>('album_artist')?.isNotEmpty == true
          ? albumRow.read<String>('album_artist')
          : albumRow.read<String>('artist');

      // Find the first track in this album that has cover art
      final coverTrack = await db
          .customSelect(
            '''
        SELECT cover_path FROM tracks
        WHERE album = ?1
          AND COALESCE(NULLIF(album_artist, ''), artist) = ?2
          AND cover_path IS NOT NULL
        LIMIT 1
        ''',
            variables: [
              Variable<String>(albumName),
              Variable<String>(artistName),
            ],
            readsFrom: {db.tracks},
          )
          .getSingleOrNull();

      if (coverTrack == null) continue;

      final coverPath = coverTrack.read<String>('cover_path');

      // Update all tracks in this album that don't have cover art
      await db.customStatement(
        '''
        UPDATE tracks
        SET cover_path = ?1
        WHERE album = ?2
          AND COALESCE(NULLIF(album_artist, ''), artist) = ?3
          AND cover_path IS NULL
        ''',
        [coverPath, albumName, artistName],
      );

      // Track that this album was processed (exact count not available from customStatement)
      propagated++;
      afLog('local', 'propagated cover art in album: $albumName');
    }

    if (propagated > 0) {
      afLog('local', 'propagated cover art across $propagated albums');
    }
    return propagated;
  }

  Future<int?> getTrackLastModified(String id) async {
    final query = db.select(db.tracks)..where((t) => t.id.equals(id));
    final result = await query.getSingleOrNull();
    return result?.lastModified;
  }

  /// Batch-load last_modified and cover_path for all tracks whose id starts
  /// with [prefix]. Returns a map of id → (lastModified, hasCoverArt).
  /// Replaces N per-file queries with a single SELECT when scanning a folder.
  Future<Map<String, ({int? lastModified, bool hasCover})>>
  getTrackScanInfoByPrefix(String prefix) async {
    final rows = await db
        .customSelect(
          'SELECT id, last_modified, cover_path FROM tracks WHERE id LIKE ?1 ESCAPE \'\\\'',
          variables: [Variable<String>('${escapeSqlLike(prefix)}%')],
          readsFrom: {db.tracks},
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('id'): (
          lastModified: r.read<int?>('last_modified'),
          hasCover: r.read<String?>('cover_path') != null,
        ),
    };
  }

  /// Batch-delete tracks by ID list. Replaces N per-file deletes with a
  /// single `WHERE id IN (...)` statement during prune.
  Future<void> deleteTracksByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    await (db.delete(db.tracks)..where((t) => t.id.isIn(ids))).go();
  }

  // ── Query ───────────────────────────────────────────────────────────────

  Future<List<AfTrack>> allTracks({int limit = 100, int offset = 0}) async {
    final rows =
        await (db.select(db.tracks)
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.title.collate(Collate.noCase),
                  mode: OrderingMode.asc,
                ),
              ])
              ..limit(limit, offset: offset > 0 ? offset : null))
            .get();
    return rows.map(rowToTrack).toList();
  }

  Future<AfTrack?> trackById(String id) async {
    final row = await (db.select(
      db.tracks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return rowToTrack(row);
  }

  /// Batch-fetch tracks by ID list. Returns tracks in arbitrary order.
  /// Replaces N sequential [trackById] calls with a single WHERE IN query.
  Future<List<AfTrack>> tracksByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (db.select(
      db.tracks,
    )..where((t) => t.id.isIn(ids))).get();
    return rows.map(rowToTrack).toList();
  }

  Future<AfTrackDetails?> trackDetailsById(String id) async {
    final row = await (db.select(
      db.tracks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final track = rowToTrack(row);
    final codec = row.codec;
    return AfTrackDetails(
      track: track,
      container: codec.isNotEmpty ? codec : null,
      sizeBytes: row.fileSize,
      channels: null,
      sampleRateHz: row.sampleRate,
      bitDepth: null,
      bitrateBps: row.bitrate != null ? row.bitrate! * 1000 : null,
      path: row.filePath,
      genres: row.genre.isNotEmpty ? [row.genre] : const [],
      playCount: null,
      lastPlayedAt: null,
      year: row.year,
      albumArtist: row.albumArtist.isNotEmpty ? row.albumArtist : null,
    );
  }

  Future<List<AfTrack>> tracksByAlbum(
    String albumName,
    String artistName, {
    int? limit,
  }) async {
    final query = db.select(db.tracks)
      ..where(
        (t) =>
            t.album.equals(albumName) &
            (t.artist.equals(artistName) | t.albumArtist.equals(artistName)),
      )
      ..orderBy([
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title),
      ]);
    if (limit != null) {
      query.limit(limit);
    }
    final rows = await query.get();
    return rows.map(rowToTrack).toList();
  }

  Future<List<AfTrack>> tracksByArtist(String artistName, {int? limit}) async {
    final query = db.select(db.tracks)
      ..where(
        (t) => t.artist.equals(artistName) | t.albumArtist.equals(artistName),
      )
      ..orderBy([
        (t) => OrderingTerm.asc(t.album),
        (t) => OrderingTerm.asc(t.trackNumber),
      ]);
    if (limit != null) {
      query.limit(limit);
    }
    final rows = await query.get();
    return rows.map(rowToTrack).toList();
  }

  /// Batch-fetch tracks for multiple artist names in a single query.
  /// Returns a map of artistName → tracks for that artist.
  Future<Map<String, List<AfTrack>>> tracksByArtists(
    Set<String> artistNames,
  ) async {
    if (artistNames.isEmpty) return const {};
    final rows =
        await (db.select(db.tracks)..where(
              (t) =>
                  t.artist.isIn(artistNames) | t.albumArtist.isIn(artistNames),
            ))
            .get();
    final map = <String, List<AfTrack>>{};
    for (final row in rows) {
      final track = rowToTrack(row);
      // Index by both artist and albumArtist so lookups succeed either way.
      map.putIfAbsent(row.artist, () => []).add(track);
      if (row.albumArtist != row.artist &&
          artistNames.contains(row.albumArtist)) {
        map.putIfAbsent(row.albumArtist, () => []).add(track);
      }
    }
    return map;
  }

  Future<List<AfTrack>> tracksByGenre(String genre) async {
    final rows =
        await (db.select(db.tracks)
              ..where((t) => t.genre.equals(genre))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.title.collate(Collate.noCase),
                  mode: OrderingMode.asc,
                ),
              ]))
            .get();
    return rows.map(rowToTrack).toList();
  }

  Future<List<AfTrack>> getSimilarTracks(
    String seedId, {
    int limit = 50,
  }) async {
    // Use pre-computed track_co_occurrences instead of the O(N²) self-join
    // on playback_history. The co-occurrence table tracks how often two
    // tracks are played close together (within 1 hour), giving us the same
    // "listening proximity" signal at O(1) lookup cost.
    final rows = await db
        .customSelect(
          r'''
      SELECT t.id, t.title, t.artist, t.album, t.album_artist,
             t.track_number, t.duration_ms, t.year, t.genre,
             t.cover_path, t.codec, t.bitrate, t.sample_rate,
             co.count AS co_count
      FROM track_co_occurrences co
      JOIN tracks t ON t.id = co.track_b_id
      WHERE co.track_a_id = ?1
        AND t.id != ?1
      ORDER BY co.count DESC
      LIMIT ?2
      ''',
          variables: [Variable<String>(seedId), Variable<int>(limit)],
          readsFrom: {db.trackCoOccurrences, db.tracks},
        )
        .get();

    return rows.map(rawRowToTrack).toList();
  }

  Future<List<AfTrack>> searchTracks(String query) async {
    final like = '%${escapeSqlLike(query)}%';
    final rows = await db
        .customSelect(
          r'''
        SELECT id, title, artist, album, album_artist, track_number,
               duration_ms, year, genre, cover_path, codec, bitrate, sample_rate
        FROM tracks
        WHERE title  LIKE ?1 ESCAPE '\'
           OR artist LIKE ?1 ESCAPE '\'
           OR album  LIKE ?1 ESCAPE '\'
        ORDER BY title COLLATE NOCASE ASC
        LIMIT 50
      ''',
          variables: [Variable<String>(like)],
          readsFrom: {db.tracks},
        )
        .get();
    return rows.map(rawRowToTrack).toList();
  }

  Future<int> trackCount() async {
    final countExp = db.tracks.id.count();
    final query = db.selectOnly(db.tracks)..addColumns([countExp]);
    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Build an [AfTrack] from extracted field values.
  /// Shared by [rowToTrack] and [rawRowToTrack] to avoid logic duplication.
  AfTrack _buildAfTrack({
    required String id,
    required String title,
    required String artist,
    required String album,
    int? trackNumber,
    required int durationMs,
    String? genre,
    String? coverPath,
    String? codec,
    int? bitrate,
    int? sampleRate,
    bool isFavorite = false,
  }) {
    final isLossless = codec == 'flac' || codec == 'alac' || codec == 'wav';
    return AfTrack(
      id: id,
      title: title,
      artistName: artist,
      albumName: album,
      albumId: (album.isNotEmpty && artist.isNotEmpty)
          ? 'local:album:$album:$artist'
          : null,
      artistId: artist.isNotEmpty ? 'local:artist:$artist' : null,
      trackNumber: trackNumber,
      duration: Duration(milliseconds: durationMs),
      quality: TrackQuality(
        sourceCodec: codec ?? '',
        bitrateKbps: !isLossless ? bitrate : null,
        bitDepth: null,
        sampleRateKhz: sampleRate != null ? sampleRate ~/ 1000 : null,
      ),
      imageUrl: coverPath != null ? 'file://$coverPath' : null,
      isFavorite: isFavorite,
      genre: genre?.isNotEmpty == true ? genre : null,
    );
  }

  AfTrack rowToTrack(TrackEntity r, {bool isFavorite = false}) {
    return _buildAfTrack(
      id: r.id,
      title: r.title,
      artist: r.artist,
      album: r.album,
      trackNumber: r.trackNumber,
      durationMs: r.durationMs,
      genre: r.genre,
      coverPath: r.coverPath,
      codec: r.codec,
      bitrate: r.bitrate,
      sampleRate: r.sampleRate,
      isFavorite: isFavorite,
    );
  }

  /// Convert a raw [QueryRow] (from customSelect) directly to [AfTrack],
  /// bypassing [TrackEntity]. Allows column projection in raw SQL queries
  /// instead of SELECT *.
  AfTrack rawRowToTrack(QueryRow r, {bool isFavorite = false}) {
    return _buildAfTrack(
      id: r.read<String>('id'),
      title: r.read<String>('title'),
      artist: r.read<String>('artist'),
      album: r.read<String>('album'),
      trackNumber: r.read<int?>('track_number'),
      durationMs: r.read<int>('duration_ms'),
      genre: r.read<String>('genre'),
      coverPath: r.read<String?>('cover_path'),
      codec: r.read<String>('codec'),
      bitrate: r.read<int?>('bitrate'),
      sampleRate: r.read<int?>('sample_rate'),
      isFavorite: isFavorite,
    );
  }
}
