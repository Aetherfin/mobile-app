import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Persists active queue state (track IDs, current index, position,
/// shuffle mapping) to SharedPreferences.
///
/// This is a client-side fallback for backends that don't natively
/// persist the play queue (Jellyfin, LocalBackend). Navidrome manages
/// queue state server-side via [MusicBackend.savePlayQueue] / [MusicBackend.getPlayQueue].
///
/// Only track IDs are persisted — full [AfTrack] objects are not
/// serializable across restarts. The caller is responsible for resolving
/// IDs to tracks via the active [MusicBackend].
class ActiveQueueStore {
  static const _kTrackIds = 'af.active_queue.track_ids';
  static const _kCurrentIndex = 'af.active_queue.current_index';
  static const _kPositionMs = 'af.active_queue.position_ms';
  static const _kShuffleMapping = 'af.active_queue.shuffle_mapping';
  static const _kShuffleEnabled = 'af.active_queue.shuffle_enabled';

  /// Maximum number of track IDs to persist (ArchiveTune windowed pattern).
  /// Saves up to 20 before + current + 50 after = 71 total.
  static const int maxPersistedTracks = 71;

  /// Save the current queue state.
  ///
  /// [trackIds] — ordered list of track identifiers in the queue.
  /// [currentIndex] — logical index of the now-playing track.
  /// [position] — current playback position.
  /// [shuffleMapping] — Fisher-Yates shuffle order (null when shuffle is off).
  /// [shuffleEnabled] — whether shuffle mode is active.
  Future<void> save({
    required List<String> trackIds,
    required int currentIndex,
    required Duration position,
    List<int>? shuffleMapping,
    bool shuffleEnabled = false,
  }) async {
    final p = await SharedPreferences.getInstance();

    // Windowed save: keep a window around currentIndex
    final window = windowed(trackIds, currentIndex);
    final windowedIds = window.trackIds;
    final adjustedIndex = window.adjustedIndex;

    await p.setStringList(_kTrackIds, windowedIds);
    await p.setInt(_kCurrentIndex, adjustedIndex);
    await p.setInt(_kPositionMs, position.inMilliseconds);
    await p.setBool(_kShuffleEnabled, shuffleEnabled);

    if (shuffleMapping != null && shuffleMapping.isNotEmpty) {
      await p.setStringList(
        _kShuffleMapping,
        shuffleMapping.map((e) => e.toString()).toList(),
      );
    } else {
      await p.remove(_kShuffleMapping);
    }
  }

  /// Restore a previously saved queue state.
  ///
  /// Returns `null` when no saved queue exists.
  Future<
    ({
      List<String> trackIds,
      int currentIndex,
      Duration position,
      List<int>? shuffleMapping,
      bool shuffleEnabled,
    })?
  >
  restore() async {
    final p = await SharedPreferences.getInstance();
    final trackIds = p.getStringList(_kTrackIds);
    if (trackIds == null || trackIds.isEmpty) return null;

    final currentIndex = p.getInt(_kCurrentIndex) ?? 0;
    final positionMs = p.getInt(_kPositionMs) ?? 0;
    final shuffleEnabled = p.getBool(_kShuffleEnabled) ?? false;

    List<int>? shuffleMapping;
    final rawMapping = p.getStringList(_kShuffleMapping);
    if (rawMapping != null && rawMapping.isNotEmpty) {
      shuffleMapping = rawMapping.map((e) => int.tryParse(e) ?? 0).toList();
    }

    return (
      trackIds: trackIds,
      currentIndex: currentIndex.clamp(0, trackIds.length - 1),
      position: Duration(milliseconds: positionMs),
      shuffleMapping: shuffleMapping,
      shuffleEnabled: shuffleEnabled,
    );
  }

  /// Clear all persisted queue state.
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTrackIds);
    await p.remove(_kCurrentIndex);
    await p.remove(_kPositionMs);
    await p.remove(_kShuffleMapping);
    await p.remove(_kShuffleEnabled);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Slice [ids] to a window around [currentIndex]:
  /// - 20 tracks before current
  /// - current track
  /// - 50 tracks after current
  /// Returns the windowed list and the adjusted current index.
  @visibleForTesting
  ({List<String> trackIds, int adjustedIndex}) windowed(
    List<String> ids,
    int currentIndex,
  ) {
    if (ids.length <= maxPersistedTracks) {
      return (trackIds: ids, adjustedIndex: currentIndex);
    }

    // Calculate the half-windows
    const beforeCount = 20;
    const afterCount = 50;

    final start = (currentIndex - beforeCount).clamp(0, ids.length);
    final end = (currentIndex + afterCount + 1).clamp(0, ids.length);
    final sliced = ids.sublist(start, end);
    final adjusted = currentIndex - start;

    return (trackIds: sliced, adjustedIndex: adjusted);
  }
}
