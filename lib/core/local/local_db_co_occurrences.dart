import 'package:drift/drift.dart';
import 'app_database.dart';

class CoOccurrenceRepository {
  CoOccurrenceRepository(this.db);
  final AppDatabase db;

  Future<void> increment(String trackAId, String trackBId) async {
    await db
        .into(db.trackCoOccurrences)
        .insert(
          TrackCoOccurrencesCompanion.insert(
            trackAId: trackAId,
            trackBId: trackBId,
            count: const Value(1),
          ),
          onConflict: DoUpdate((old) {
            return TrackCoOccurrencesCompanion.custom(
              count: old.count + const Constant(1),
            );
          }),
        );
  }

  Future<int> getCount(String trackAId, String trackBId) async {
    final query = db.select(db.trackCoOccurrences)
      ..where((t) => t.trackAId.equals(trackAId) & t.trackBId.equals(trackBId));
    final row = await query.getSingleOrNull();
    return row?.count ?? 0;
  }

  Future<Map<String, int>> getCountsForSeed(
    String seedId,
    List<String> candidateIds,
  ) async {
    if (candidateIds.isEmpty) return const {};
    final result = <String, int>{};
    const chunkSize = 500;
    for (var i = 0; i < candidateIds.length; i += chunkSize) {
      final chunk = candidateIds.sublist(
        i,
        i + chunkSize > candidateIds.length
            ? candidateIds.length
            : i + chunkSize,
      );
      final query = db.select(db.trackCoOccurrences)
        ..where((t) => t.trackAId.equals(seedId) & t.trackBId.isIn(chunk));
      final rows = await query.get();
      for (final row in rows) {
        result[row.trackBId] = row.count;
      }
    }
    return result;
  }

  Future<int> getMaxCount(String trackAId) async {
    final query = db.customSelect(
      'SELECT MAX(count) AS max_count FROM track_co_occurrences WHERE track_a_id = ?1',
      variables: [Variable<String>(trackAId)],
      readsFrom: {db.trackCoOccurrences},
    );
    final row = await query.getSingleOrNull();
    return row?.read<int?>('max_count') ?? 0;
  }

  Future<List<String>> getTopCoOccurred(
    String trackAId, {
    int limit = 15,
  }) async {
    final query = db.customSelect(
      'SELECT track_b_id FROM track_co_occurrences WHERE track_a_id = ?1 ORDER BY count DESC LIMIT ?2',
      variables: [Variable<String>(trackAId), Variable<int>(limit)],
      readsFrom: {db.trackCoOccurrences},
    );
    final rows = await query.get();
    return rows.map((r) => r.read<String>('track_b_id')).toList();
  }

  Future<void> prune({int keep = 10000}) async {
    await db.customStatement(
      'DELETE FROM track_co_occurrences WHERE rowid IN ('
      'SELECT rowid FROM track_co_occurrences ORDER BY count ASC '
      'LIMIT -1 OFFSET ?1)',
      [keep],
    );
  }
}
