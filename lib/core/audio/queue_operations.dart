part of 'playback_controller.dart';

/// Queue mutations extracted from [PlaybackController].
///
/// Covers: skip operations, shuffle/loop/speed settings,
/// queue reorder/insert/append/remove, and prefetch configuration.
extension QueueOperations on PlaybackController {
  // ---------------------------------------------------------------------------
  // Skip operations
  // ---------------------------------------------------------------------------

  Future<void> skipToNext() async {
    if (_disposed) return;
    if (_queueManager.engine.isAtQueueEnd &&
        _loopModeManager.mode != Loop.playlist) {
      return;
    }

    _positionTracker.onStop();
    try {
      await _player.stop();
    } on Exception catch (e) {
      afLog('audio', 'Failed to stop player during skipToNext', error: e);
    }

    final wasPlaying = _queueManager.currentTrack;
    _completedHandledForTrackId = null;
    _eofFallbackHandledTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    if (wasPlaying != null) {
      onTrackSkipped?.call(wasPlaying);
    }
    _queueManager.engine.advanceIndex();
    _queueManager.engine.resetRepeats();
    final nextTrack = _queueManager.currentTrack;
    if (nextTrack == null) {
      return;
    }

    _onTrackChangedOrRestarted();
    _queueManager.emitCurrentTrack(nextTrack);
    onTrackChanged?.call(nextTrack);
    updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    try {
      await _rebuildWindow(nextTrack);
      updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'skipToNext failed', error: e, stackTrace: stack);
    }
  }

  Future<void> skipToPrevious() async {
    if (_disposed) return;

    _positionTracker.onStop();
    try {
      await _player.stop();
    } on Exception catch (e) {
      afLog('audio', 'Failed to stop player during skipToPrevious', error: e);
    }

    final wasPlaying = _queueManager.currentTrack;
    _completedHandledForTrackId = null;
    _eofFallbackHandledTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    if (wasPlaying != null) {
      onTrackSkipped?.call(wasPlaying);
    }
    _queueManager.engine.retreatIndex();
    _queueManager.engine.resetRepeats();
    final prevTrack = _queueManager.currentTrack;
    if (prevTrack == null) {
      return;
    }

    _onTrackChangedOrRestarted();
    _queueManager.emitCurrentTrack(prevTrack);
    onTrackChanged?.call(prevTrack);
    updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    try {
      await _rebuildWindow(prevTrack);
      updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'skipToPrevious failed', error: e, stackTrace: stack);
    }
  }

  Future<void> skipToQueueItem(int index) async {
    if (_disposed) return;

    _positionTracker.onStop();
    try {
      await _player.stop();
    } on Exception catch (e) {
      afLog('audio', 'Failed to stop player during skipToQueueItem', error: e);
    }

    final wasPlaying = _queueManager.currentTrack;
    _completedHandledForTrackId = null;
    _eofFallbackHandledTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    if (wasPlaying != null) {
      onTrackSkipped?.call(wasPlaying);
    }
    _queueManager.engine.jumpTo(index);
    _queueManager.engine.resetRepeats();
    final targetTrack = _queueManager.currentTrack;
    if (targetTrack == null) {
      return;
    }

    _onTrackChangedOrRestarted();
    _queueManager.emitCurrentTrack(targetTrack);
    onTrackChanged?.call(targetTrack);
    updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    try {
      await _rebuildWindow(targetTrack);
      updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'skipToQueueItem failed', error: e, stackTrace: stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Shuffle / Loop / forNtimes
  // ---------------------------------------------------------------------------

  Future<void> setAfShuffleTail() async {
    if (_disposed) return;
    if (_queueManager.currentQueue.isEmpty) return;
    _queueManager.shuffleTail();
    afLog(
      'data',
      'shuffleTail source=live '
          'queueSize=${_queueManager.currentQueue.length}',
    );
  }

  Future<void> setAfShuffleMode(bool enabled) async {
    if (_disposed) return;
    if (_queueManager.isShuffleEnabled == enabled) return;

    await _queueLock.run(() async {
      _queueManager.setShuffle(enabled);
    });
    unawaited(PlayerSettingsStore.saveShuffleEnabled(enabled));

    afLog(
      'data',
      'shuffleMode source=live enabled=$enabled '
          'queueSize=${_queueManager.currentQueue.length} '
          'currentIndex=${_queueManager.currentIndex}',
    );
    updateMediaSession();
  }

  Future<void> setAfForNtimes(bool enabled) async {
    if (_disposed) return;
    _queueManager.engine.setForNtimes(enabled);
    onForNtimesChanged?.call(enabled);
    updateMediaSession();
    afLog(
      'data',
      'forNtimes source=live enabled=$enabled '
          'ntimesCount=${_queueManager.engine.ntimesCount}',
    );
  }

  Future<void> setAfNtimesCount(int count) async {
    if (_disposed) return;
    _queueManager.engine.setNtimesCount(count);
    afLog('data', 'forNtimesCount source=live count=$count');
  }

  void setLoopModeOffSync() => _loopModeManager.setOffSync();

  /// Set playback speed. Intentionally bypasses [_queueLock] because
  /// `setRate` is a simple mpv property setter.
  Future<void> setAfSpeed(double speed) async {
    if (_disposed) return;
    await _player.setRate(speed);
    afLog('data', 'playbackSpeed source=live speed=$speed');
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_disposed) return;
    final queueSize = _queueManager.currentQueue.length;
    if (oldIndex < 0 ||
        oldIndex >= queueSize ||
        newIndex < 0 ||
        newIndex >= queueSize) {
      afLog(
        'audio',
        'reorderQueue refused — index out of bounds: '
            'old=$oldIndex new=$newIndex size=$queueSize',
      );
      return;
    }
    if (!_queueManager.canReorder(oldIndex, newIndex)) return;

    await _queueLock.run(() async {
      _queueManager.reorder(oldIndex, newIndex);
    });
    afLog(
      'audio',
      'reorderQueue oldIndex=$oldIndex newIndex=$newIndex '
          'currentIndex=${_queueManager.currentIndex} '
          'queueSize=${_queueManager.currentQueue.length}',
    );
  }

  Future<bool> removeFromQueue(int index) async {
    if (_disposed) return false;
    final queueSize = _queueManager.currentQueue.length;
    if (index < 0 || index >= queueSize) {
      afLog(
        'audio',
        'removeFromQueue refused — index out of bounds: '
            'index=$index size=$queueSize',
      );
      return false;
    }
    if (!_queueManager.canRemove(index)) {
      afLog(
        'audio',
        'removeFromQueue refused index=$index (currently playing)',
      );
      return false;
    }

    await _queueLock.run(() async {
      _queueManager.remove(index);
    });
    afLog(
      'audio',
      'removeFromQueue index=$index '
          'currentIndex=${_queueManager.currentIndex} '
          'queueSize=${_queueManager.currentQueue.length}',
    );
    return true;
  }

  Future<void> insertIntoQueue(
    int index,
    AfTrack track, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    _resolveStreamUrl = resolveStreamUrl;
    await _queueLock.run(() async {
      _queueManager.insert(index, track);
    });
    afLog(
      'audio',
      'insertIntoQueue "${track.title}" at index=$index '
          'currentIndex=${_queueManager.currentIndex}',
    );
  }

  Future<void> playNext(
    AfTrack track, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    _resolveStreamUrl = resolveStreamUrl;
    await _queueLock.run(() async {
      _queueManager.engine.insert(
        _queueManager.currentIndex >= 0
            ? _queueManager.currentIndex + 1
            : _queueManager.currentQueue.length,
        track,
      );
      _queueManager.emitQueue();
    });
    afLog('audio', 'playNext "${track.title}"');
  }

  Future<void> addToQueue(
    AfTrack track, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    _resolveStreamUrl = resolveStreamUrl;
    await _queueLock.run(() async {
      _queueManager.engine.append(track);
      _queueManager.emitQueue();
    });
    afLog('audio', 'addToQueue "${track.title}" at end');
  }

  Future<void> appendQueue(
    List<AfTrack> tracks, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed || tracks.isEmpty) return;
    _resolveStreamUrl = resolveStreamUrl;
    await _queueLock.run(() async {
      _queueManager.appendAll(tracks);
    });
    afLog('audio', 'appendQueue added ${tracks.length} tracks at end');
  }

  // ---------------------------------------------------------------------------
  // Prefetch
  // ---------------------------------------------------------------------------

  Future<void> setPrefetchPlaylist(bool enabled) async {
    if (_disposed) return;
    _prefetchPlaylistEnabled = enabled;
    if (!enabled) {
      _prefetcher.dispose();
    }
    afLog('audio', 'prefetchPlaylist=$enabled');
  }

  bool get prefetchPlaylist => _prefetchPlaylistEnabled;

  void checkPrefetch(Duration pos) {
    if (!_prefetchPlaylistEnabled) return;
    final currentTrack = _queueManager.currentTrack;
    final nextTrack = _queueManager.engine.nextTrack;
    if (currentTrack != null && nextTrack != null) {
      final nextTrackId = nextTrack.id;

      // 1. Pre-resolve next track stream URL early in the background
      // so it is cached by the time the user skips or we start byte prefetching.
      if (_getCachedStreamUrl(nextTrackId) == null &&
          !_preResolvingTrackIds.contains(nextTrackId)) {
        _preResolvingTrackIds.add(nextTrackId);
        afLog('audio', 'Pre-resolving stream URL in background for next track: $nextTrackId');
        final resolved = _resolveStreamUrl?.call(nextTrack);
        if (resolved is Future<String>) {
          resolved.then((nextUrl) {
            _cacheStreamUrl(nextTrackId, nextUrl);
            _preResolvingTrackIds.remove(nextTrackId);
            afLog('audio', 'Pre-resolution success for $nextTrackId');
          }).catchError((Object e, StackTrace stack) {
            _preResolvingTrackIds.remove(nextTrackId);
            afLog(
              'audio',
              'Pre-resolution failed for $nextTrackId',
              error: e,
              stackTrace: stack,
            );
          });
        } else if (resolved is String) {
          _cacheStreamUrl(nextTrackId, resolved);
          _preResolvingTrackIds.remove(nextTrackId);
        }
      }

      // 2. Prefetch actual bytes of the next track near the end of the current track
      if (_prefetchStartedForTrackId != currentTrack.id) {
        final duration = _player.state.duration;
        if (duration > Duration.zero &&
            duration - pos <= const Duration(seconds: 3)) {
          _prefetchStartedForTrackId = currentTrack.id;
          final cachedUrl = _getCachedStreamUrl(nextTrackId);
          if (cachedUrl != null) {
            unawaited(
              _prefetcher.prefetch(
                cachedUrl,
                _authHeaders,
                trackId: nextTrackId,
              ),
            );
          } else {
            final resolved = _resolveStreamUrl?.call(nextTrack);
            if (resolved is Future<String>) {
              resolved
                  .then((nextUrl) {
                    _cacheStreamUrl(nextTrackId, nextUrl);
                    unawaited(
                      _prefetcher.prefetch(
                        nextUrl,
                        _authHeaders,
                        trackId: nextTrackId,
                      ),
                    );
                  })
                  .catchError((Object e, StackTrace stack) {
                    afLog(
                      'audio',
                      'prefetch URL resolution failed for $nextTrackId',
                      error: e,
                      stackTrace: stack,
                    );
                  });
            } else if (resolved is String) {
              _cacheStreamUrl(nextTrackId, resolved);
              unawaited(
                _prefetcher.prefetch(
                  resolved,
                  _authHeaders,
                  trackId: nextTrackId,
                ),
              );
            }
          }
        }
      }
    }
  }
}
