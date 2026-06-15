import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import 'artwork_manager.dart';
import 'async_lock.dart';
import 'audio_device_manager.dart';
import 'auth_headers_manager.dart';
import 'loop_mode_manager.dart';
import 'media_session_bridge.dart';
import 'player_settings_store.dart';
import 'position_tracker.dart';
import 'queue_manager.dart';
import 'stream_prefetcher.dart';
import 'stream_url_cache.dart';
import 'spectrum_settings.dart';

part 'completed_handler.dart';
part 'queue_operations.dart';

/// Orchestrates core playback operations: play, pause, seek, skip, queue
/// loading, track transitions, prefetch, and media-session state updates.
///
/// This is an internal implementation detail of [AfPlayerService].
/// It owns the orchestration logic and mutable playback state while the
/// service provides the public API surface and stream wiring.
///
/// Queue mutations live in [QueueOperations] and completion/EOF logic
/// in [CompletedHandler] (part files of this library).
class PlaybackController {
  PlaybackController({
    required PlayerApi player,
    required AfQueueManager queueManager,
    required AfPositionTracker positionTracker,
    required AfArtworkManager artworkManager,
    required AfAudioDeviceManager audioDeviceManager,
    required StreamPrefetcher prefetcher,
    required StreamUrlCache streamUrlCache,
    required AfAsyncLock queueLock,
    required LoopModeManager loopModeManager,
    required AuthHeadersManager authHeadersManager,
    required NativeMediaSessionBridge bridge,
  }) : _player = player,
       _queueManager = queueManager,
       _positionTracker = positionTracker,
       _artworkManager = artworkManager,
       _audioDeviceManager = audioDeviceManager,
       _prefetcher = prefetcher,
       _streamUrlCache = streamUrlCache,
       _queueLock = queueLock,
       _loopModeManager = loopModeManager,
       _authHeadersManager = authHeadersManager,
       _bridge = bridge;

  final PlayerApi _player;
  final AfQueueManager _queueManager;
  final AfPositionTracker _positionTracker;
  final AfArtworkManager _artworkManager;
  final AfAudioDeviceManager _audioDeviceManager;
  final StreamPrefetcher _prefetcher;
  final StreamUrlCache _streamUrlCache;
  final AfAsyncLock _queueLock;
  final LoopModeManager _loopModeManager;
  final AuthHeadersManager _authHeadersManager;
  final NativeMediaSessionBridge _bridge;

  bool _disposed = false;

  set disposedForTesting(bool value) => _disposed = value;

  // ── Mutable playback state ───────────────────────────────────────

  String? _prefetchStartedForTrackId;
  bool _prefetchPlaylistEnabled = true;

  /// Guards against re-processing a `completed` event for the same track.
  String? _completedHandledForTrackId;

  /// Guards against re-processing a track completion via the EOF fallback.
  String? _eofFallbackHandledTrackId;

  /// The ID of the track currently loaded in the mpv player.
  String? _mpvLoadedTrackId;

  Duration? _lastPosition;
  Duration _listenedDuration = Duration.zero;

  /// Returns the accumulated continuous listen duration for the active track.
  Duration get listenedDuration => _listenedDuration;

  /// Tracks last-applied spectrum settings to avoid redundant native calls.
  SpectrumSettings? _lastSpectrumSettings;

  int _lastMediaSessionUpdateMs = 0;
  int _lastQSPositionPushMs = 0;
  bool _lastEffectivePlaying = false;
  Uri? _lastPushedArtUri;

  /// Stored from [playQueue] so [skipToQueueItem] and the completed handler
  /// can lazily resolve stream URLs when rebuilding the 2-track window.
  FutureOr<String> Function(AfTrack)? _resolveStreamUrl;

  // ── Callbacks ───────────────────────────────────────────────────

  void Function(AfTrack? track)? onTrackChanged;
  void Function(String? trackId)? onMpvLoadedTrackChanged;
  void Function(AfTrack track)? onTrackCompleted;
  void Function(AfTrack track)? onTrackSkipped;
  Future<List<AfTrack>> Function(AfTrack lastTrack)? onGetSimilarTracks;
  VoidCallback? onToggleFavorite;
  void Function(bool enabled)? onForNtimesChanged;
  void Function(Uri?)? onArtworkUpdated;
  void Function(AudioOutputState state)? onAudioOutputFailed;

  // ── Cached stream URL helpers ───────────────────────────────────

  String? _getCachedStreamUrl(String trackId) => _streamUrlCache.get(trackId);
  void _cacheStreamUrl(String trackId, String url) =>
      _streamUrlCache.put(trackId, url);

  void _clearStreamUrlCache() => _streamUrlCache.clear();

  // ── Auth header convenience ─────────────────────────────────────

  Map<String, String> get _authHeaders => _authHeadersManager.headers;

  // ── Loop mode convenience ───────────────────────────────────────

  Loop get loopMode => _loopModeManager.mode;

  // ── Track lifecycle helper ──────────────────────────────────────

  void _onTrackChangedOrRestarted() {
    _positionTracker.onTrackChanged();
    _listenedDuration = Duration.zero;
    _lastPosition = null;
    _artworkManager.persistCover(null);
  }

  // ---------------------------------------------------------------------------
  // Playback control
  // ---------------------------------------------------------------------------

  void setAuthHeaders(Map<String, String> headers) {
    _authHeadersManager.setHeaders(headers);
    _artworkManager.setAuthHeaders(headers);
  }

  Future<void> play() async {
    if (_disposed) return;
    _positionTracker.onPlay();
    try {
      await _player.play();
      _audioDeviceManager.nudge();
    } on Exception catch (e, stack) {
      afLog('audio', 'play failed', error: e, stackTrace: stack);
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    _positionTracker.onPause();
    try {
      await _player.pause();
    } on Exception catch (e, stack) {
      afLog('audio', 'pause failed', error: e, stackTrace: stack);
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _positionTracker.onStop();
    _listenedDuration = Duration.zero;
    _lastPosition = null;
    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    _eofFallbackHandledTrackId = null;
    _clearStreamUrlCache();
    try {
      await _player.stop();
    } on Exception catch (e, stack) {
      afLog('audio', 'stop failed', error: e, stackTrace: stack);
    }
  }

  Future<void> stopAndClear() async {
    if (_disposed) return;
    _positionTracker.onStop();
    _listenedDuration = Duration.zero;
    _lastPosition = null;
    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    _eofFallbackHandledTrackId = null;
    try {
      await _player.stop();
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'stop failed in stopAndClear',
        error: e,
        stackTrace: stack,
      );
    }
    _queueManager.clear();
    onTrackChanged?.call(null);
    updateMediaSession();
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    _positionTracker.onSeek(position);
    if (position == Duration.zero) {
      _listenedDuration = Duration.zero;
      _lastPosition = null;
    } else {
      _lastPosition = position;
    }
    try {
      await _player.seek(position);
      updateMediaSession();
      _audioDeviceManager.nudge();
    } on Exception catch (e, stack) {
      afLog('audio', 'seek failed', error: e, stackTrace: stack);
    }
  }

  Future<void> seekToPercent(
    double percent, {
    bool relative = false,
    bool exact = false,
  }) async {
    if (_disposed) return;
    final clamped = percent.clamp(0.0, 100.0);
    try {
      await _player.seekToPercent(clamped, relative: relative, exact: exact);
      updateMediaSession();
      _audioDeviceManager.nudge();
    } on Exception catch (e, stack) {
      afLog('audio', 'seekToPercent failed', error: e, stackTrace: stack);
    }
  }

  Future<void> revertSeek() async {
    if (_disposed) return;
    try {
      await _player.revertSeek();
      updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'revertSeek failed', error: e, stackTrace: stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Queue loading (kept here for invariant test visibility)
  // ---------------------------------------------------------------------------

  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required FutureOr<String> Function(AfTrack track) resolveStreamUrl,
    Map<String, String> streamHeaders = const <String, String>{},
  }) async {
    if (tracks.isEmpty) return;

    _resolveStreamUrl = resolveStreamUrl;
    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;
    _completedHandledForTrackId = null;
    _eofFallbackHandledTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);

    if (streamHeaders.isNotEmpty) {
      _authHeadersManager.setHeaders(streamHeaders);
      _artworkManager.setAuthHeaders(streamHeaders);
    }

    final safeIndex = startIndex.clamp(0, tracks.length - 1);
    _queueManager.replaceQueue(tracks, safeIndex);

    final startTrack = tracks[safeIndex];
    _queueManager.emitCurrentTrack(startTrack);
    onTrackChanged?.call(startTrack);
    afLog(
      'data',
      'playQueue source=live size=${tracks.length} '
          'startIndex=$safeIndex first="${startTrack.title}"',
    );

    final cachedFile = await _prefetcher.getCachedFile(startTrack.id);
    final String url;
    if (cachedFile != null) {
      url = cachedFile.uri.toString();
      afLog(
        'audio',
        'playQueue: using prefetched file for "${startTrack.title}"',
      );
    } else {
      final cachedUrl = _getCachedStreamUrl(startTrack.id);
      if (cachedUrl != null) {
        url = cachedUrl;
        afLog(
          'audio',
          'playQueue: using cached stream URL for "${startTrack.title}"',
        );
      } else {
        url = await resolveStreamUrl(startTrack);
        _cacheStreamUrl(startTrack.id, url);
      }
    }
    final medias = <Media>[
      Media(url, httpHeaders: _authHeaders.isNotEmpty ? _authHeaders : null),
    ];
    afLog(
      'aetherfin:youtube',
      'playQueue: url=${url.length > 80 ? url.substring(0, 80) : url}...',
    );

    return _queueLock.run(() async {
      try {
        _onTrackChangedOrRestarted();

        await _player.openAll(medias, index: 0, play: true);
        _mpvLoadedTrackId = startTrack.id;
        onMpvLoadedTrackChanged?.call(_mpvLoadedTrackId);

        _audioDeviceManager.nudge();
      } on Exception catch (e, stack) {
        afLog(
          'aetherfin:error',
          'playQueue failed',
          error: e,
          stackTrace: stack,
        );
        _queueManager.clear();
        _mpvLoadedTrackId = null;
        onMpvLoadedTrackChanged?.call(null);
        try {
          await _player.stop();
        } on Exception catch (err, st) {
          afLog(
            'audio',
            'stop failed on playQueue cleanup',
            error: err,
            stackTrace: st,
          );
        }
        rethrow;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Loop mode (kept here for invariant test visibility)
  // ---------------------------------------------------------------------------

  Future<void> setAfLoopMode(Loop mode) async {
    if (_disposed) return;
    return _queueLock.run(() async {
      try {
        _loopModeManager.setMode(mode);
        afLog('data', 'loopMode source=live mode=${mode.name}');
        updateMediaSession();
      } on Exception catch (e, stack) {
        afLog('audio', 'setAfLoopMode failed', error: e, stackTrace: stack);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Spectrum
  // ---------------------------------------------------------------------------

  Future<void> configureSpectrum() async {
    try {
      await _player.setSpectrum(defaultSpectrumSettings);
    } on Exception catch (e, stack) {
      afLog('audio', 'configureSpectrum failed', error: e, stackTrace: stack);
    }
  }

  Future<void> _reconfigureSpectrumOnTrackChange() async {
    if (_disposed) return;
    try {
      await Future.delayed(const Duration(milliseconds: 250));
      if (_disposed) return;
      if (_lastSpectrumSettings == defaultSpectrumSettings) return;
      await _player.setSpectrum(defaultSpectrumSettings);
      _lastSpectrumSettings = defaultSpectrumSettings;
      afLog('audio', 'spectrum re-configured after track change');
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'reconfigureSpectrumOnTrackChange failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 2-track window management
  // ---------------------------------------------------------------------------

  Future<void> _rebuildWindow(AfTrack target) async {
    if (_resolveStreamUrl == null) return;

    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;

    final cachedFile = await _prefetcher.getCachedFile(target.id);
    final String url;
    if (cachedFile != null) {
      url = cachedFile.uri.toString();
      afLog(
        'audio',
        'rebuildWindow: using prefetched file for "${target.title}"',
      );
    } else {
      final cachedUrl = _getCachedStreamUrl(target.id);
      if (cachedUrl != null) {
        url = cachedUrl;
        afLog(
          'audio',
          'rebuildWindow: using cached stream URL for "${target.title}"',
        );
      } else {
        url = await _resolveStreamUrl!(target);
        _cacheStreamUrl(target.id, url);
      }
    }

    try {
      await _player.openAll(
        [
          Media(
            url,
            httpHeaders: _authHeaders.isNotEmpty ? _authHeaders : null,
          ),
        ],
        index: 0,
        play: true,
      );
      _mpvLoadedTrackId = target.id;
      onMpvLoadedTrackChanged?.call(_mpvLoadedTrackId);
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'MPV openAll failed for track ${target.id}',
        error: e,
        stackTrace: stack,
      );
      _mpvLoadedTrackId = null;
      onMpvLoadedTrackChanged?.call(null);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Media session update
  // ---------------------------------------------------------------------------

  /// Push the current state to the OS media session and the legacy bridge.
  ///
  /// Throttled to ~100ms at the entry point so metadata construction
  /// doesn't run at 30–60 Hz from position stream events.
  void updateMediaSession() {
    if (_disposed) return;
    final track = _queueManager.currentTrack;
    if (track == null) {
      _player.setMediaSession(null);
      _bridge.clear();
      return;
    }

    final s = _player.state;
    final isQueueEnd = s.completed && _queueManager.isAtQueueEnd;
    final trackEnded =
        _player.state.playWhenReady &&
        _queueManager.isAtQueueEnd &&
        s.duration > Duration.zero &&
        _positionTracker.lastKnownPosition >= s.duration;
    final effectivePlaying = (isQueueEnd || trackEnded)
        ? false
        : (s.playing || _shouldAdvancePosition());

    final playingChanged = effectivePlaying != _lastEffectivePlaying;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!playingChanged && nowMs - _lastMediaSessionUpdateMs < 100) return;
    _lastMediaSessionUpdateMs = nowMs;
    _lastEffectivePlaying = effectivePlaying;

    final effectiveDuration = s.duration > Duration.zero
        ? s.duration
        : track.duration;

    final artUri = _artworkManager.artUri(track);
    final artPath = artUri != null && artUri.isScheme('file')
        ? artUri.toFilePath()
        : null;

    // Only notify artwork change when URI actually changed to avoid
    // unnecessary provider cascade + HomeWidgetManager.update() every 2s.
    if (artUri != _lastPushedArtUri) {
      _lastPushedArtUri = artUri;
      onArtworkUpdated?.call(artUri);
    }

    final loopModeStr = _queueManager.engine.isForNtimes
        ? 'ntimes'
        : switch (_loopModeManager.mode) {
            Loop.file => 'one',
            Loop.playlist => 'all',
            Loop.off => 'off',
          };

    final artwork = artUri != null
        ? MediaSessionArtwork.uri(artUri)
        : MediaSessionArtwork.none;

    _player.setMediaSession(
      (s.mediaSession ?? const MediaSession()).copyWith(
        title: track.title,
        artist: track.artistName,
        album: track.albumName,
        duration: effectiveDuration,
        artwork: artwork,
        isFavorite: track.isFavorite,
      ),
    );

    _bridge.pushState(
      MediaSessionState(
        playing: effectivePlaying,
        buffering: s.buffering,
        position: _positionTracker.lastKnownPosition,
        duration: effectiveDuration,
        speed: effectivePlaying ? s.rate : 0.0,
        title: track.title,
        artist: track.artistName,
        album: track.albumName,
        artPath: artPath,
        queueIndex: _queueManager.currentIndex >= 0
            ? _queueManager.currentIndex
            : null,
        queueSize: _queueManager.currentQueue.length,
        needsArtworkDownload:
            artUri == null && _artworkManager.needsRemoteArtwork(track),
        shuffleEnabled: _queueManager.isShuffleEnabled,
        loopMode: loopModeStr,
        isFavorite: track.isFavorite,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Position listener helpers (called from _bindStreams in the service)
  // ---------------------------------------------------------------------------

  void onPositionTick(Duration pos) {
    checkPrefetch(pos);
    checkEndOfTrackFallback(pos);
    final last = _lastPosition;
    _lastPosition = pos;
    if (last != null && _player.state.playing) {
      final delta = pos - last;
      if (delta > Duration.zero && delta < const Duration(milliseconds: 1200)) {
        _listenedDuration += delta;
      }
    }
    if (pos > Duration.zero) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastQSPositionPushMs > 2000) {
        _lastQSPositionPushMs = nowMs;
        updateMediaSession();
      }
    }
  }

  void notifyAudioOutputFailed() {
    onAudioOutputFailed?.call(AudioOutputState.failed);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  bool _shouldAdvancePosition() {
    if (_queueManager.currentTrack == null) return false;
    if (!_player.state.playWhenReady) return false;
    if (_player.state.completed) return false;
    if (_queueManager.isAtQueueEnd && !_player.state.playing) {
      return false;
    }
    return true;
  }

  void dispose() {
    _disposed = true;
  }
}
