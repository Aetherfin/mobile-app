import 'dart:async' show unawaited;

import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../../utils/log.dart';
import 'lrc_parser.dart';
import 'lyrics_resolver.dart';

/// Pre-fetches lyrics for upcoming tracks in the playback queue.
///
/// On track change, [preloadNext] resolves lyrics (embedded → NetEase → LRCLib)
/// for tracks at [currentIndex] +1, +2, +3. All resolution is fire-and-forget
/// via [unawaited] — it never blocks playback.
///
/// Tracks that have already been preloaded (tracked by [LyricsPreloadManager])
/// or that already exist in the [LyricsResolver] cache are skipped to avoid
/// redundant network calls.
class LyricsPreloadManager {
  LyricsPreloadManager({
    required MusicBackend backend,
    LyricsResolver? resolver,
    this.onCachedResult,
  }) : _resolver = resolver ?? LyricsResolver(backend: backend);

  final Future<void> Function(String trackId, LyricsResult result)?
  onCachedResult;

  final LyricsResolver _resolver;

  /// Tracks that have already been scheduled for preload this session.
  final Set<String> _preloadedTrackIds = {};

  /// The underlying [LyricsResolver], whose cache is populated by preloads.
  /// Useful for tests or direct access to cached lyrics.
  LyricsResolver get resolver => _resolver;

  /// Preload lyrics for up to 3 tracks ahead of [currentIndex].
  ///
  /// Skips tracks already in the resolver's cache or already preloaded.
  /// No-op if queue is empty or [currentIndex] is at the end.
  void preloadNext({required List<AfTrack> queue, required int currentIndex}) {
    if (queue.isEmpty) return;
    if (currentIndex < 0 || currentIndex >= queue.length - 1) return;

    final start = currentIndex + 1;
    final end = (start + 3).clamp(0, queue.length);

    for (var i = start; i < end; i++) {
      final track = queue[i];
      final trackId = track.id;

      // Skip if already preloaded or already in resolver cache
      if (_preloadedTrackIds.contains(trackId)) continue;
      if (_resolver.isCached(trackId)) continue;

      _preloadedTrackIds.add(trackId);
      unawaited(_preloadLyrics(track));
    }
  }

  /// Resolve and cache lyrics for a single track.
  Future<void> _preloadLyrics(AfTrack track) async {
    try {
      final result = await _resolver.resolve(trackId: track.id, track: track);
      if (result != null) {
        afLog('lyrics', 'Preloaded lyrics for "${track.title}" (${track.id})');
        await onCachedResult?.call(track.id, result);
      } else {
        afLog('lyrics', 'No lyrics found for "${track.title}" (${track.id})');
      }
    } on Exception catch (e, stack) {
      afLog(
        'lyrics',
        'Preload failed for "${track.title}" (${track.id})',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Clear the preload tracking set.
  ///
  /// Call when the queue changes so tracks from a previous queue can be
  /// preloaded again if they appear in the new queue.
  void reset() {
    _preloadedTrackIds.clear();
  }
}
