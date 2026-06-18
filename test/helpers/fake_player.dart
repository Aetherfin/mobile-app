// ignore_for_file: close_sinks
// StreamControllers are intentionally kept alive for the test lifecycle
// and closed by the caller via StreamControllers.dispose() in tearDown.

import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Mock implementation of [PlayerApi] for use in playback integration tests.
///
/// Uses mocktail's [Mock] to satisfy [PlayerApi] via `noSuchMethod`.
/// The `stream` property returns a [MockPlayerStream] with stubbable
/// typed stream getters backed by broadcast [StreamController]s.
class MockPlayer extends Mock implements PlayerApi {
  // Convenience — no custom members needed, mocktail handles everything.
}

/// Mock implementation of [PlayerStream].
///
/// [PlayerStream] is NOT marked `final` in mpv_audio_kit 0.1.3, so mocktail
/// can implement it directly. Each stream property is stubbed via `when()`
/// in the test setup.
class MockPlayerStream extends Mock implements PlayerStream {}

/// Creates a fully-wired [MockPlayer] with stream controllers.
///
/// Returns a record containing:
/// - `player`: the mock player, with all required stream properties stubbed
/// - `playing`: [StreamController] to push `playing` events
/// - `completed`: [StreamController] to push `completed` events
/// - `playlist`: [StreamController] to push [Playlist] events
/// - `loop`: [StreamController] to push [Loop] changes
/// - `position`: [StreamController] to push position [Duration] updates
/// - `rate`: [StreamController] for playback speed changes
/// - `buffering`: [StreamController] for buffering state
///
/// Usage:
/// ```dart
/// final (player, ctrls) = createMockPlayer();
/// ctrls.playing.add(true);
/// ctrls.completed.add(false);
/// ```
({MockPlayer player, StreamControllers ctrls}) createMockPlayer() {
  final player = MockPlayer();
  final stream = MockPlayerStream();

  final playingCtrl = StreamController<bool>.broadcast();
  final completedCtrl = StreamController<bool>.broadcast();
  final playlistCtrl = StreamController<Playlist>.broadcast();
  final positionCtrl = StreamController<Duration>.broadcast();
  final rateCtrl = StreamController<double>.broadcast();
  final loopCtrl = StreamController<Loop>.broadcast();
  final bufferingCtrl = StreamController<bool>.broadcast();
  final pausedForCacheCtrl = StreamController<bool>.broadcast();
  final shuffleCtrl = StreamController<bool>.broadcast();
  final coverArtCtrl = StreamController<CoverArt?>.broadcast();
  final audioDeviceCtrl = StreamController<Device>.broadcast();
  final audioDevicesCtrl = StreamController<List<Device>>.broadcast();
  final audioOutputStateCtrl = StreamController<AudioOutputState>.broadcast();
  final durationCtrl = StreamController<Duration>.broadcast();
  final mediaSessionCommandsCtrl =
      StreamController<MediaSessionCommand>.broadcast();
  final volumeCtrl = StreamController<double>.broadcast();
  final muteCtrl = StreamController<bool>.broadcast();
  final audioPtsCtrl = StreamController<Duration>.broadcast();
  final percentPosCtrl = StreamController<double>.broadcast();
  final playbackStateCtrl = StreamController<MpvPlaybackState>.broadcast();
  final bufferingPercentageCtrl = StreamController<double>.broadcast();
  final prefetchCacheDurationCtrl = StreamController<Duration>.broadcast();
  final audioEffectsCtrl = StreamController<AudioEffects>.broadcast();
  final audioParamsCtrl = StreamController<AudioParams>.broadcast();
  final audioOutParamsCtrl = StreamController<AudioParams>.broadcast();
  final audioBitrateCtrl = StreamController<double?>.broadcast();
  final replayGainCtrl = StreamController<ReplayGainSettings>.broadcast();
  final cacheCtrl = StreamController<CacheSettings>.broadcast();
  final audioExclusiveCtrl = StreamController<bool>.broadcast();
  final audioStreamSilenceCtrl = StreamController<bool>.broadcast();
  final audioBufferCtrl = StreamController<Duration>.broadcast();
  final fftCtrl = StreamController<FftFrame>.broadcast();
  final errorCtrl = StreamController<MpvPlayerError>.broadcast();
  final abLoopACtrl = StreamController<Duration?>.broadcast();
  final abLoopBCtrl = StreamController<Duration?>.broadcast();
  final remainingAbLoopsCtrl = StreamController<int?>.broadcast();
  final prefetchStateCtrl = StreamController<MpvPrefetchState>.broadcast();

  // Stub player.stream to return our MockPlayerStream
  when(() => player.stream).thenReturn(stream);

  // Stub individual stream properties on the mock stream
  when(() => stream.playing).thenAnswer((_) => playingCtrl.stream);
  when(() => stream.duration).thenAnswer((_) => durationCtrl.stream);
  when(() => stream.completed).thenAnswer((_) => completedCtrl.stream);
  when(() => stream.playlist).thenAnswer((_) => playlistCtrl.stream);
  when(() => stream.position).thenAnswer((_) => positionCtrl.stream);
  when(() => stream.rate).thenAnswer((_) => rateCtrl.stream);
  when(() => stream.loop).thenAnswer((_) => loopCtrl.stream);
  when(() => stream.buffering).thenAnswer((_) => bufferingCtrl.stream);
  when(
    () => stream.pausedForCache,
  ).thenAnswer((_) => pausedForCacheCtrl.stream);
  when(() => stream.shuffle).thenAnswer((_) => shuffleCtrl.stream);
  when(() => stream.coverArt).thenAnswer((_) => coverArtCtrl.stream);
  when(() => stream.audioDevice).thenAnswer((_) => audioDeviceCtrl.stream);
  when(() => stream.audioDevices).thenAnswer((_) => audioDevicesCtrl.stream);
  when(
    () => stream.audioOutputState,
  ).thenAnswer((_) => audioOutputStateCtrl.stream);
  when(
    () => stream.mediaSessionCommands,
  ).thenAnswer((_) => mediaSessionCommandsCtrl.stream);
  when(() => stream.volume).thenAnswer((_) => volumeCtrl.stream);
  when(() => stream.mute).thenAnswer((_) => muteCtrl.stream);
  when(() => stream.audioPts).thenAnswer((_) => audioPtsCtrl.stream);
  when(() => stream.percentPos).thenAnswer((_) => percentPosCtrl.stream);
  when(() => stream.playbackState).thenAnswer((_) => playbackStateCtrl.stream);
  when(
    () => stream.bufferingPercentage,
  ).thenAnswer((_) => bufferingPercentageCtrl.stream);
  when(
    () => stream.prefetchCacheDuration,
  ).thenAnswer((_) => prefetchCacheDurationCtrl.stream);
  when(() => stream.audioEffects).thenAnswer((_) => audioEffectsCtrl.stream);
  when(() => stream.audioParams).thenAnswer((_) => audioParamsCtrl.stream);
  when(
    () => stream.audioOutParams,
  ).thenAnswer((_) => audioOutParamsCtrl.stream);
  when(() => stream.audioBitrate).thenAnswer((_) => audioBitrateCtrl.stream);
  when(() => stream.replayGain).thenAnswer((_) => replayGainCtrl.stream);
  when(() => stream.cache).thenAnswer((_) => cacheCtrl.stream);
  when(
    () => stream.audioExclusive,
  ).thenAnswer((_) => audioExclusiveCtrl.stream);
  when(
    () => stream.audioStreamSilence,
  ).thenAnswer((_) => audioStreamSilenceCtrl.stream);
  when(() => stream.audioBuffer).thenAnswer((_) => audioBufferCtrl.stream);
  when(() => stream.fft).thenAnswer((_) => fftCtrl.stream);
  when(() => stream.error).thenAnswer((_) => errorCtrl.stream);
  when(() => stream.abLoopA).thenAnswer((_) => abLoopACtrl.stream);
  when(() => stream.abLoopB).thenAnswer((_) => abLoopBCtrl.stream);
  when(
    () => stream.remainingAbLoops,
  ).thenAnswer((_) => remainingAbLoopsCtrl.stream);
  when(() => stream.prefetchState).thenAnswer((_) => prefetchStateCtrl.stream);

  // Stub default state (override in each test as needed)
  when(() => player.state).thenReturn(const PlayerState());

  // Stub no-op methods that get called during playQueue
  when(() => player.setAudioDriver(any())).thenAnswer((_) async {});
  when(() => player.setAudioBuffer(any())).thenAnswer((_) async {});
  when(() => player.setAudioDevice(any())).thenAnswer((_) async {});
  when(() => player.setShuffle(any())).thenAnswer((_) async {});
  when(() => player.setLoop(any())).thenAnswer((_) async {});
  when(() => player.setRate(any())).thenAnswer((_) async {});
  when(() => player.setGapless(any())).thenAnswer((_) async {});
  when(() => player.setPrefetchPlaylist(any())).thenAnswer((_) async {});
  when(() => player.setSpectrum(any())).thenAnswer((_) async {});
  when(() => player.setMediaSession(any())).thenAnswer((_) async {});
  when(() => player.sendRawCommand(any())).thenAnswer((_) async {});
  when(() => player.getRawProperty(any())).thenAnswer((_) async => null);
  when(() => player.getRawPropertyNode(any())).thenAnswer((_) async => null);

  // Playback control stubs (override in specific tests)
  when(player.play).thenAnswer((_) async {});
  when(player.pause).thenAnswer((_) async {});
  when(player.stop).thenAnswer((_) async {});
  when(() => player.seek(any())).thenAnswer((_) async {});
  when(player.next).thenAnswer((_) async {});
  when(player.previous).thenAnswer((_) async {});
  when(() => player.jump(any())).thenAnswer((_) async {});
  when(
    () => player.open(any(), play: any(named: 'play')),
  ).thenAnswer((_) async {});
  when(
    () => player.openAll(
      any(),
      index: any(named: 'index'),
      play: any(named: 'play'),
    ),
  ).thenAnswer((_) async {});
  when(() => player.add(any())).thenAnswer((_) async {});
  when(player.dispose).thenAnswer((_) async {});

  final ctrls = StreamControllers(
    playing: playingCtrl,
    completed: completedCtrl,
    playlist: playlistCtrl,
    position: positionCtrl,
    rate: rateCtrl,
    loop: loopCtrl,
    buffering: bufferingCtrl,
    pausedForCache: pausedForCacheCtrl,
    duration: durationCtrl,
    shuffle: shuffleCtrl,
    coverArt: coverArtCtrl,
    audioDevice: audioDeviceCtrl,
    audioDevices: audioDevicesCtrl,
    audioOutputState: audioOutputStateCtrl,
    mediaSessionCommands: mediaSessionCommandsCtrl,
  );

  return (player: player, ctrls: ctrls);
}

/// Typed container for all stream controllers created by [createMockPlayer].
class StreamControllers {
  const StreamControllers({
    required this.playing,
    required this.completed,
    required this.playlist,
    required this.position,
    required this.rate,
    required this.loop,
    required this.buffering,
    required this.pausedForCache,
    required this.duration,
    required this.shuffle,
    required this.coverArt,
    required this.audioDevice,
    required this.audioDevices,
    required this.audioOutputState,
    required this.mediaSessionCommands,
  });
  final StreamController<bool> playing;
  final StreamController<bool> completed;
  final StreamController<Playlist> playlist;
  final StreamController<Duration> position;
  final StreamController<double> rate;
  final StreamController<Loop> loop;
  final StreamController<bool> buffering;
  final StreamController<bool> pausedForCache;
  final StreamController<Duration> duration;
  final StreamController<bool> shuffle;
  final StreamController<CoverArt?> coverArt;
  final StreamController<Device> audioDevice;
  final StreamController<List<Device>> audioDevices;
  final StreamController<AudioOutputState> audioOutputState;
  final StreamController<MediaSessionCommand> mediaSessionCommands;

  /// Close all controllers. Call in `tearDown`.
  void dispose() {
    playing.close();
    completed.close();
    playlist.close();
    position.close();
    rate.close();
    loop.close();
    buffering.close();
    pausedForCache.close();
    duration.close();
    shuffle.close();
    coverArt.close();
    audioDevice.close();
    audioDevices.close();
    audioOutputState.close();
  }
}
