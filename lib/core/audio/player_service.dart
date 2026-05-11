import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../jellyfin/models/items.dart';

/// Wraps `just_audio` + `audio_service` so:
///   - the OS lock screen / notification controls drive playback,
///   - `position`, `state`, and `currentTrack` are single-source streams
///     (per non-negotiable rule §4.3 — one [Stream<Duration>] feeds the
///     ring, waveform, lyric scroll, and time labels),
///   - background audio survives app backgrounding.
class AfPlayerService extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  final _trackQueue = <AfTrack>[];
  int _currentIndex = -1;
  final _trackController = StreamController<AfTrack?>.broadcast();
  final _queueController = StreamController<List<AfTrack>>.broadcast();

  /// Called whenever the active track changes (queue advance, manual
  /// skip, queue replaced). Wired by `playerServiceProvider` so the
  /// Riverpod layer can keep `currentTrackProvider` in sync and report
  /// session start/stop to Jellyfin.
  ///
  /// Player itself is Riverpod-free so it stays testable without a
  /// ProviderContainer.
  void Function(AfTrack track)? onTrackChanged;

  AfPlayerService() {
    _player.playbackEventStream.listen(
      _broadcastPlaybackEvent,
      onError: (Object e, StackTrace stack) {
        // ignore: avoid_print
        print('aetherfin:audio playbackEventStream error: $e');
        // ignore: avoid_print
        print('aetherfin:audio stack: $stack');
      },
    );
    _player.processingStateStream.listen((state) {
      // ignore: avoid_print
      print('aetherfin:audio processingState=${state.name} '
          'playing=${_player.playing} position=${_player.position.inMilliseconds}ms '
          'duration=${_player.duration?.inMilliseconds ?? "?"}ms');
    });
    _player.currentIndexStream.listen((idx) {
      if (idx == null) return;
      if (idx < 0 || idx >= _trackQueue.length) return;
      // currentIndexStream re-emits on every state change, not just on
      // index changes — without this dedupe we'd fire onTrackChanged +
      // playbackStart dozens of times for the same track and spam
      // /Sessions/Playing.
      if (idx == _currentIndex) return;
      _currentIndex = idx;
      final track = _trackQueue[idx];
      mediaItem.add(_mediaItemFor(track));
      _trackController.add(track);
      // ignore: avoid_print
      print(
        'aetherfin:data currentTrack source=live id=${track.id} '
        'title="${track.title}" index=$idx',
      );
      onTrackChanged?.call(track);
    });
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<ProcessingState> get stateStream => _player.processingStateStream;
  /// Broadcast stream of the currently-playing [AfTrack]. Emits whenever
  /// the queue index advances; emits `null` when the queue is cleared.
  Stream<AfTrack?> get currentTrackStream => _trackController.stream;
  /// Broadcast stream of the active queue — emits the same list shape the
  /// Queue screen renders so it reflects skips / replacements immediately.
  Stream<List<AfTrack>> get queueStream => _queueController.stream;
  /// Broadcast stream of just_audio's shuffle flag.
  Stream<bool> get shuffleModeStream => _player.shuffleModeEnabledStream;
  /// Broadcast stream of just_audio's loop mode (off / one / all).
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  /// Broadcast stream of the playback speed multiplier (1.0 = normal).
  Stream<double> get speedStream => _player.speedStream;
  Duration get position => _player.position;
  List<AfTrack> get currentQueue => List.unmodifiable(_trackQueue);
  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
          ? _trackQueue[_currentIndex]
          : null;
  bool get isShuffleEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;
  double get speed => _player.speed;

  /// Replace the queue with [tracks] and start playback at [startIndex].
  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required String Function(AfTrack track) resolveStreamUrl,
  }) async {
    _trackQueue
      ..clear()
      ..addAll(tracks);
    queue.add(tracks.map(_mediaItemFor).toList());
    _queueController.add(List.unmodifiable(_trackQueue));
    final sources = tracks
        .map((t) => AudioSource.uri(
              Uri.parse(resolveStreamUrl(t)),
              tag: _mediaItemFor(t),
            ))
        .toList();
    final startTrack = tracks[startIndex];
    // Pre-set _currentIndex BEFORE setAudioSource so the currentIndexStream
    // listener's dedupe (`if (idx == _currentIndex) return;`) suppresses
    // the spurious emit that fires immediately after the source is set —
    // we drive the initial onTrackChanged + mediaItem broadcast ourselves
    // below so the UI / playback reporter see the new track before audio
    // even starts loading.
    _currentIndex = startIndex;
    mediaItem.add(_mediaItemFor(startTrack));
    _trackController.add(startTrack);
    // ignore: avoid_print
    print(
      'aetherfin:data playQueue source=live size=${tracks.length} '
      'startIndex=$startIndex first="${startTrack.title}" '
      'url="${resolveStreamUrl(startTrack)}"',
    );
    onTrackChanged?.call(startTrack);
    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: startIndex,
      );
    } on Object catch (e, stack) {
      // ignore: avoid_print
      print('aetherfin:audio setAudioSource failed: $e');
      // ignore: avoid_print
      print('aetherfin:audio stack: $stack');
      rethrow;
    }
    try {
      await _player.play();
    } on Object catch (e, stack) {
      // ignore: avoid_print
      print('aetherfin:audio play() failed: $e');
      // ignore: avoid_print
      print('aetherfin:audio stack: $stack');
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  /// Toggle shuffle. just_audio reshuffles the queue order; the
  /// underlying [_trackQueue] list is left in original order — only the
  /// playback order changes. The Queue screen reflects the new order via
  /// `queueStream` (currentIndexStream still fires per-skip).
  ///
  /// Named with the `af` prefix to avoid colliding with
  /// `BaseAudioHandler.setShuffleMode(AudioServiceShuffleMode)` which the
  /// OS lock-screen calls with a different enum type.
  Future<void> setAfShuffleMode(bool enabled) async {
    if (enabled) {
      // Generate a fresh shuffle order so consecutive toggles don't
      // produce the same sequence.
      await _player.shuffle();
    }
    await _player.setShuffleModeEnabled(enabled);
    // ignore: avoid_print
    print('aetherfin:data shuffleMode source=live enabled=$enabled');
  }

  /// Set loop mode to `off`, `one`, or `all`.
  ///
  /// Named with the `af` prefix to avoid colliding with
  /// `BaseAudioHandler.setRepeatMode(AudioServiceRepeatMode)`.
  Future<void> setAfLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
    // ignore: avoid_print
    print('aetherfin:data loopMode source=live mode=${mode.name}');
  }

  /// Set playback speed multiplier (0.5–2.0 is the user-facing range).
  Future<void> setAfSpeed(double speed) async {
    await _player.setSpeed(speed);
    // ignore: avoid_print
    print('aetherfin:data playbackSpeed source=live speed=$speed');
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _trackController.close();
    await _queueController.close();
  }

  // ---------------------------------------------------------------------------

  MediaItem _mediaItemFor(AfTrack t) => MediaItem(
        id: t.id,
        album: t.albumName,
        title: t.title,
        artist: t.artistName,
        duration: t.duration,
        artUri: t.imageUrl != null ? Uri.parse(t.imageUrl!) : null,
        extras: {
          'albumId': t.albumId,
          'artistId': t.artistId,
        },
      );

  void _broadcastPlaybackEvent(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }
}
