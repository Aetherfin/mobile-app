import 'dart:async';

import 'package:flutter/foundation.dart'
    show VoidCallback, kDebugMode, visibleForTesting;
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../design_tokens/tokens.dart';
import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import 'artwork_manager.dart';
import 'async_lock.dart';
import 'audio_device_manager.dart';
import 'auth_headers_manager.dart';
import 'loop_mode_manager.dart';
import 'media_session_bridge.dart';
import 'playback_controller.dart';
import 'player_settings_store.dart';
import 'position_tracker.dart';
import 'queue_manager.dart';
import 'stream_prefetcher.dart';
import 'stream_url_cache.dart';

/// Re-export [AfAsyncLock] for backward compatibility.
///
/// Existing imports of `player_service.dart` that use [AfAsyncLock]
/// will continue to work without changes.
export 'async_lock.dart' show AfAsyncLock;

/// Bridges [Player] (mpv_audio_kit) with a platform-native media session
/// via [Player.setMediaSession].
///
/// Composition root that wires together focused sub-modules:
/// - [PlaybackController] — play, pause, seek, skip, queue mutations
/// - [LoopModeManager] — loop mode state and transitions
/// - [AuthHeadersManager] — auth header storage
/// - [AfQueueManager] — queue state (unchanged)
/// - [AfPositionTracker] — position polling (unchanged)
/// - [AfArtworkManager] — cover art (unchanged)
/// - [AfAudioDeviceManager] — audio device routing (unchanged)
/// - [StreamPrefetcher] — track prefetching (unchanged)
/// - [StreamUrlCache] — URL caching (unchanged)
class AfPlayerService {
  AfPlayerService() : _player = Player() {
    _positionTracker = AfPositionTracker(
      player: _player,
      shouldAdvancePosition: () => _shouldAdvancePosition,
    );
    _artworkManager = AfArtworkManager();
    _audioDeviceManager = AfAudioDeviceManager(player: _player);
    _queueManager = AfQueueManager();
    _prefetcher = StreamPrefetcher();
    _loopModeManager = LoopModeManager();
    _authHeadersManager = AuthHeadersManager();
    _queueLock = AfAsyncLock();

    _bridge = NativeMediaSessionBridge();
    _wireBridgeCallbacks(_bridge);

    _playback = PlaybackController(
      player: _player,
      queueManager: _queueManager,
      positionTracker: _positionTracker,
      artworkManager: _artworkManager,
      audioDeviceManager: _audioDeviceManager,
      prefetcher: _prefetcher,
      streamUrlCache: _streamUrlCache,
      queueLock: _queueLock,
      loopModeManager: _loopModeManager,
      authHeadersManager: _authHeadersManager,
      bridge: _bridge,
    );

    // Wire cross-module callbacks
    _artworkManager.onArtworkChanged = _playback.updateMediaSession;

    // Async setup — fire-and-forget like the original pattern.
    _init();
  }

  @visibleForTesting
  AfPlayerService.test({
    required PlayerApi player,
    NativeMediaSessionBridge? bridge,
  }) : _player = player {
    _positionTracker = AfPositionTracker(
      player: player,
      shouldAdvancePosition: () => _shouldAdvancePosition,
    );
    _artworkManager = AfArtworkManager();
    _audioDeviceManager = AfAudioDeviceManager(player: player);
    _queueManager = AfQueueManager();
    _prefetcher = StreamPrefetcher();
    _loopModeManager = LoopModeManager();
    _authHeadersManager = AuthHeadersManager();
    _queueLock = AfAsyncLock();

    if (bridge != null) {
      _bridge = bridge;
    }
    _wireBridgeCallbacks(_bridge);

    _playback = PlaybackController(
      player: player,
      queueManager: _queueManager,
      positionTracker: _positionTracker,
      artworkManager: _artworkManager,
      audioDeviceManager: _audioDeviceManager,
      prefetcher: _prefetcher,
      streamUrlCache: _streamUrlCache,
      queueLock: _queueLock,
      loopModeManager: _loopModeManager,
      authHeadersManager: _authHeadersManager,
      bridge: _bridge,
    );

    _artworkManager.onArtworkChanged = _playback.updateMediaSession;

    _wireMediaSessionCommands();

    _bindStreams();
  }

  /// Async initialization extracted from the constructor.
  ///
  /// Runs immediately after field construction. Failures are logged
  /// and do not propagate — a single failed init should not crash the app.
  Future<void> _init() async {
    unawaited(
      _player
          .setMediaSession(
            const MediaSession(
              actions: {
                MediaAction.play,
                MediaAction.pause,
                MediaAction.playPause,
                MediaAction.next,
                MediaAction.previous,
                MediaAction.seek,
                MediaAction.fastForward,
                MediaAction.rewind,
                MediaAction.setRepeatMode,
                MediaAction.setShuffle,
                MediaAction.like,
              },
              fastForwardInterval: Duration(
                seconds: 30,
              ), // ponytail: FF/RW intervals, not animation
              rewindInterval: Duration(
                seconds: 15,
              ), // ponytail: FF/RW intervals, not animation
              interruptionPolicy: InterruptionPolicy.pauseAndResume,
              appName: 'Aetherfin',
              artwork: MediaSessionArtwork.none,
            ),
          )
          .catchError((Object e, StackTrace stack) {
            _initFailed = true;
            afLog(
              'audio',
              'setMediaSession failed',
              error: e,
              stackTrace: stack,
            );
          }),
    );

    _wireMediaSessionCommands();

    try {
      final action = await _bridge.getShortcutAction();
      if (action != null) {
        _handleShortcutAction(action);
      }
    } on Exception catch (e, stack) {
      afLog('audio', 'getShortcutAction failed', error: e, stackTrace: stack);
    }

    unawaited(
      _player.setAudioDriver('aaudio').catchError((
        Object e,
        StackTrace? stack,
      ) {
        _initFailed = true;
        afLog('error', 'setAudioDriver failed', error: e, stackTrace: stack);
      }),
    );

    if (kDebugMode) {
      unawaited(
        _player.setLogLevel(LogLevel.debug).catchError((
          Object e,
          StackTrace s,
        ) {
          _initFailed = true;
          afLog('audio', 'setLogLevel failed', error: e, stackTrace: s);
        }),
      );
    }

    unawaited(
      _player
          .setAudioBuffer(
            const Duration(milliseconds: 200),
          ) // ponytail: audio buffer, not animation
          .catchError((Object e, StackTrace? stack) {
            _initFailed = true;
            afLog('error', 'setAudioBuffer failed', error: e, stackTrace: stack);
          }),
    );
    _bindStreams();
    _positionTracker.start();

    Future.delayed(AfDurations.expressive, () async {
      if (_disposed) return;
      try {
        final devices = _player.state.audioDevices;
        // Restore the user's persisted default device, or fall back to "auto".
        final savedDeviceName =
            await PlayerSettingsStore.loadDefaultAudioDevice();
        if (savedDeviceName != null) {
          final match = devices.where((d) => d.name == savedDeviceName);
          if (match.isNotEmpty) {
            await _player.setAudioDevice(match.first);
            return;
          }
        }
        final auto = devices.firstWhere(
          (d) => d.name == 'auto',
          orElse: () => _player.state.audioDevice,
        );
        await _player.setAudioDevice(auto);
      } on Exception catch (e, stack) {
        afLog(
          'audio',
          'setAudioDevice(auto) failed',
          error: e,
          stackTrace: stack,
        );
      }
    });
  }

  @visibleForTesting
  AfPositionTracker get positionTracker => _positionTracker;

  /// Exposes the artwork manager for wiring callbacks from providers.
  AfArtworkManager get artworkManager => _artworkManager;

  final PlayerApi _player;
  late final AfPositionTracker _positionTracker;
  late final AfArtworkManager _artworkManager;
  late final AfAudioDeviceManager _audioDeviceManager;
  late final AfQueueManager _queueManager;
  late final StreamPrefetcher _prefetcher;
  late final LoopModeManager _loopModeManager;
  late final AuthHeadersManager _authHeadersManager;
  late final PlaybackController _playback;
  late final AfAsyncLock _queueLock;

  final StreamUrlCache _streamUrlCache = StreamUrlCache();
  NativeMediaSessionBridge _bridge = NativeMediaSessionBridge();

  bool _disposed = false;
  double _preDuckVolume = 1.0;
  bool _initFailed = false;

  /// True if any constructor `.catchError` fired — indicates a partial init.
  bool get hasInitFailure => _initFailed;

  // ---------------------------------------------------------------------------
  // Callbacks (public — set by UI layer)
  // ---------------------------------------------------------------------------

  void Function(AfTrack? track)? get onTrackChanged => _playback.onTrackChanged;
  set onTrackChanged(void Function(AfTrack? track)? cb) =>
      _playback.onTrackChanged = cb;

  void Function(String? trackId)? get onMpvLoadedTrackChanged =>
      _playback.onMpvLoadedTrackChanged;
  set onMpvLoadedTrackChanged(void Function(String? trackId)? cb) =>
      _playback.onMpvLoadedTrackChanged = cb;

  void Function(AfTrack track)? get onTrackCompleted =>
      _playback.onTrackCompleted;
  set onTrackCompleted(void Function(AfTrack track)? cb) =>
      _playback.onTrackCompleted = cb;

  void Function(AfTrack track)? get onTrackSkipped => _playback.onTrackSkipped;
  set onTrackSkipped(void Function(AfTrack track)? cb) =>
      _playback.onTrackSkipped = cb;

  Future<List<AfTrack>> Function(AfTrack lastTrack)? get onGetSimilarTracks =>
      _playback.onGetSimilarTracks;
  set onGetSimilarTracks(
    Future<List<AfTrack>> Function(AfTrack lastTrack)? cb,
  ) => _playback.onGetSimilarTracks = cb;

  VoidCallback? get onToggleFavorite => _playback.onToggleFavorite;
  set onToggleFavorite(VoidCallback? cb) => _playback.onToggleFavorite = cb;

  void Function(bool enabled)? get onForNtimesChanged =>
      _playback.onForNtimesChanged;
  set onForNtimesChanged(void Function(bool enabled)? cb) =>
      _playback.onForNtimesChanged = cb;

  VoidCallback? onShortcutPlayFavorites;
  VoidCallback? onShortcutSearchMusic;

  void Function(Uri?)? get onArtworkUpdated => _playback.onArtworkUpdated;
  set onArtworkUpdated(void Function(Uri?)? cb) =>
      _playback.onArtworkUpdated = cb;

  void Function(AudioOutputState state)? onAudioOutputFailed;

  // ---------------------------------------------------------------------------
  // Public stream surface
  // ---------------------------------------------------------------------------

  Stream<Duration> get positionStream => _positionTracker.positionStream;
  Stream<bool> get playingStream => _player.stream.playing;
  Stream<Duration> get audioPtsStream => _player.stream.audioPts;
  Stream<double> get percentPosStream => _player.stream.percentPos;
  double get percentPos => _player.state.percentPos;
  Stream<AfTrack?> get currentTrackStream => _queueManager.currentTrackStream;
  Stream<List<AfTrack>> get queueStream => _queueManager.queueStream;
  Stream<bool> get shuffleModeStream => _queueManager.shuffleModeStream;
  Stream<Loop> get loopModeStream => _loopModeManager.stream;
  Stream<double> get speedStream => _player.stream.rate;

  Stream<List<Device>> get audioDevicesStream => _player.stream.audioDevices;
  Stream<Device> get audioDeviceStream => _player.stream.audioDevice;
  List<Device> get audioDevices => _player.state.audioDevices;
  Device get audioDevice => _player.state.audioDevice;

  Stream<MpvPlaybackState> get mpvPlaybackStateStream =>
      _player.stream.playbackState;
  Stream<bool> get bufferingStream => _player.stream.buffering;
  bool get isBuffering => _player.state.buffering;
  Stream<bool> get pausedForCacheStream => _player.stream.pausedForCache;
  bool get isPausedForCache => _player.state.pausedForCache;
  Stream<double> get bufferingPercentageStream =>
      _player.stream.bufferingPercentage;
  double get bufferingPercentage => _player.state.bufferingPercentage;

  Stream<AudioOutputState> get audioOutputStateStream =>
      _player.stream.audioOutputState;
  AudioOutputState get audioOutputState => _player.state.audioOutputState;

  Stream<Duration> get prefetchCacheDurationStream =>
      _player.stream.prefetchCacheDuration;

  Stream<double> get volumeStream => _player.stream.volume;
  double get volume => _player.state.volume;

  Stream<bool> get muteStream => _player.stream.mute;
  bool get isMuted => _player.state.mute;

  Duration get audioDelay => _audioDelay;
  Duration _audioDelay = Duration.zero;

  Stream<double?> get audioBitrateStream => _player.stream.audioBitrate;
  double? get audioBitrate => _player.state.audioBitrate;
  Stream<AudioParams> get audioParamsStream => _player.stream.audioParams;
  AudioParams get audioParams => _player.state.audioParams;
  Stream<MpvPrefetchState> get prefetchStateStream =>
      _player.stream.prefetchState;
  Stream<MpvPlayerError> get errorStream => _player.stream.error;

  Stream<Duration?> get abLoopAStream => _player.stream.abLoopA;
  Duration? get abLoopA => _player.state.abLoopA;
  Stream<Duration?> get abLoopBStream => _player.stream.abLoopB;
  Duration? get abLoopB => _player.state.abLoopB;
  Stream<int?> get remainingAbLoopsStream => _player.stream.remainingAbLoops;

  Stream<AudioEffects> get audioEffectsStream => _player.stream.audioEffects;
  AudioEffects get audioEffects => _player.state.audioEffects;

  Stream<ReplayGainSettings> get replayGainStream => _player.stream.replayGain;
  ReplayGainSettings get replayGain => _player.state.replayGain;

  Gapless get gaplessMode => Gapless.no;
  Stream<Gapless> get gaplessStream => const Stream.empty();

  bool get prefetchPlaylist => _playback.prefetchPlaylist;

  Stream<FftFrame> get spectrumStream => _player.stream.fft;

  Duration get position => _player.state.position;
  Duration get duration => _player.state.duration;
  Stream<Duration> get durationStream => _player.stream.duration;

  List<AfTrack> get currentQueue => _queueManager.currentQueue;
  int get currentIndex => _queueManager.currentIndex;
  AfTrack? get currentTrack => _queueManager.currentTrack;

  bool get isPlaying => _player.state.playing;
  bool get isCompleted => _player.state.completed;
  bool get isUserPaused => !_player.state.playWhenReady;

  bool get isShuffleEnabled => _queueManager.isShuffleEnabled;
  bool get isTailShuffle => _queueManager.isTailShuffle;
  Loop get loopMode => _loopModeManager.mode;
  double get speed => _player.state.rate;

  bool get isForNtimesMode => _queueManager.engine.isForNtimes;
  Duration get listenedDuration => _playback.listenedDuration;

  Stream<AudioParams> get audioOutParamsStream => _player.stream.audioOutParams;
  AudioParams get audioOutParams => _player.state.audioOutParams;

  // ---------------------------------------------------------------------------
  // shouldAdvancePosition (needs cross-cutting state)
  // ---------------------------------------------------------------------------

  bool get _shouldAdvancePosition {
    if (currentTrack == null) return false;
    if (!_player.state.playWhenReady) return false;
    if (_player.state.completed) return false;
    if (_queueManager.isAtQueueEnd && !_player.state.playing) {
      return false;
    }
    return true;
  }

  bool get shouldAdvancePosition => _shouldAdvancePosition;

  @visibleForTesting
  set disposedForTesting(bool value) {
    _disposed = value;
    _playback.disposedForTesting = value;
  }

  @visibleForTesting
  bool get isDisposedForTesting => _disposed;

  // ---------------------------------------------------------------------------
  // Public playback methods (delegated to PlaybackController)
  // ---------------------------------------------------------------------------

  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required FutureOr<String> Function(AfTrack track) resolveStreamUrl,
    Map<String, String> streamHeaders = const <String, String>{},
  }) => _playback.playQueue(
    tracks,
    startIndex: startIndex,
    resolveStreamUrl: resolveStreamUrl,
    streamHeaders: streamHeaders,
  );

  Future<void> play() => _playback.play();
  Future<void> pause() => _playback.pause();
  Future<void> stop() => _playback.stop();
  Future<void> stopAndClear() => _playback.stopAndClear();

  Future<void> seek(Duration position) => _playback.seek(position);

  Future<void> seekToPercent(
    double percent, {
    bool relative = false,
    bool exact = false,
  }) => _playback.seekToPercent(percent, relative: relative, exact: exact);

  Future<void> revertSeek() => _playback.revertSeek();
  Future<void> skipToNext() => _playback.skipToNext();
  Future<void> skipToPrevious() => _playback.skipToPrevious();
  Future<void> skipToQueueItem(int index) => _playback.skipToQueueItem(index);

  // ---------------------------------------------------------------------------
  // Shuffle / Loop / forNtimes (delegated)
  // ---------------------------------------------------------------------------

  Future<void> setAfShuffleTail() => _playback.setAfShuffleTail();
  Future<void> setAfShuffleMode(bool enabled) =>
      _playback.setAfShuffleMode(enabled);

  Future<void> setAfLoopMode(Loop mode) => _playback.setAfLoopMode(mode);
  void setLoopModeOffSync() => _playback.setLoopModeOffSync();

  Future<void> setAfForNtimes(bool enabled) =>
      _playback.setAfForNtimes(enabled);
  Future<void> setAfNtimesCount(int count) => _playback.setAfNtimesCount(count);

  Future<void> setAfSpeed(double speed) => _playback.setAfSpeed(speed);

  // ---------------------------------------------------------------------------
  // Queue management (delegated)
  // ---------------------------------------------------------------------------

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      _playback.reorderQueue(oldIndex, newIndex);

  Future<bool> removeFromQueue(int index) => _playback.removeFromQueue(index);

  Future<void> insertIntoQueue(
    int index,
    AfTrack track, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) => _playback.insertIntoQueue(
    index,
    track,
    resolveStreamUrl: resolveStreamUrl,
  );

  Future<void> playNext(
    AfTrack track, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) => _playback.playNext(track, resolveStreamUrl: resolveStreamUrl);

  Future<void> addToQueue(
    AfTrack track, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) => _playback.addToQueue(track, resolveStreamUrl: resolveStreamUrl);

  Future<void> appendQueue(
    List<AfTrack> tracks, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) => _playback.appendQueue(tracks, resolveStreamUrl: resolveStreamUrl);

  // ---------------------------------------------------------------------------
  // Auth headers
  // ---------------------------------------------------------------------------

  void setAuthHeaders(Map<String, String> headers) =>
      _playback.setAuthHeaders(headers);

  // ---------------------------------------------------------------------------
  // Audio hardware & routing
  // ---------------------------------------------------------------------------

  Future<void> setAudioDevice(Device device) async {
    if (_disposed) return;
    await _player.setAudioDevice(device);
    afLog('audio', 'audioDevice set to ${device.name}');
  }

  Future<void> setAudioDriver(String driver) async {
    await _player.setAudioDriver(driver);
    afLog('audio', 'audioDriver set to $driver');
  }

  Future<void> setAudioExclusive(bool enabled) async {
    if (_disposed) return;
    await _player.setAudioExclusive(enabled);
    afLog('audio', 'audioExclusive=$enabled');
    _audioDeviceManager.nudge();
  }

  Future<void> setAudioSampleRate(int rate) async {
    if (_disposed) return;
    await _player.setAudioSampleRate(rate);
    afLog('audio', 'audioSampleRate=$rate');
  }

  Future<void> setAudioFormat(Format format) async {
    if (_disposed) return;
    await _player.setAudioFormat(format);
    afLog('audio', 'audioFormat=$format');
  }

  Future<void> setAudioChannels(Channels channels) async {
    await _player.setAudioChannels(channels);
    afLog('audio', 'audioChannels=$channels');
  }

  Future<void> setAudioSpdif(Set<Spdif> codecs) async {
    await _player.setAudioSpdif(codecs);
    afLog('audio', 'audioSpdif=$codecs');
  }

  bool get audioExclusive => _player.state.audioExclusive;
  Stream<bool> get audioExclusiveStream => _player.stream.audioExclusive;
  bool get audioStreamSilence => _player.state.audioStreamSilence;
  Stream<bool> get audioStreamSilenceStream =>
      _player.stream.audioStreamSilence;
  Duration get audioBuffer => _player.state.audioBuffer;
  Stream<Duration> get audioBufferStream => _player.stream.audioBuffer;

  // ---------------------------------------------------------------------------
  // Network & caching
  // ---------------------------------------------------------------------------

  Future<void> setCache(CacheSettings settings) async {
    if (_disposed) return;
    await _player.setCache(settings);
    afLog('audio', 'cache set: mode=${settings.mode} secs=${settings.secs}');
  }

  CacheSettings get cacheSettings => _player.state.cache;
  Stream<CacheSettings> get cacheStream => _player.stream.cache;

  Future<void> setDemuxerMaxBytes(int bytes) async {
    await _player.setDemuxerMaxBytes(bytes);
    afLog('audio', 'demuxerMaxBytes=${bytes ~/ (1024 * 1024)} MiB');
  }

  Future<void> setDemuxerMaxBackBytes(int bytes) async {
    await _player.setDemuxerMaxBackBytes(bytes);
    afLog('audio', 'demuxerMaxBackBytes=${bytes ~/ (1024 * 1024)} MiB');
  }

  Future<void> setDemuxerReadaheadSecs(Duration secs) async {
    await _player.setDemuxerReadaheadSecs(secs);
    afLog('audio', 'demuxerReadaheadSecs=${secs.inSeconds}s');
  }

  Future<void> setNetworkTimeout(Duration timeout) async {
    await _player.setNetworkTimeout(timeout);
    afLog('audio', 'networkTimeout=${timeout.inSeconds}s');
  }

  Future<void> setAudioBuffer(Duration buffer) async {
    if (_disposed) return;
    await _player.setAudioBuffer(buffer);
    afLog('audio', 'audioBuffer=${buffer.inMilliseconds}ms');
  }

  Future<void> setAudioStreamSilence(bool enabled) async {
    if (_disposed) return;
    await _player.setAudioStreamSilence(enabled);
    afLog('audio', 'audioStreamSilence=$enabled');
  }

  // ---------------------------------------------------------------------------
  // Volume / Mute / Delay
  // ---------------------------------------------------------------------------

  Future<void> setVolume(double vol) async {
    await _player.setVolume(vol);
    afLog('audio', 'volume=$vol');
  }

  Future<void> setMute(bool muted) async {
    await _player.setMute(muted);
    afLog('audio', 'mute=$muted');
  }

  Future<void> setAudioDelay(Duration delay) async {
    await _player.setAudioDelay(delay);
    _audioDelay = delay;
    afLog('audio', 'audioDelay=${delay.inMilliseconds}ms');
  }

  // ---------------------------------------------------------------------------
  // DSP / Audio Effects
  // ---------------------------------------------------------------------------

  Future<void> setAudioEffects(AudioEffects effects) async {
    if (_disposed) return;
    final optimized = autoBypassFlat(effects);
    await _player.setAudioEffects(optimized);
    afLog('audio', 'audioEffects set');
  }

  Future<void> updateAudioEffects(
    AudioEffects Function(AudioEffects) mapper,
  ) async {
    await _player.updateAudioEffects((current) {
      final updated = mapper(current);
      return autoBypassFlat(updated);
    });
    afLog('audio', 'audioEffects updated');
  }

  Future<void> setReplayGain(ReplayGainSettings settings) async {
    if (_disposed) return;
    await _player.setReplayGain(settings);
    afLog('audio', 'replayGain mode=${settings.mode}');
  }

  // ---------------------------------------------------------------------------
  // Gapless / Prefetch
  // ---------------------------------------------------------------------------

  Future<void> setGapless(Gapless mode) async {
    if (_disposed) return;
    afLog('audio', 'gapless=${mode.name} (no-op)');
  }

  Future<void> setPrefetchPlaylist(bool enabled) =>
      _playback.setPrefetchPlaylist(enabled);

  // ---------------------------------------------------------------------------
  // A-B Loop
  // ---------------------------------------------------------------------------

  Future<void> setAbLoopA(Duration? position) async {
    await _player.setAbLoopA(position);
    afLog('audio', 'abLoopA=${position?.inMilliseconds}ms');
  }

  Future<void> setAbLoopB(Duration? position) async {
    await _player.setAbLoopB(position);
    afLog('audio', 'abLoopB=${position?.inMilliseconds}ms');
  }

  Future<void> setAbLoopCount(int? count) async {
    await _player.setAbLoopCount(count);
    afLog('audio', 'abLoopCount=$count');
  }

  // ---------------------------------------------------------------------------
  // Spectrum
  // ---------------------------------------------------------------------------

  Future<void> configureSpectrum() => _playback.configureSpectrum();

  // ---------------------------------------------------------------------------
  // Position
  // ---------------------------------------------------------------------------

  Future<Duration> getRawPosition() => _positionTracker.getRawPosition();
  Future<Duration> getRawDuration() => _positionTracker.getRawDuration();

  Uri? get currentArtworkUri {
    final track = _queueManager.currentTrack;
    return track != null ? _artworkManager.artUri(track) : null;
  }

  // ---------------------------------------------------------------------------
  // Queue state helpers
  // ---------------------------------------------------------------------------

  void updateTrackFavorite(String trackId, bool isFavorite) {
    _queueManager.updateTrackFavorite(trackId, isFavorite);
    _playback.updateMediaSession();
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(_subs.map((s) => s.cancel()), eagerError: false);
    _bridge.dispose();
    _positionTracker.dispose();
    _queueManager.dispose();
    _prefetcher.dispose();
    _playback.dispose();
    await _loopModeManager.dispose();
    await _player.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal stream wiring
  // ---------------------------------------------------------------------------

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  void _bindStreams() {
    _subs.add(_positionTracker.positionStream.listen(_onPositionTick));
    _subs.add(_player.stream.playing.listen(_onPlayingChanged));
    _subs.add(_player.stream.buffering.listen(_onBufferingChanged));
    _subs.add(_player.stream.audioOutputState.listen(_onAudioOutputFailed));
    _subs.add(_player.stream.completed.listen(_onCompleted));
    _subs.add(_player.stream.rate.listen(_onRateChanged));
    _subs.add(_player.stream.duration.listen(_onDurationChanged));
    _subs.add(_player.stream.coverArt.listen(_onCoverArtChanged));
    _subs.add(_player.stream.audioDevice.listen(_onAudioDeviceChanged));
  }

  // ponytail: extracted stream handlers for readability

  void _onPositionTick(Duration pos) {
    _playback.onPositionTick(pos);
  }

  void _onPlayingChanged(bool playing) {
    try {
      _playback.updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'playing handler failed', error: e, stackTrace: stack);
    }
  }

  void _onBufferingChanged(bool _) {
    _playback.updateMediaSession();
  }

  Future<void> _onAudioOutputFailed(AudioOutputState state) async {
    try {
      if (state == AudioOutputState.failed) {
        afLog('error', 'Audio output failed, attempting fallback');
        onAudioOutputFailed?.call(state);
        try {
          await _player.setAudioDriver('audiotrack');
          afLog('audio', 'Fallback to audiotrack succeeded');
        } on Exception catch (e, stack) {
          afLog(
            'audio',
            'audiotrack fallback failed, trying auto',
            error: e,
            stackTrace: stack,
          );
          try {
            await _player.setAudioDriver('auto');
            afLog('audio', 'Fallback to auto succeeded');
          } on Exception catch (e2, stack2) {
            afLog(
              'audio',
              'auto fallback also failed',
              error: e2,
              stackTrace: stack2,
            );
          }
        }
      }
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'audioOutputState handler failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  void _onCompleted(bool completed) {
    safeFireAndForget(
      () => _playback.handleCompleted(completed),
      label: 'handleCompleted',
    );
  }

  void _onRateChanged(double _) {
    _playback.updateMediaSession();
  }

  void _onDurationChanged(Duration dur) {
    if (dur > Duration.zero) {
      _playback.updateMediaSession();
    }
  }

  Future<void> _onCoverArtChanged(CoverArt? raw) async {
    try {
      try {
        await _artworkManager.persistCover(raw);
        // Also save permanently to the cover cache so artwork
        // appears in library views (not just Now Playing).
        final track = _queueManager.currentTrack;
        if (raw != null && track != null) {
          unawaited(
            _artworkManager.persistCoverToPermanentCache(track.id, raw),
          );
        }
      } on Exception catch (e, stack) {
        afLog('audio', 'persistCover failed', error: e, stackTrace: stack);
      }
      _playback.updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'coverArt handler failed', error: e, stackTrace: stack);
    }
  }

  Future<void> _onAudioDeviceChanged(Device newDevice) async {
    try {
      if (!_audioDeviceManager.isRealDeviceChange(newDevice.name)) return;
      try {
        await _audioDeviceManager.reapplyPersistedEffects();
      } on Exception catch (e, stack) {
        afLog(
          'audio',
          'reapplyPersistedEffects failed',
          error: e,
          stackTrace: stack,
        );
      }
    } on Exception catch (e, stack) {
      afLog('audio', 'audioDevice handler failed', error: e, stackTrace: stack);
    }
  }

  void _onMediaSessionCommand(dynamic command) {
    if (_disposed) return;
    switch (command) {
      case MediaSessionCommandNext():
        unawaited(_playback.skipToNext());
      case MediaSessionCommandPrevious():
        unawaited(_playback.skipToPrevious());
      case MediaSessionCommandSetShuffle(:final shuffle):
        unawaited(_playback.setAfShuffleMode(shuffle));
      case MediaSessionCommandSetRepeatMode(:final loop):
        unawaited(_playback.setAfLoopMode(loop));
      case MediaSessionCommandSetPlaybackRate(:final rate):
        unawaited(_playback.setAfSpeed(rate));
      case MediaSessionCommandLike():
        onToggleFavorite?.call();
      case MediaSessionCommandSeekBy(:final offset):
        unawaited(_playback.seek(_positionTracker.lastKnownPosition + offset));
      case MediaSessionCommandStop():
        unawaited(_playback.stop());
      case _:
        break;
    }
  }

  void _wireMediaSessionCommands() {
    _subs.add(
      _player.stream.mediaSessionCommands.listen(_onMediaSessionCommand),
    );
  }

  void _wireBridgeCallbacks(NativeMediaSessionBridge bridge) {
    bridge.onPlay = () => _playback.play();
    bridge.onPause = () => _playback.pause();
    bridge.onNext = () => unawaited(_playback.skipToNext());
    bridge.onPrevious = () => unawaited(_playback.skipToPrevious());
    bridge.onStop = () => unawaited(_playback.stop());
    bridge.onSeek = (position) => unawaited(_playback.seek(position));
    bridge.onSkipToQueueItem = (index) =>
        unawaited(_playback.skipToQueueItem(index));
    bridge.onSetShuffleMode = (shuffleMode) {
      unawaited(_playback.setAfShuffleMode(shuffleMode == 1));
    };
    bridge.onSetRepeatMode = (repeatMode) {
      final loop = switch (repeatMode) {
        1 => Loop.file,
        2 => Loop.playlist,
        _ => Loop.off,
      };
      unawaited(_playback.setAfLoopMode(loop));
    };
    bridge.onToggleShuffle = () {
      unawaited(_playback.setAfShuffleMode(!_queueManager.isShuffleEnabled));
    };
    bridge.onToggleRepeat = () {
      final nextMode = switch (_loopModeManager.mode) {
        Loop.off => Loop.playlist,
        Loop.playlist => Loop.file,
        Loop.file => Loop.off,
      };
      unawaited(_playback.setAfLoopMode(nextMode));
    };
    bridge.onToggleFavorite = () => onToggleFavorite?.call();
    bridge.onArtworkNeeded = () {
      final track = _queueManager.currentTrack;
      if (track != null) {
        unawaited(_artworkManager.downloadArtworkForNotification(track));
      }
    };
    bridge.onDuck = (volume) {
      _preDuckVolume = _player.state.volume;
      unawaited(_player.setVolume(volume * 100));
    };
    bridge.onUnduck = () {
      unawaited(_player.setVolume(_preDuckVolume));
    };
    bridge.onShortcutAction = _handleShortcutAction;
  }

  void _handleShortcutAction(String action) {
    afLog('audio', 'Handling native shortcut action: $action');
    if (action == 'play_favorites') {
      onShortcutPlayFavorites?.call();
    } else if (action == 'search_music') {
      onShortcutSearchMusic?.call();
    }
  }
}

/// Sanitise an [AudioEffects] bundle before it goes into libmpv's
/// `af` filter chain. Clamps all parameters to their valid ranges so
/// corrupted SharedPreferences data or UI bugs cannot push out-of-range
/// values to mpv.
@visibleForTesting
AudioEffects autoBypassFlat(AudioEffects fx) {
  return fx.copyWith(
    // Tone — bypass flat
    bass: fx.bass.copyWith(enabled: fx.bass.enabled && fx.bass.g.abs() > 0.001),
    treble: fx.treble.copyWith(
      enabled: fx.treble.enabled && fx.treble.g.abs() > 0.001,
    ),
    // Graphic EQ — bypass when empty
    superequalizer: fx.superequalizer.copyWith(
      enabled: fx.superequalizer.enabled && fx.superequalizer.params.isNotEmpty,
    ),
    // Compressor — clamp ranges
    acompressor: fx.acompressor.copyWith(
      threshold: fx.acompressor.threshold.clamp(-100.0, 0.0),
      ratio: fx.acompressor.ratio.clamp(1.0, 30.0),
      attack: fx.acompressor.attack.clamp(0.1, 1000.0),
      release: fx.acompressor.release.clamp(0.1, 1000.0),
    ),
    // Gate — clamp ranges
    agate: fx.agate.copyWith(
      threshold: fx.agate.threshold.clamp(-100.0, 0.0),
      ratio: fx.agate.ratio.clamp(1.0, 30.0),
      attack: fx.agate.attack.clamp(0.1, 1000.0),
      release: fx.agate.release.clamp(0.1, 1000.0),
    ),
    // Deesser — clamp 0..1
    deesser: fx.deesser.copyWith(
      f: fx.deesser.f.clamp(0.0, 1.0),
      i: fx.deesser.i.clamp(0.0, 1.0),
      m: fx.deesser.m.clamp(0.0, 1.0),
    ),
    // Rubberband — clamp pitch/tempo
    rubberband: fx.rubberband.copyWith(
      pitch: fx.rubberband.pitch.clamp(0.5, 2.0),
      tempo: fx.rubberband.tempo.clamp(0.5, 2.0),
    ),
    // Tremolo — clamp freq/depth
    tremolo: fx.tremolo.copyWith(
      f: fx.tremolo.f.clamp(0.1, 50.0),
      d: fx.tremolo.d.clamp(0.0, 1.0),
    ),
    // Vibrato — clamp freq/depth
    vibrato: fx.vibrato.copyWith(
      f: fx.vibrato.f.clamp(0.1, 50.0),
      d: fx.vibrato.d.clamp(0.0, 1.0),
    ),
  );
}
