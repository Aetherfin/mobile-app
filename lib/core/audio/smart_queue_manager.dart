import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../lastfm/lastfm_client.dart';
import '../local/app_database.dart';
import '../local/local_db.dart';
import 'queue_candidate_provider.dart';
import 'track_scorer.dart';

/// Smart queue manager: learns from listening behavior to suggest relevant
/// next tracks. Operates in two modes:
///   - **Local mode:** uses [LocalDb] for genre/artist/co-occurrence queries.
///   - **Server mode:** uses [MusicBackend.instantMix] + co-occurrence data.
///
/// Maintains an internal buffer of scored candidates. The player service
/// pulls from this buffer when the playback queue runs low.
class SmartQueueManager {
  SmartQueueManager({this.localDb, this.backend, this.lastfmClient});

  final LocalDb? localDb;
  final MusicBackend? backend;
  final LastFmClient? lastfmClient;

  /// Reused across scoring passes to avoid entropy-seeded allocations.
  final Random _random = Random();

  /// TTL cache for [_getRecentlyPlayedIds].
  Set<String>? _recentlyPlayedCache;
  DateTime? _recentlyPlayedCacheTime;
  static const Duration _recentlyPlayedTtl = Duration(seconds: 5);

  // ── Buffer ──────────────────────────────────────────────────────────────

  final List<AfTrack> _buffer = [];
  static const int bufferSize = 15;
  static const int refillThreshold = 5;

  /// Guards against concurrent refill/dequeue buffer mutations.
  bool _busy = false;

  bool get isBufferLow => _buffer.length < refillThreshold;
  int get bufferLength => _buffer.length;

  List<AfTrack> dequeueBatch(int count) {
    if (_busy || _buffer.isEmpty) return const [];
    final actual = count > _buffer.length ? _buffer.length : count;
    final batch = _buffer.sublist(0, actual);
    _buffer.removeRange(0, actual);
    return batch;
  }

  AfTrack? peekNext() => _buffer.isNotEmpty ? _buffer.first : null;
  void clearBuffer() => _buffer.clear();

  // ── Feedback loop ──────────────────────────────────────────────────────

  Future<void> recordPlayback(
    AfTrack track, {
    required double completionRate,
    bool isSkipped = false,
  }) async {
    final stats = localDb?.trackStats;
    if (stats == null) return;
    try {
      if (isSkipped) {
        await stats.recordSkip(track.id, completionRate: completionRate);
      } else {
        await stats.recordPlay(track.id, completionRate: completionRate);
      }
      _recentlyPlayedCache = null;
      _recentlyPlayedCacheTime = null;
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'SmartQueue.recordPlayback failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> recordTransition(
    AfTrack from,
    AfTrack to, {
    required double completionRate,
  }) async {
    if (completionRate < 0.8) return;
    final co = localDb?.coOccurrences;
    if (co == null) return;
    try {
      await co.increment(from.id, to.id);
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'SmartQueue.recordTransition failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // ── Refill buffer ──────────────────────────────────────────────────────

  Future<void> refillBuffer(AfTrack current) async {
    if (_busy) return;
    if (_buffer.length >= bufferSize) return;
    _busy = true;
    try {
      final recentlyPlayedIds = await _getRecentlyPlayedIds();
      final provider = QueueCandidateProvider(
        localDb: localDb,
        backend: backend,
        lastfmClient: lastfmClient,
      );
      final candidates = await provider.getCandidates(
        current,
        recentlyPlayedIds,
      );
      if (candidates.isNotEmpty) {
        final scored = await _scoreAll(candidates, current, recentlyPlayedIds);
        final need = bufferSize - _buffer.length;
        _buffer.addAll(scored.take(need).map((e) => e.key));
      }
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'SmartQueue.refillBuffer failed',
        error: e,
        stackTrace: stack,
      );
    } finally {
      _busy = false;
    }
  }

  // ── Recently played ────────────────────────────────────────────────────

  Future<Set<String>> _getRecentlyPlayedIds({int limit = 20}) async {
    if (localDb == null) return {};
    final now = DateTime.now();
    if (_recentlyPlayedCache != null && _recentlyPlayedCacheTime != null) {
      if (now.difference(_recentlyPlayedCacheTime!) < _recentlyPlayedTtl) {
        return _recentlyPlayedCache!;
      }
    }
    try {
      final rows = await localDb!.db
          .customSelect(
            'SELECT DISTINCT track_id FROM playback_history ORDER BY played_at DESC LIMIT ?1',
            variables: [Variable<int>(limit)],
            readsFrom: {localDb!.db.playbackHistory},
          )
          .get();
      final result = rows.map((r) => r.read<String>('track_id')).toSet();
      _recentlyPlayedCache = result;
      _recentlyPlayedCacheTime = now;
      return result;
    } catch (e, stack) {
      afLog(
        'error',
        'Recently played cache query failed',
        error: e,
        stackTrace: stack,
      );
      return {};
    }
  }

  // ── Scoring engine ─────────────────────────────────────────────────────

  Future<
    ({
      Map<String, TrackStatsEntity> stats,
      Map<String, int> coCounts,
      int maxCo,
    })
  >
  _fetchScoringData(AfTrack seed, List<String> candidateIds) async {
    return (
      stats: localDb != null
          ? await localDb!.trackStats.getStatsForTracks(candidateIds)
          : const <String, TrackStatsEntity>{},
      coCounts: localDb != null
          ? await localDb!.coOccurrences.getCountsForSeed(seed.id, candidateIds)
          : const <String, int>{},
      maxCo: localDb != null
          ? await localDb!.coOccurrences.getMaxCount(seed.id)
          : 0,
    );
  }

  Future<List<MapEntry<AfTrack, double>>> _scoreAll(
    Set<AfTrack> candidates,
    AfTrack seed,
    Set<String> recentlyPlayedIds,
  ) async {
    if (candidates.isEmpty) return const [];
    final recentlyList = recentlyPlayedIds.toList();
    final candidateIds = candidates.map((c) => c.id).toList();
    final data = await _fetchScoringData(seed, candidateIds);

    final results = <MapEntry<AfTrack, double>>[];
    for (final candidate in candidates) {
      final rawStats = data.stats[candidate.id];
      final score = scoreOneTrack(
        candidate,
        seed,
        recentlyList,
        stats: rawStats != null
            ? SimpleTrackStats(rawStats.avgCompletion, rawStats.skipCount)
            : null,
        coCount: data.coCounts[candidate.id] ?? 0,
        maxCo: data.maxCo,
        random: _random,
      );
      results.add(MapEntry(candidate, score));
    }
    results.sort((a, b) => b.value.compareTo(a.value));
    return results;
  }

  /// Public scoring: score all [candidates] against [seed], return sorted.
  ///
  /// Runs the CPU-heavy scoring loop in a background isolate so large
  /// libraries (50K+ tracks) don't freeze the UI.
  Future<List<AfTrack>> scoreAndSort(
    AfTrack seed,
    List<AfTrack> candidates,
  ) async {
    if (candidates.isEmpty) return candidates;
    final recentlyPlayedIds = (await _getRecentlyPlayedIds(limit: 20)).toList();
    final candidateIds = candidates.map((c) => c.id).toList();
    final data = await _fetchScoringData(seed, candidateIds);

    final simpleStats = <String, SimpleTrackStats>{};
    for (final entry in data.stats.entries) {
      simpleStats[entry.key] = SimpleTrackStats(
        entry.value.avgCompletion,
        entry.value.skipCount,
      );
    }

    return Isolate.run(
      () => scoreTracksInBackground(
        ScoringParams(
          seed: seed,
          candidates: candidates,
          recentlyPlayedIds: recentlyPlayedIds,
          statsMap: simpleStats,
          coCountsMap: data.coCounts,
          maxCo: data.maxCo,
        ),
      ),
    );
  }
}
