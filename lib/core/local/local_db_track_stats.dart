import 'package:drift/drift.dart';
import 'app_database.dart';

class TrackStatsRepository {
  TrackStatsRepository(this.db);
  final AppDatabase db;

  Future<TrackStatsEntity?> getStats(String trackId) async {
    final query = db.select(db.trackStats)
      ..where((t) => t.trackId.equals(trackId));
    return query.getSingleOrNull();
  }

  Future<Map<String, TrackStatsEntity>> getStatsForTracks(
    List<String> trackIds,
  ) async {
    if (trackIds.isEmpty) return const {};
    final result = <String, TrackStatsEntity>{};
    const chunkSize = 500;
    for (var i = 0; i < trackIds.length; i += chunkSize) {
      final chunk = trackIds.sublist(
        i,
        i + chunkSize > trackIds.length ? trackIds.length : i + chunkSize,
      );
      final query = db.select(db.trackStats)
        ..where((t) => t.trackId.isIn(chunk));
      final rows = await query.get();
      for (final row in rows) {
        result[row.trackId] = row;
      }
    }
    return result;
  }

  Future<void> recordPlay(
    String trackId, {
    required double completionRate,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db
        .into(db.trackStats)
        .insert(
          TrackStatsCompanion.insert(
            trackId: trackId,
            playCount: const Value(1),
            avgCompletion: Value(completionRate),
            lastPlayed: Value(now),
          ),
          onConflict: DoUpdate.withExcluded((old, excluded) {
            final newCount = old.playCount + const Constant(1);
            return TrackStatsCompanion.custom(
              playCount: newCount,
              avgCompletion:
                  ((old.avgCompletion * old.playCount.dartCast<double>()) +
                      excluded.avgCompletion) /
                  newCount.dartCast<double>(),
              lastPlayed: Variable(now),
            );
          }),
        );
  }

  Future<void> recordSkip(
    String trackId, {
    required double completionRate,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db
        .into(db.trackStats)
        .insert(
          TrackStatsCompanion.insert(
            trackId: trackId,
            skipCount: const Value(1),
            avgCompletion: Value(completionRate),
            lastPlayed: Value(now),
          ),
          onConflict: DoUpdate.withExcluded((old, excluded) {
            final newCount = old.skipCount + const Constant(1);
            return TrackStatsCompanion.custom(
              skipCount: newCount,
              avgCompletion:
                  ((old.avgCompletion * old.playCount.dartCast<double>()) +
                      excluded.avgCompletion) /
                  newCount.dartCast<double>(),
              lastPlayed: Variable(now),
            );
          }),
        );
  }

  Future<void> deleteStats(String trackId) async {
    await (db.delete(
      db.trackStats,
    )..where((t) => t.trackId.equals(trackId))).go();
  }
}
