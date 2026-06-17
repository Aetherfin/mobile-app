import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('TrackEntity')
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant(''))();
  TextColumn get album => text().withDefault(const Constant(''))();
  TextColumn get albumArtist => text().withDefault(const Constant(''))();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get year => integer().nullable()();
  TextColumn get genre => text().withDefault(const Constant(''))();
  TextColumn get filePath => text()();
  IntColumn get fileSize => integer().nullable()();
  IntColumn get lastModified => integer().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get codec => text().withDefault(const Constant(''))();
  IntColumn get bitrate => integer().nullable()();
  IntColumn get sampleRate => integer().nullable()();
  RealColumn get spectralHue => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FolderEntity')
class Folders extends Table {
  TextColumn get uri => text()();
  TextColumn get displayPath => text()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {uri};
}

@DataClassName('SmartPlaylistEntity')
class SmartPlaylists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get combinator => text().withDefault(const Constant('all'))();
  TextColumn get rulesJson => text().withDefault(const Constant('[]'))();
  TextColumn get sort => text().withDefault(const Constant('title'))();
  TextColumn get sortOrder => text().withDefault(const Constant('asc'))();
  IntColumn get maxLimit => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local-mode favorites — covers tracks, albums and playlists. The
/// `itemId` is whatever the rest of the app uses to address the item
/// (track → `content://` URI, album → `local:album:NAME:ARTIST`,
/// playlist → `local:playlist:UUID`). Persists across launches so
/// hearts stay filled in without a server round-trip.
@DataClassName('FavoriteEntity')
class Favorites extends Table {
  TextColumn get itemId => text()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {itemId};
}

/// Local-mode user playlists. The `id` is generated on creation and
/// follows the `local:playlist:<uuid>` convention so the rest of the
/// app can tell it apart from server-issued playlist IDs.
@DataClassName('PlaylistEntity')
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ordered tracks inside a local playlist. The `entryId` is a stable
/// per-row UUID so the same track can appear multiple times in one
/// playlist (server backends use a similar entry-id pattern for the
/// same reason). `position` is the user-visible order; we re-pack it
/// on every move/remove so it always stays a dense 0..N sequence.
@DataClassName('PlaylistEntryEntity')
class PlaylistEntries extends Table {
  TextColumn get entryId => text()();
  TextColumn get playlistId => text()();
  TextColumn get trackId => text()();
  IntColumn get position => integer()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {entryId};
}

@DataClassName('CacheEntryEntity')
class CacheEntries extends Table {
  TextColumn get trackId => text()();
  IntColumn get fileSize => integer()();
  IntColumn get lastPlayedAt => integer()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// Snapshot of a played queue — persisted so the user can restore
/// previous play sessions. Added in schema v4.
///
/// Stores only track IDs and source metadata (not full track objects).
/// Tracks are re-fetched from the active backend when restoring.
@DataClassName('QueueHistoryEntity')
class QueueHistory extends Table {
  TextColumn get id => text()(); // uuid v4
  TextColumn get trackIdsJson => text()(); // JSON array of track IDs
  TextColumn get sourceLabel => text()(); // "Album: In Rainbows"
  TextColumn get sourceType =>
      text()(); // "album", "playlist", "artist", "manual"
  TextColumn get sourceId => text().nullable()(); // nullable server/DB ID
  IntColumn get createdAt => integer()(); // epoch ms

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TrackStatsEntity')
class TrackStats extends Table {
  TextColumn get trackId => text()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get skipCount => integer().withDefault(const Constant(0))();
  RealColumn get avgCompletion => real().withDefault(const Constant(0.0))();
  IntColumn get lastPlayed => integer().nullable()(); // epoch ms

  @override
  Set<Column> get primaryKey => {trackId};
}

@DataClassName('TrackCoOccurrenceEntity')
class TrackCoOccurrences extends Table {
  TextColumn get trackAId => text()();
  TextColumn get trackBId => text()();
  IntColumn get count => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {trackAId, trackBId};
}

@DataClassName('PlaybackHistoryEntity')
class PlaybackHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackId => text()();
  IntColumn get playedAt => integer()(); // Unix epoch milliseconds
  TextColumn get title => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get sourceType => text().nullable()();
  BoolColumn get skipped => boolean().withDefault(const Constant(false))();
  RealColumn get completionRate => real().withDefault(const Constant(0.0))();
}

@DataClassName('LastfmSimilarCacheEntity')
class LastfmSimilarCache extends Table {
  TextColumn get trackId => text()();
  TextColumn get similarTrackIds => text()(); // JSON array of track IDs
  IntColumn get cachedAt => integer()(); // epoch ms

  @override
  Set<Column> get primaryKey => {trackId};
}

@DriftDatabase(
  include: {'track_search.drift'},
  tables: [
    Tracks,
    Folders,
    SmartPlaylists,
    Favorites,
    Playlists,
    PlaylistEntries,
    CacheEntries,
    QueueHistory,
    PlaybackHistory,
    TrackStats,
    TrackCoOccurrences,
    LastfmSimilarCache,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test-only constructor that lets us inject an in-memory executor
  /// (`NativeDatabase.memory()`) without going through path_provider.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Create performance indexes for fresh installations too.
      final db = m.database;
      for (final stmt in const [
        'CREATE INDEX IF NOT EXISTS idx_playlist_entries_playlist_id '
            'ON playlist_entries (playlist_id)',
        'CREATE INDEX IF NOT EXISTS idx_playback_history_track_id '
            'ON playback_history (track_id)',
        'CREATE INDEX IF NOT EXISTS idx_tracks_artist '
            'ON tracks (artist)',
        'CREATE INDEX IF NOT EXISTS idx_tracks_album '
            'ON tracks (album)',
        'CREATE INDEX IF NOT EXISTS idx_tracks_genre '
            'ON tracks (genre)',
        'CREATE INDEX IF NOT EXISTS idx_tracks_last_modified '
            'ON tracks (last_modified)',
        'CREATE INDEX IF NOT EXISTS idx_playback_history_played_at '
            'ON playback_history (played_at)',
        'CREATE INDEX IF NOT EXISTS idx_track_co_occurrences_track_a '
            'ON track_co_occurrences (track_a_id)',
        'CREATE INDEX IF NOT EXISTS idx_tracks_artist_title '
            'ON tracks (artist, title)',
        'CREATE INDEX IF NOT EXISTS idx_tracks_album_artist '
            'ON tracks (album, album_artist)',
        'CREATE INDEX IF NOT EXISTS idx_track_stats_track_id '
            'ON track_stats (track_id)',
        'CREATE INDEX IF NOT EXISTS idx_lastfm_similar_cache_track_id '
            'ON lastfm_similar_cache (track_id)',
        'CREATE INDEX IF NOT EXISTS idx_queue_history_created_at '
            'ON queue_history (created_at)',
        'CREATE INDEX IF NOT EXISTS idx_playlist_entries_playlist_position '
            'ON playlist_entries (playlist_id, position)',
      ]) {
        try {
          await db.customStatement(stmt);
        } on Exception {
          // Table may not exist — skip index, no data loss.
        }
      }
      // FTS5 virtual table + auto-sync triggers for instant search.
      for (final stmt in const [
        "CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5("
            "title, artist, album, content=tracks, content_rowid=rowid, "
            "tokenize='unicode61 remove_diacritics 2', prefix='2 3')",
        "CREATE TRIGGER IF NOT EXISTS tracks_ai AFTER INSERT ON tracks "
            "BEGIN INSERT INTO tracks_fts(rowid, title, artist, album) "
            "VALUES (new.rowid, new.title, new.artist, new.album); END",
        "CREATE TRIGGER IF NOT EXISTS tracks_ad AFTER DELETE ON tracks "
            "BEGIN INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) "
            "VALUES ('delete', old.rowid, old.title, old.artist, old.album); END",
        "CREATE TRIGGER IF NOT EXISTS tracks_au AFTER UPDATE ON tracks "
            "BEGIN "
            "INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) "
            "VALUES ('delete', old.rowid, old.title, old.artist, old.album); "
            "INSERT INTO tracks_fts(rowid, title, artist, album) "
            "VALUES (new.rowid, new.title, new.artist, new.album); END",
        "INSERT INTO tracks_fts(rowid, title, artist, album) "
            "SELECT rowid, title, artist, album FROM tracks",
      ]) {
        try {
          await db.customStatement(stmt);
        } on Exception {
          // FTS table or triggers may already exist — skip.
        }
      }
    },
    onUpgrade: (m, from, to) async {
      // v1 → v2 introduces local-mode favorites and user playlists
      // so the hearts and "Save to playlist" actions can persist
      // without a music server.
      if (from < 2) {
        await m.createTable(favorites);
        await m.createTable(playlists);
        await m.createTable(playlistEntries);
      }
      if (from < 3) {
        await m.createTable(cacheEntries);
      }
      if (from < 4) {
        await m.createTable(queueHistory);
      }
      if (from < 5) {
        await m.createTable(playbackHistory);
      }
      if (from < 6) {
        await m.addColumn(playbackHistory, playbackHistory.skipped);
      }
      if (from < 7) {
        await m.addColumn(playbackHistory, playbackHistory.completionRate);
      }
      if (from < 8) {
        await m.createTable(trackStats);
        await m.createTable(trackCoOccurrences);
      }
      if (from < 9) {
        await m.createTable(lastfmSimilarCache);
      }
      if (from < 10) {
        // Performance indexes for common query patterns.
        // Drift's m.createIndex() expects an Index object. Since these aren't
        // defined on table classes, we use raw SQL via the migrator's database.
        // Each index is wrapped in try-catch — if the table was never created
        // (e.g. in a partial migration test), skipping the index is harmless.
        final db = m.database;
        for (final stmt in const [
          'CREATE INDEX IF NOT EXISTS idx_playlist_entries_playlist_id '
              'ON playlist_entries (playlist_id)',
          'CREATE INDEX IF NOT EXISTS idx_playback_history_track_id '
              'ON playback_history (track_id)',
          'CREATE INDEX IF NOT EXISTS idx_tracks_artist '
              'ON tracks (artist)',
          'CREATE INDEX IF NOT EXISTS idx_tracks_album '
              'ON tracks (album)',
          'CREATE INDEX IF NOT EXISTS idx_tracks_genre '
              'ON tracks (genre)',
          'CREATE INDEX IF NOT EXISTS idx_tracks_last_modified '
              'ON tracks (last_modified)',
        ]) {
          try {
            await db.customStatement(stmt);
          } on Exception {
            // Table may not exist — skip index, no data loss.
          }
        }
      }
      if (from < 11) {
        // Index on played_at for ORDER BY queries in _getRecentlyPlayedIds
        // and getLostMemories.
        try {
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_playback_history_played_at '
            'ON playback_history (played_at)',
          );
        } on Exception {
          // Table may not exist — skip index, no data loss.
        }
      }
      if (from < 12) {
        // Performance indexes for co-occurrence lookups and composite
        // track queries (artist+title search, album browsing).
        final db = m.database;
        for (final stmt in const [
          'CREATE INDEX IF NOT EXISTS idx_track_co_occurrences_track_a '
              'ON track_co_occurrences (track_a_id)',
          'CREATE INDEX IF NOT EXISTS idx_tracks_artist_title '
              'ON tracks (artist, title)',
          'CREATE INDEX IF NOT EXISTS idx_tracks_album_artist '
              'ON tracks (album, album_artist)',
        ]) {
          try {
            await db.customStatement(stmt);
          } on Exception {
            // Table may not exist — skip index, no data loss.
          }
        }
      }
      if (from < 13) {
        // Pre-computed spectral hue for instant palette lookup during playback.
        // Nullable — only populated for tracks with extracted cover art.
        try {
          await m.addColumn(tracks, tracks.spectralHue);
        } on Exception {
          // Table may not exist — skip, no data loss.
        }
      }
      if (from < 14) {
        // Performance indexes for track stats lookups, similar track cache,
        // and queue history sorting.
        final db = m.database;
        for (final stmt in const [
          'CREATE INDEX IF NOT EXISTS idx_track_stats_track_id '
              'ON track_stats (track_id)',
          'CREATE INDEX IF NOT EXISTS idx_lastfm_similar_cache_track_id '
              'ON lastfm_similar_cache (track_id)',
          'CREATE INDEX IF NOT EXISTS idx_queue_history_created_at '
              'ON queue_history (created_at)',
        ]) {
          try {
            await db.customStatement(stmt);
          } on Exception {
            // Table may not exist — skip index, no data loss.
          }
        }
      }
      if (from < 15) {
        // Composite index for playlist entry ordering: covers both WHERE
        // playlist_id = ? and ORDER BY position in a single b-tree scan.
        // Avoids filesort on playlists with 5000+ entries.
        try {
          await m.database.customStatement(
            'CREATE INDEX IF NOT EXISTS idx_playlist_entries_playlist_position '
            'ON playlist_entries (playlist_id, position)',
          );
        } on Exception {
          // Table may not exist — skip index, no data loss.
        }
      }
      if (from < 16) {
        // FTS5 virtual table + auto-sync triggers for instant track search.
        // Replaces LIKE '%query%' full-table-scan with inverted index.
        final db = m.database;
        for (final stmt in const [
          "CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5("
              "title, artist, album, content=tracks, content_rowid=rowid, "
              "tokenize='unicode61 remove_diacritics 2', prefix='2 3')",
          "CREATE TRIGGER IF NOT EXISTS tracks_ai AFTER INSERT ON tracks "
              "BEGIN INSERT INTO tracks_fts(rowid, title, artist, album) "
              "VALUES (new.rowid, new.title, new.artist, new.album); END",
          "CREATE TRIGGER IF NOT EXISTS tracks_ad AFTER DELETE ON tracks "
              "BEGIN INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) "
              "VALUES ('delete', old.rowid, old.title, old.artist, old.album); END",
          "CREATE TRIGGER IF NOT EXISTS tracks_au AFTER UPDATE ON tracks "
              "BEGIN "
              "INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) "
              "VALUES ('delete', old.rowid, old.title, old.artist, old.album); "
              "INSERT INTO tracks_fts(rowid, title, artist, album) "
              "VALUES (new.rowid, new.title, new.artist, new.album); END",
          "INSERT INTO tracks_fts(rowid, title, artist, album) "
              "SELECT rowid, title, artist, album FROM tracks",
        ]) {
          try {
            await db.customStatement(stmt);
          } on Exception {
            // FTS table or triggers may already exist — skip.
          }
        }
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'aetherfin_drift.db'));
    return NativeDatabase.createInBackground(file);
  });
}
