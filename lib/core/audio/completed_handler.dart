part of 'playback_controller.dart';

/// Track completion and EOF fallback logic extracted from [PlaybackController].
///
/// Handles: handleCompleted, checkEndOfTrackFallback, _advanceToNextTrack,
/// and _trimAutoplayedTracks.
extension CompletedHandler on PlaybackController {
  // ---------------------------------------------------------------------------
  // Autoplay queue cap
  // ---------------------------------------------------------------------------

  static const int _maxAutoplayQueueSize = 500;

  void _trimAutoplayedTracks() {
    final queue = _queueManager.currentQueue;
    final idx = _queueManager.currentIndex;
    if (queue.length <= _maxAutoplayQueueSize || idx <= 0) return;
    final excess = queue.length - _maxAutoplayQueueSize;
    final trimCount = excess < idx ? excess : idx - 1;
    if (trimCount <= 0) return;
    for (var i = 0; i < trimCount; i++) {
      _queueManager.remove(0);
    }
    afLog(
      'audio',
      'trimAutoplayedTracks: removed $trimCount old tracks, '
          'queueSize=${_queueManager.currentQueue.length}',
    );
  }

  // ---------------------------------------------------------------------------
  // Track advancement
  // ---------------------------------------------------------------------------

  Future<void> _advanceToNextTrack() async {
    _queueManager.engine.advanceIndex();
    _onTrackChangedOrRestarted();

    final current = _queueManager.currentTrack;
    if (current != null) {
      _queueManager.emitCurrentTrack(current);
      onTrackChanged?.call(current);
      unawaited(
        Future.microtask(() {
          try {
            onTrackCompleted?.call(current);
          } catch (e, stack) {
            afLog(
              'error',
              'onTrackCompleted microtask failed',
              error: e,
              stackTrace: stack,
            );
          }
        }),
      );
    }
    updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    if (current != null) {
      await _rebuildWindow(current);
      if (!_player.state.playing && _player.state.playWhenReady) {
        try {
          await _player.play();
        } on Exception catch (e, stack) {
          afLog(
            'audio',
            'advance: play() guard failed',
            error: e,
            stackTrace: stack,
          );
        }
      }
      updateMediaSession();
    }
  }

  // ---------------------------------------------------------------------------
  // Position-based EOF fallback detection
  // ---------------------------------------------------------------------------

  void checkEndOfTrackFallback(Duration pos) {
    final currentTrack = _queueManager.currentTrack;
    if (currentTrack == null) return;
    if (_completedHandledForTrackId == currentTrack.id) return;
    if (_eofFallbackHandledTrackId == currentTrack.id) return;

    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
    if (pos < duration - AfDurations.expressive) return;
    if (_player.state.playing) return;

    afLog(
      'audio',
      'EOF fallback triggered for track "${currentTrack.id}" '
          'pos=${pos.inMilliseconds}ms duration=${duration.inMilliseconds}ms',
    );

    unawaited(
      _queueLock.run(() async {
        if (_eofFallbackHandledTrackId == currentTrack.id) return;
        if (_completedHandledForTrackId == currentTrack.id) return;
        _eofFallbackHandledTrackId = currentTrack.id;
        await _advanceToNextTrack();
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Completed handler (extracted from _bindStreams)
  // ---------------------------------------------------------------------------

  Future<void> handleCompleted(bool completed) async {
    try {
      if (_disposed) return;
      if (!completed) return;

      final currentTrackId = _queueManager.currentTrack?.id;
      if (currentTrackId == null || _mpvLoadedTrackId != currentTrackId) {
        afLog(
          'audio',
          'completed event ignored: currentTrackId=$currentTrackId, '
              'mpvLoadedTrackId=$_mpvLoadedTrackId (mismatch or null)',
        );
        return;
      }

      if (_completedHandledForTrackId == currentTrackId) {
        afLog(
          'audio',
          'completed event ignored: already handled for '
              'track "$currentTrackId"',
        );
        return;
      }

      await _queueLock.run(() async {
        if (_disposed) return;
        if (_completedHandledForTrackId == currentTrackId) return;
        if (_eofFallbackHandledTrackId == currentTrackId) return;

        final loopAtEvent = _loopModeManager.mode;

        if (loopAtEvent == Loop.file) {
          _completedHandledForTrackId = currentTrackId;
          await _handleLoopFileCompleted();
          return;
        }

        if (loopAtEvent == Loop.off &&
            _queueManager.engine.isForNtimes &&
            _queueManager.engine.remainingRepeats > 0) {
          _completedHandledForTrackId = currentTrackId;
          await _handleForNtimesCompleted();
          return;
        }

        _completedHandledForTrackId = currentTrackId;

        if (!_queueManager.engine.isAtQueueEnd) {
          await _advanceToNextTrack();
        } else {
          final autoplayTriggered = await _handleAutoplay(loopAtEvent);
          if (!autoplayTriggered) {
            await _handleQueueEnd(loopAtEvent);
          }
        }
      });
    } on Exception catch (e, stack) {
      afLog('audio', 'completed handler failed', error: e, stackTrace: stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Per-loop-mode completed handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleLoopFileCompleted() async {
    _onTrackChangedOrRestarted();
    try {
      await _player.seek(Duration.zero);
      if (!_player.state.playing) {
        await _player.play();
      }
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Loop.file restart failed, rebuilding window',
        error: e,
        stackTrace: stack,
      );
      final track = _queueManager.currentTrack;
      if (track != null) {
        await _rebuildWindow(track);
      }
    }
    updateMediaSession();
    afLog('audio', 'Loop.file — restarted current track');
  }

  Future<void> _handleForNtimesCompleted() async {
    final playingAtEvent = _player.state.playing;
    _queueManager.engine.decrementRepeats();
    afLog(
      'audio',
      'forNtimes: restarting track, '
          '${_queueManager.engine.remainingRepeats} repeats remaining',
    );
    try {
      _onTrackChangedOrRestarted();
      await _player.seek(Duration.zero);
      if (!playingAtEvent) {
        await _player.play();
      }
    } on Exception catch (e, stack) {
      afLog('audio', 'forNtimes: seek(0) failed', error: e, stackTrace: stack);
    }
    updateMediaSession();
  }

  Future<bool> _handleAutoplay(Loop loopAtEvent) async {
    if (loopAtEvent != Loop.off || onGetSimilarTracks == null) return false;

    final lastTrack = _queueManager.currentTrack;
    if (lastTrack == null) return false;

    _trimAutoplayedTracks();
    try {
      final similar = await onGetSimilarTracks!(lastTrack);
      if (similar.isNotEmpty) {
        _queueManager.appendAll(similar);
        await _advanceToNextTrack();
        return true;
      }
    } on Exception catch (e, stack) {
      afLog('audio', 'autoplay check failed', error: e, stackTrace: stack);
    }
    return false;
  }

  Future<void> _handleQueueEnd(Loop loopAtEvent) async {
    switch (loopAtEvent) {
      case Loop.off:
        _positionTracker.onStop();
        _mpvLoadedTrackId = null;
        try {
          await _player.stop();
        } on Exception catch (e, stack) {
          afLog(
            'audio',
            'stop failed on queue completion',
            error: e,
            stackTrace: stack,
          );
        }
        _queueManager.endPlayback();
        onTrackChanged?.call(null);
        updateMediaSession();
        afLog('audio', 'queue end, auto-stop (loop=off)');
      case Loop.playlist:
        _queueManager.engine.jumpTo(0);
        _onTrackChangedOrRestarted();
        final track = _queueManager.currentTrack;
        if (track != null) {
          await _rebuildWindow(track);
        }
        updateMediaSession();
        afLog('audio', 'queue end, looping playlist');
      case Loop.file:
        _onTrackChangedOrRestarted();
        try {
          await _player.seek(Duration.zero);
          if (!_player.state.playing) {
            await _player.play();
          }
        } on Exception catch (e, stack) {
          afLog(
            'audio',
            'Loop.file fallback restart failed',
            error: e,
            stackTrace: stack,
          );
        }
        afLog('audio', 'queue end, loop=file — restarted (fallback)');
    }
  }
}
