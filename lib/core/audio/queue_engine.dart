import 'dart:math';
import '../jellyfin/models/items.dart';

/// Single source of truth for queue state.
///
/// Pure Dart — no mpv dependency, no streams, no Flutter imports.
/// Owns the full track list, current index, and shuffle index mapping.
/// All queue mutations (reorder, remove, insert, shuffle) are pure Dart.
///
/// Shuffle design: Fisher-Yates index mapping.
/// - Shuffle OFF: _shuffleOrder is null, direct index access.
/// - Shuffle ON: _shuffleOrder[i] = original index in _tracks.
/// - queue[i] = _tracks[_shuffleOrder[i]]
class AfQueueEngine {
  AfQueueEngine({Random? random}) : _random = random ?? Random();

  List<AfTrack> _tracks = <AfTrack>[];
  int _currentIndex = -1;
  int _logicalIndex = -1;
  List<int>? _shuffleOrder;
  Map<int, int>? _physicalToLogical;
  List<AfTrack>? _shuffledTracks;
  bool _playbackEnded = false;

  // ── forNtimes loop mode fields ────────────────────────────────────
  bool _isForNtimes = false;
  int _remainingRepeats = 0;
  int _ntimesCount = 2;
  bool _isTailShuffle = false;

  final Random _random;

  /// Rebuild the physical→logical reverse index from [_shuffleOrder].
  void _rebuildPhysicalToLogical() {
    if (_shuffleOrder == null) {
      _physicalToLogical = null;
      return;
    }
    _physicalToLogical = <int, int>{};
    for (var logical = 0; logical < _shuffleOrder!.length; logical++) {
      _physicalToLogical![_shuffleOrder![logical]] = logical;
    }
  }

  // ── Query helpers ──────────────────────────────────────────────────

  List<AfTrack> get tracks {
    if (_shuffleOrder == null) return List<AfTrack>.unmodifiable(_tracks);
    _shuffledTracks ??= _shuffleOrder!
        .map((i) => _tracks[i])
        .toList(growable: false);
    return List<AfTrack>.unmodifiable(_shuffledTracks!);
  }

  /// Logical index in the queue (index into [_shuffleOrder] or direct
  /// index into [_tracks] when shuffle is off).
  int get currentIndex => _logicalIndex;

  bool get isShuffleEnabled => _shuffleOrder != null;
  List<int>? get shuffleOrder => _shuffleOrder;
  bool get playbackEnded => _playbackEnded;
  bool get isForNtimes => _isForNtimes;
  int get remainingRepeats => _remainingRepeats;
  int get ntimesCount => _ntimesCount;
  bool get isNtimesModeActive => _isForNtimes && _remainingRepeats > 0;
  bool get isTailShuffle => _isTailShuffle;

  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _tracks.length)
      ? _tracks[_currentIndex]
      : null;

  /// The next track that should be loaded after the current one.
  AfTrack? get nextTrack {
    final nextIdx = currentIndex + 1;
    if (nextIdx < 0 || nextIdx >= _tracks.length) return null;
    return trackAt(nextIdx);
  }

  bool get isAtQueueEnd {
    if (_tracks.isEmpty) return true;
    return currentIndex >= _tracks.length - 1;
  }

  bool get isEmpty => _tracks.isEmpty;
  int get length => _tracks.length;

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Replace the entire queue with [tracks] starting at [startIndex].
  void replaceAll(List<AfTrack> tracks, int startIndex) {
    _tracks = List<AfTrack>.of(tracks);
    if (_tracks.isEmpty) {
      _currentIndex = -1;
      _logicalIndex = -1;
    } else {
      _logicalIndex = startIndex.clamp(0, _tracks.length - 1);
      _currentIndex = physicalIndex(_logicalIndex);
    }
    _playbackEnded = false;
    _isTailShuffle = false;
    _shuffleOrder = null;
    _physicalToLogical = null;
    _shuffledTracks = null;
    resetRepeats();
  }

  /// End playback: set currentIndex to -1 without clearing the queue.
  void endPlayback() {
    _currentIndex = -1;
    _logicalIndex = -1;
    _playbackEnded = true;
    _isForNtimes = false;
    _remainingRepeats = 0;
  }

  /// Clear all state.
  void clear() {
    _tracks = <AfTrack>[];
    _currentIndex = -1;
    _logicalIndex = -1;
    _shuffleOrder = null;
    _physicalToLogical = null;
    _shuffledTracks = null;
    _playbackEnded = false;
    _isForNtimes = false;
    _remainingRepeats = 0;
    _isTailShuffle = false;
  }

  // ── Shuffle (Fisher-Yates index mapping) ───────────────────────────

  /// Enable or disable shuffle.
  ///
  /// When enabling: builds a Fisher-Yates shuffled index list.
  /// When disabling: nulls out the shuffle order (pure Dart, 0 mpv calls).
  void setShuffle(bool enabled) {
    if (enabled == isShuffleEnabled) return;
    if (enabled) {
      _shuffleOrder = List<int>.generate(_tracks.length, (i) => i);
      _fisherYatesShuffle();
      _rebuildPhysicalToLogical();
      _logicalIndex = _currentIndex >= 0 ? 0 : -1;
    } else {
      _shuffleOrder = null;
      _physicalToLogical = null;
      _logicalIndex = _currentIndex;
      _isTailShuffle = false;
    }
    _shuffledTracks = null;
  }

  /// Activate or deactivate forNtimes loop mode.
  void setForNtimes(bool enabled) {
    _isForNtimes = enabled;
    _remainingRepeats = enabled ? _ntimesCount : 0;
  }

  /// Set the N value (how many repeats per track).
  void setNtimesCount(int count) {
    _ntimesCount = count > 0 ? count : 2;
    if (_isForNtimes && _remainingRepeats > 0) {
      _remainingRepeats = _ntimesCount;
    }
  }

  /// Decrement remaining repeats (called on track completion).
  void decrementRepeats() {
    if (_remainingRepeats > 0) {
      _remainingRepeats--;
    }
  }

  /// Reset repeats counter to the configured N value.
  void resetRepeats() {
    if (_isForNtimes) {
      _remainingRepeats = _ntimesCount;
    }
  }

  /// Fisher-Yates shuffle of the current [_shuffleOrder].
  /// Preserves the current track's position so playback isn't interrupted.
  ///
  /// Optimized to use in-place shuffling to reduce memory allocations.
  void _fisherYatesShuffle() {
    if (_shuffleOrder == null || _tracks.isEmpty) return;

    final currentTrackId = _currentIndex >= 0 && _currentIndex < _tracks.length
        ? _tracks[_currentIndex].id
        : null;

    // Use in-place shuffling to reduce memory allocations
    final indices = _shuffleOrder!;

    if (currentTrackId != null) {
      // Find current index in shuffle order
      final currentPos = indices.indexOf(_currentIndex);

      if (currentPos > 0) {
        // Swap current to front
        indices[currentPos] = indices[0];
        indices[0] = _currentIndex;
      }

      // Shuffle the rest (positions 1 to end) using Fisher-Yates
      for (var i = 1; i < indices.length; i++) {
        final j = i + _random.nextInt(indices.length - i);
        final temp = indices[i];
        indices[i] = indices[j];
        indices[j] = temp;
      }
    } else {
      // Shuffle all positions using Fisher-Yates
      for (var i = 0; i < indices.length; i++) {
        final j = i + _random.nextInt(indices.length - i);
        final temp = indices[i];
        indices[i] = indices[j];
        indices[j] = temp;
      }
    }
  }

  /// Shuffle only the tail — everything after the current logical position.
  void shuffleTail() {
    if (_tracks.isEmpty) return;

    if (_logicalIndex < 0 || _logicalIndex >= _tracks.length - 1) return;

    final tailStart = _logicalIndex + 1;

    _isTailShuffle = true;

    if (_shuffleOrder == null) {
      _shuffleOrder = List<int>.generate(_tracks.length, (i) => i);
      final tail = _shuffleOrder!.sublist(tailStart);
      tail.shuffle(_random);
      _shuffleOrder = [..._shuffleOrder!.sublist(0, tailStart), ...tail];
    } else {
      final head = _shuffleOrder!.sublist(0, tailStart);
      final tail = _shuffleOrder!.sublist(tailStart);
      tail.shuffle(_random);
      _shuffleOrder = [...head, ...tail];
    }
    _shuffledTracks = null;
    _rebuildPhysicalToLogical();
    // _currentIndex stays at physicalIndex(_logicalIndex) which is unchanged
  }

  /// Reset forNtimes repeats counter on track jump.
  void _resetRepeatsOnJump() {
    if (_isForNtimes) {
      _remainingRepeats = _ntimesCount;
    }
  }

  /// Map a logical queue index to the actual track.
  /// Returns `null` if [logicalIndex] is out of bounds.
  AfTrack? trackAt(int logicalIndex) {
    if (logicalIndex < 0 || logicalIndex >= _tracks.length) return null;
    final actualIndex = _shuffleOrder != null
        ? _shuffleOrder![logicalIndex]
        : logicalIndex;
    return _tracks[actualIndex];
  }

  /// Convert a logical index to physical (_tracks) index.
  int physicalIndex(int logicalIndex) {
    return _shuffleOrder != null ? _shuffleOrder![logicalIndex] : logicalIndex;
  }

  /// Convert a physical (_tracks) index to logical (queue) index.
  int logicalIndex(int physicalIndex) {
    if (_shuffleOrder == null) return physicalIndex;
    return _physicalToLogical?[physicalIndex] ??
        _shuffleOrder!.indexOf(physicalIndex);
  }

  // ── Track transitions ──────────────────────────────────────────────

  /// Advance to the next track. Returns new currentIndex.
  int advanceIndex() {
    if (_tracks.isEmpty) return _logicalIndex;
    if (_logicalIndex < _tracks.length - 1) {
      _logicalIndex++;
      _currentIndex = physicalIndex(_logicalIndex);
      resetRepeats();
    }
    return _logicalIndex;
  }

  /// Retreat to the previous track. Returns new currentIndex.
  int retreatIndex() {
    if (_tracks.isEmpty) return _logicalIndex;
    if (_logicalIndex > 0) {
      _logicalIndex--;
      _currentIndex = physicalIndex(_logicalIndex);
      resetRepeats();
    }
    return _logicalIndex;
  }

  /// Jump to a specific logical index. Returns new currentIndex.
  int jumpTo(int logicalIndex) {
    if (_tracks.isEmpty) return _logicalIndex;
    final clamped = logicalIndex.clamp(0, _tracks.length - 1);
    _logicalIndex = clamped;
    _currentIndex = physicalIndex(_logicalIndex);
    _resetRepeatsOnJump();
    return _logicalIndex;
  }

  // ── Queue mutations (all pure Dart, 0 mpv calls) ───────────────────

  bool canReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tracks.length) return false;
    if (newIndex < 0 || newIndex > _tracks.length) return false;
    return oldIndex != newIndex;
  }

  /// Reorder a track from [oldIndex] to [newIndex].
  /// Returns the adjusted insertion index.
  int reorder(int oldIndex, int newIndex) {
    if (_shuffleOrder == null) {
      final track = _tracks.removeAt(oldIndex);
      final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
      _tracks.insert(insertIdx, track);

      // Track where the current track moved to after reorder
      if (_logicalIndex == oldIndex) {
        _logicalIndex = insertIdx;
        _currentIndex = _logicalIndex;
      } else if (oldIndex < _logicalIndex && insertIdx >= _logicalIndex) {
        _logicalIndex--;
        _currentIndex = _logicalIndex;
      } else if (oldIndex > _logicalIndex && insertIdx <= _logicalIndex) {
        _logicalIndex++;
        _currentIndex = _logicalIndex;
      }

      return insertIdx;
    } else {
      final physicalIdx = _shuffleOrder!.removeAt(oldIndex);
      final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
      _shuffleOrder!.insert(insertIdx, physicalIdx);

      // Adjust logical index for shuffle order changes
      if (_logicalIndex == oldIndex) {
        _logicalIndex = insertIdx;
      } else if (oldIndex < _logicalIndex && insertIdx >= _logicalIndex) {
        _logicalIndex--;
      } else if (oldIndex > _logicalIndex && insertIdx <= _logicalIndex) {
        _logicalIndex++;
      }
      _currentIndex = physicalIndex(_logicalIndex);
      _shuffledTracks = null;

      return insertIdx;
    }
  }

  bool canRemove(int index) {
    if (index < 0 || index >= _tracks.length) return false;
    return index != currentIndex;
  }

  /// Remove a track at [index].
  void remove(int index) {
    if (_shuffleOrder == null) {
      _tracks.removeAt(index);
      if (_logicalIndex > index) {
        _logicalIndex--;
        _currentIndex = _logicalIndex;
      } else if (_logicalIndex == index) {
        // Removing current track — reset index
        _logicalIndex = -1;
        _currentIndex = -1;
      }
    } else {
      final physicalIdx = _shuffleOrder![index];
      _tracks.removeAt(physicalIdx);
      _shuffleOrder!.removeAt(index);

      // Adjust any physical indices in _shuffleOrder that were after the removed physical index
      for (var i = 0; i < _shuffleOrder!.length; i++) {
        if (_shuffleOrder![i] > physicalIdx) {
          _shuffleOrder![i]--;
        }
      }

      // Adjust _currentIndex (physical)
      if (_currentIndex >= physicalIdx) {
        _currentIndex--;
      }

      // Adjust _logicalIndex
      if (index < _logicalIndex) {
        _logicalIndex--;
      }
      _shuffledTracks = null;
      _rebuildPhysicalToLogical();
    }
  }

  /// Insert [track] at [index].
  void insert(int index, AfTrack track) {
    if (_shuffleOrder == null) {
      final clamped = index.clamp(0, _tracks.length);
      _tracks.insert(clamped, track);
      if (clamped <= _logicalIndex) {
        _logicalIndex++;
        _currentIndex++;
      }
    } else {
      final clampedLogical = index.clamp(0, _shuffleOrder!.length);
      _tracks.add(track);
      final newPhysicalIndex = _tracks.length - 1;
      _shuffleOrder!.insert(clampedLogical, newPhysicalIndex);
      if (clampedLogical <= _logicalIndex) {
        _logicalIndex++;
      }
      _currentIndex = physicalIndex(_logicalIndex);
      _shuffledTracks = null;
      _rebuildPhysicalToLogical();
    }
  }

  /// Append [track] to the end of the queue.
  void append(AfTrack track) {
    _tracks.add(track);
    if (_shuffleOrder != null) {
      _shuffleOrder!.add(_tracks.length - 1);
      _rebuildPhysicalToLogical();
      _shuffledTracks = null;
    }
  }

  /// Append multiple tracks in one batch — O(n) instead of O(n²).
  ///
  /// In shuffle mode, appends all physical indices first, then rebuilds
  /// the physical→logical map once instead of per-append.
  void appendAll(List<AfTrack> tracks) {
    if (tracks.isEmpty) return;
    final startPhysical = _tracks.length;
    _tracks.addAll(tracks);
    if (_shuffleOrder != null) {
      for (var i = 0; i < tracks.length; i++) {
        _shuffleOrder!.add(startPhysical + i);
      }
      _rebuildPhysicalToLogical();
      _shuffledTracks = null;
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────

  void updateTrackFavorite(String trackId, bool isFavorite) {
    for (var i = 0; i < _tracks.length; i++) {
      if (_tracks[i].id == trackId) {
        _tracks[i] = _tracks[i].copyWith(isFavorite: isFavorite);
        break; // ponytail: IDs are unique, no reason to scan the rest
      }
    }
    _shuffledTracks = null;
  }
}
