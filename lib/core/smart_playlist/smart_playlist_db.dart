import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/app_database.dart';
import 'smart_playlist_model.dart';

/// Storage for smart playlist definitions.
/// Refactored to wrap Drift's [AppDatabase].
class SmartPlaylistDb {
  SmartPlaylistDb({required this.db});
  final AppDatabase db;

  // ── CRUD ────────────────────────────────────────────────────────────────

  Future<List<SmartPlaylist>> getAll() async {
    final rows = await (db.select(
      db.smartPlaylists,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();
    return rows.map(_rowToPlaylist).toList();
  }

  Future<SmartPlaylist?> getById(String id) async {
    final query = db.select(db.smartPlaylists)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return _rowToPlaylist(row);
  }

  Future<SmartPlaylist> save(SmartPlaylist playlist) async {
    return db.transaction(() async {
      final isNew =
          await (db.select(db.smartPlaylists)
                ..where((t) => t.id.equals(playlist.id))
                ..limit(1))
              .get()
              .then((rows) => rows.isEmpty);
      final id = isNew && playlist.id.isEmpty ? const Uuid().v4() : playlist.id;
      final updated = playlist.copyWith(
        id: id,
        createdAt: isNew ? DateTime.now() : playlist.createdAt,
        updatedAt: DateTime.now(),
      );

      await db
          .into(db.smartPlaylists)
          .insert(
            SmartPlaylistsCompanion.insert(
              id: updated.id,
              name: updated.name,
              combinator: Value(updated.combinator),
              rulesJson: Value(updated.rulesJson),
              sort: Value(updated.sort),
              sortOrder: Value(updated.sortOrder),
              maxLimit: Value(updated.limit),
              createdAt: updated.createdAt.millisecondsSinceEpoch,
              updatedAt: updated.updatedAt.millisecondsSinceEpoch,
            ),
            mode: InsertMode.replace,
          );

      return updated;
    });
  }

  Future<void> delete(String id) async {
    await (db.delete(db.smartPlaylists)..where((t) => t.id.equals(id))).go();
  }

  Future<int> count() async {
    final countExp = db.smartPlaylists.id.count();
    final query = db.selectOnly(db.smartPlaylists)..addColumns([countExp]);
    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  SmartPlaylist _rowToPlaylist(SmartPlaylistEntity r) {
    return SmartPlaylist(
      id: r.id,
      name: r.name,
      combinator: r.combinator,
      rules: SmartPlaylist.parseRules(r.rulesJson),
      sort: r.sort,
      sortOrder: r.sortOrder,
      limit: r.maxLimit,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt),
    );
  }

  Future<void> close() async {
    await db.close();
  }
}
