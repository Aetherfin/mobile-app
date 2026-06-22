import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:aetherfin/core/local/app_database.dart';

void main() {
  // Test opens multiple AppDatabase instances (group-level + migration test).
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('QueueHistory schema', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test('class has correct columns', () {
      expect(db.queueHistory, isNotNull);
      final table = db.queueHistory;
      expect(table.id, isA<Column>());
      expect(table.trackIdsJson, isA<Column>());
      expect(table.sourceLabel, isA<Column>());
      expect(table.sourceType, isA<Column>());
      expect(table.sourceId, isA<Column>());
      expect(table.createdAt, isA<Column>());
    });

    test('insert and read QueueHistory entries', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.queueHistory)
          .insert(
            QueueHistoryCompanion.insert(
              id: 'test-uuid-1',
              trackIdsJson: '["track1","track2"]',
              sourceLabel: 'Album: Test Album',
              sourceType: 'album',
              sourceId: const Value('album-123'),
              createdAt: now - 1000,
            ),
          );
      await db
          .into(db.queueHistory)
          .insert(
            QueueHistoryCompanion.insert(
              id: 'test-uuid-2',
              trackIdsJson: '["track3"]',
              sourceLabel: 'Playlist: My Favorites',
              sourceType: 'playlist',
              createdAt: now,
            ),
          );

      final rows = await (db.select(
        db.queueHistory,
      )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

      expect(rows.length, 2);
      expect(rows[0].id, 'test-uuid-2');
      expect(rows[0].trackIdsJson, '["track3"]');
      expect(rows[0].sourceLabel, 'Playlist: My Favorites');
      expect(rows[0].sourceType, 'playlist');
      expect(rows[0].sourceId, isNull);
      expect(rows[1].id, 'test-uuid-1');
      expect(rows[1].sourceType, 'album');
      expect(rows[1].sourceId, 'album-123');
    });

    test('schema version is 17', () {
      expect(db.schemaVersion, 17);
    });

    test('migration from v9 to v10 creates performance indexes', () async {
      final sqliteDb = sqlite3.openInMemory();
      sqliteDb.execute('PRAGMA user_version = 9;');
      sqliteDb.execute('''
        CREATE TABLE playback_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          track_id TEXT NOT NULL,
          played_at INTEGER NOT NULL,
          title TEXT,
          artist TEXT,
          album TEXT,
          duration_ms INTEGER,
          image_url TEXT,
          source_id TEXT,
          source_type TEXT,
          skipped INTEGER NOT NULL DEFAULT 0,
          completion_rate REAL NOT NULL DEFAULT 0.0
        );
      ''');
      sqliteDb.execute('''
        CREATE TABLE track_stats (
          track_id TEXT NOT NULL PRIMARY KEY,
          play_count INTEGER NOT NULL DEFAULT 0,
          skip_count INTEGER NOT NULL DEFAULT 0,
          avg_completion REAL NOT NULL DEFAULT 0.0,
          last_played INTEGER
        );
      ''');
      sqliteDb.execute('''
        CREATE TABLE track_co_occurrences (
          track_a_id TEXT NOT NULL,
          track_b_id TEXT NOT NULL,
          count INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (track_a_id, track_b_id)
        );
      ''');
      sqliteDb.execute('''
        CREATE TABLE tracks (id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT DEFAULT "", album TEXT DEFAULT "", album_artist TEXT DEFAULT "", track_number INTEGER, duration_ms INTEGER DEFAULT 0, year INTEGER, genre TEXT DEFAULT "", file_path TEXT NOT NULL, file_size INTEGER, last_modified INTEGER, cover_path TEXT, codec TEXT DEFAULT "", bitrate INTEGER, sample_rate INTEGER)
      ''');
      sqliteDb.execute(
        'CREATE TABLE folders (uri TEXT PRIMARY KEY, display_path TEXT NOT NULL, added_at INTEGER NOT NULL)',
      );
      sqliteDb.execute('''
        CREATE TABLE favorites (id INTEGER PRIMARY KEY AUTOINCREMENT, track_id TEXT NOT NULL UNIQUE, added_at INTEGER NOT NULL)
      ''');
      sqliteDb.execute('''
        CREATE TABLE playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, created_at INTEGER NOT NULL, updated_at INTEGER)
      ''');
      sqliteDb.execute('''
        CREATE TABLE playlist_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id TEXT NOT NULL, track_id TEXT NOT NULL, sort_order INTEGER NOT NULL, added_at INTEGER NOT NULL)
      ''');
      sqliteDb.execute('''
        CREATE TABLE cache_entries (key TEXT PRIMARY KEY, value TEXT NOT NULL, expires_at INTEGER)
      ''');
      sqliteDb.execute('''
        CREATE TABLE queue_history (id TEXT PRIMARY KEY, track_ids_json TEXT NOT NULL, source_label TEXT NOT NULL, source_type TEXT NOT NULL, source_id TEXT, created_at INTEGER NOT NULL)
      ''');
      sqliteDb.execute('''
        CREATE TABLE lastfm_similar_cache (track_id TEXT NOT NULL PRIMARY KEY, similar_track_ids TEXT NOT NULL, cached_at INTEGER NOT NULL)
      ''');

      final db = AppDatabase.forTesting(NativeDatabase.opened(sqliteDb));

      // Verify all tables still work after migration
      final historyRows = await db.select(db.playbackHistory).get();
      expect(historyRows, isEmpty);

      await db
          .into(db.trackStats)
          .insert(TrackStatsCompanion.insert(trackId: 'migrated-track'));
      final statsRows = await db.select(db.trackStats).get();
      expect(statsRows.length, 1);

      // Verify indexes were created before closing
      final afterIndexes = await (db.customSelect(
        'SELECT name FROM sqlite_master WHERE type=\'index\' AND name LIKE \'idx_%\'',
      )).get();
      final indexNames = afterIndexes
          .map((r) => r.read<String>('name'))
          .toList();
      expect(indexNames, contains('idx_playlist_entries_playlist_id'));
      expect(indexNames, contains('idx_playback_history_track_id'));
      expect(indexNames, contains('idx_tracks_artist'));
      expect(indexNames, contains('idx_tracks_album'));
      expect(indexNames, contains('idx_tracks_genre'));
      expect(indexNames, contains('idx_tracks_last_modified'));

      await db.close();
    });
  });
}
