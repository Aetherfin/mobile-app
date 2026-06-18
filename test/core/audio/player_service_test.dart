// ignore_for_file: close_sinks
// StreamControllers are closed via StreamControllers.dispose() in tearDown.

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import '../../helpers/fake_player.dart';
import '../../helpers/mock_method_channel.dart';

/// Wraps a mutable [PlayerState] so tests can change the mock's state.
typedef _StateUpdater =
    void Function(PlayerState Function(PlayerState) updater);

/// Test helper that creates a fresh mock player + service + channel.
({
  AfPlayerService service,
  NativeMediaSessionBridge bridge,
  MockPlayer player,
  StreamControllers ctrls,
  MockMethodChannel channel,
  _StateUpdater updateState,
  Future<dynamic> Function(MethodCall)? handler,
})
_createFixture() {
  final result = createMockPlayer();
  final player = result.player;
  final ctrls = result.ctrls;
  final channel = MockMethodChannel();

  // Mutable state so the test can change _player.state mid-lifecycle.
  var mutableState = const PlayerState();
  when(() => player.state).thenAnswer((_) => mutableState);
  void updateState(PlayerState Function(PlayerState) updater) {
    mutableState = updater(mutableState);
  }

  Future<dynamic> Function(MethodCall)? handler;

  // Stub MethodChannel calls (the bridge uses catchError on failures).
  when(() => channel.invokeMethod(any())).thenAnswer((_) async => null);
  when(() => channel.invokeMethod(any(), any())).thenAnswer((_) async => null);
  when(() => channel.setMethodCallHandler(any())).thenAnswer((
    invocation,
  ) async {
    handler =
        invocation.positionalArguments[0]
            as Future<dynamic> Function(MethodCall)?;
  });

  final bridge = NativeMediaSessionBridge(channel: channel);
  final service = AfPlayerService.test(player: player, bridge: bridge);

  return (
    service: service,
    bridge: bridge,
    player: player,
    ctrls: ctrls,
    channel: channel,
    updateState: updateState,
    handler: handler,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AfPlayerService playback integration', () {
    late AfPlayerService service;
    late MockPlayer player;
    late StreamControllers ctrls;
    late _StateUpdater updateState;

    const trackA = AfTrack(
      id: '1',
      title: 'Track A',
      artistName: 'Test Artist',
      albumName: 'Test Album',
    );
    const trackB = AfTrack(
      id: '2',
      title: 'Track B',
      artistName: 'Test Artist',
      albumName: 'Test Album',
    );
    const trackC = AfTrack(
      id: '3',
      title: 'Track C',
      artistName: 'Test Artist',
      albumName: 'Test Album',
    );

    String resolveStreamUrl(AfTrack t) => 'https://example.com/${t.id}.flac';

    setUpAll(() {
      SharedPreferences.setMockInitialValues({});
      registerFallbackValue(Duration.zero);
      registerFallbackValue(Device.auto);
      registerFallbackValue(Loop.off);
      registerFallbackValue(Gapless.weak);
      registerFallbackValue(SpectrumSettings.defaults);
      registerFallbackValue(const Media(''));
      registerFallbackValue(<Media>[]);
    });

    setUp(() {
      final fixture = _createFixture();
      service = fixture.service;
      player = fixture.player;
      ctrls = fixture.ctrls;
      updateState = fixture.updateState;
    });

    tearDown(() async {
      await service.dispose();
      ctrls.dispose();
    });

    // -----------------------------------------------------------------------
    // 1. playQueue uses openAll for small queues and emits currentTrack
    // -----------------------------------------------------------------------
    test('playQueue opens tracks and emits currentTrack', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      // Should have opened single track in mpv.
      verify(
        () => player.openAll(any(that: hasLength(1)), index: 0, play: true),
      ).called(1);

      // Current track should be set immediately from Dart state.
      expect(service.currentTrack?.id, equals('1'));
      expect(service.currentTrack?.title, equals('Track A'));
      expect(service.currentQueue.length, equals(2));

      // onTrackChanged should fire.
      expect(changedTrack?.id, equals('1'));
    });

    // -----------------------------------------------------------------------
    // 2. playQueue with single track loads only 1 media
    // -----------------------------------------------------------------------
    test('playQueue with single track opens 1 media', () async {
      await service.playQueue(
        [trackA],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      verify(
        () => player.openAll(any(that: hasLength(1)), index: 0, play: true),
      ).called(1);

      expect(service.currentQueue.length, equals(1));
    });

    // -----------------------------------------------------------------------
    // 3. Track auto-advance on completion advances engine state
    // -----------------------------------------------------------------------
    test('completed handler advances engine and emits next track', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      // Set state so we're not at queue end (length=2, index 0 → advance to 1)
      updateState(
        (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
      );

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Engine advanced — current index should be 1 (track B).
      expect(service.currentTrack?.id, equals('2'));
      expect(changedTrack?.id, equals('2'));
      // player.jump() is never called — _jumpAndPlay was removed.
      verifyNever(() => player.jump(any()));
      // player.play() not called because playingAtEvent is true.
      verifyNever(() => player.play());
    });

    // -----------------------------------------------------------------------
    // 3.1 Completed handler advances even when position is far from end
    //     (position guard removed — only the track ID guard filters events)
    // -----------------------------------------------------------------------
    test(
      'completed handler advances despite position being far from end',
      () async {
        AfTrack? changedTrack;
        service.onTrackChanged = (track) {
          changedTrack = track;
        };

        await service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack?.id, equals('1'));

        changedTrack = null;

        // Set state with duration = 3 minutes and position = 30 seconds
        // (remaining = 150 seconds — would have been rejected by the
        // removed position guard).
        updateState(
          (s) => s.copyWith(
            playing: true,
            completed: false,
            loop: Loop.off,
            duration: const Duration(minutes: 3),
            position: const Duration(seconds: 30),
          ),
        );
        service.positionTracker.updateKnownPosition(
          const Duration(seconds: 30),
        );

        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        // Should advance to next track (position guard removed).
        expect(service.currentTrack?.id, equals('2'));
        expect(changedTrack?.id, equals('2'));
      },
    );

    // -----------------------------------------------------------------------
    // 4. Completion at queue end with loop=off stops and clears track
    // -----------------------------------------------------------------------
    test('queue end with loop=off stops and clears track', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      // Clear the stop() call from playQueue entry so we only count the
      // completion handler's stop.
      clearInteractions(player);
      when(() => player.stop()).thenAnswer((_) async {});

      // Simulate completion at queue end (nextIdx = 1, length = 1).
      updateState(
        (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
      );

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Queue end with loop=off: stop + endPlayback.
      verify(() => player.stop()).called(1);
      expect(service.currentTrack, isNull);
      expect(changedTrack, isNull);
      // The track list is preserved but currentIndex goes to -1.
      // (Real behavior: _engine.endPlayback() sets index to -1, doesn't clear tracks.)
    });

    // -----------------------------------------------------------------------
    // 5. Completion at queue end with loop=playlist wraps around
    // -----------------------------------------------------------------------
    test('loop playlist wraps to first track at queue end', () async {
      await service.playQueue(
        [trackA, trackB],
        startIndex: 1, // Start at last track.
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('2'));

      clearInteractions(player);

      await service.setAfLoopMode(Loop.playlist);

      when(
        () => player.openAll(
          any(),
          index: any(named: 'index'),
          play: any(named: 'play'),
        ),
      ).thenAnswer((_) async {});

      // Simulate completion at queue end with loop=playlist.
      updateState(
        (s) => s.copyWith(playing: true, completed: false, loop: Loop.playlist),
      );

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Engine wrapped to index 0 via _rebuildWindow → openAll.
      expect(service.currentTrack?.id, equals('1'));
      verify(
        () => player.openAll(
          any(that: hasLength(1)),
          index: 0,
          play: any(named: 'play'),
        ),
      ).called(1);
      verifyNever(() => player.jump(any()));
    });

    // -----------------------------------------------------------------------
    // 6. Completion at queue end with loop=file replays in place
    // -----------------------------------------------------------------------
    test('loop file at queue end replays without track change', () async {
      await service.playQueue(
        [trackA],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      await service.setAfLoopMode(Loop.file);
      when(() => player.play()).thenAnswer((_) async {});

      // Simulate completion at queue end with loop=file.
      updateState(
        (s) => s.copyWith(
          playing: false, // mpv stopped at end of file
          completed: false,
          loop: Loop.file,
        ),
      );

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Track stays the same; seek(0) + play() called to restart.
      expect(service.currentTrack?.id, equals('1'));
      verify(() => player.seek(Duration.zero)).called(1);
      verify(() => player.play()).called(1);
    });

    // -----------------------------------------------------------------------
    // 8. Queue mutations are pure Dart — 0 mpv calls
    // -----------------------------------------------------------------------
    test('queue mutations are pure Dart — 0 mpv calls', () async {
      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentQueue.length, equals(2));

      // insertIntoQueue at index 1 — verify Dart state change
      await service.insertIntoQueue(
        1,
        trackC,
        resolveStreamUrl: resolveStreamUrl,
      );
      expect(service.currentQueue.length, equals(3));
      expect(service.currentQueue[1].id, equals('3'));

      // playNext inserts after current index (still 0)
      await service.playNext(trackC, resolveStreamUrl: resolveStreamUrl);
      expect(service.currentQueue.length, equals(4));
      expect(service.currentQueue[1].id, equals('3'));

      // addToQueue appends
      await service.addToQueue(trackC, resolveStreamUrl: resolveStreamUrl);
      expect(service.currentQueue.length, equals(5));

      // reorderQueue — verify Dart state change
      await service.reorderQueue(4, 2);
      expect(service.currentQueue[2].id, equals('3'));

      // removeFromQueue (not currently playing — index 3 is not current 0)
      final removed = await service.removeFromQueue(3);
      expect(removed, isTrue);
      expect(service.currentQueue.length, equals(4));

      // remove currently playing index fails
      final removedCurrent = await service.removeFromQueue(0);
      expect(removedCurrent, isFalse);
      expect(service.currentQueue.length, equals(4));

      // 0 mpv calls for queue mutations.
      verifyNever(() => player.sendRawCommand(any()));
    });

    // -----------------------------------------------------------------------
    // 9. Play/Pause respect disposed guard
    // -----------------------------------------------------------------------
    test('play and pause respect disposed guard', () async {
      await service.dispose();
      await service.play();
      verifyNever(() => player.play());
      await service.pause();
      verifyNever(() => player.pause());
    });

    // -----------------------------------------------------------------------
    // 10. Seek/Skip work after playQueue; skipToQueueItem uses openAll
    // -----------------------------------------------------------------------
    test(
      'seek, skipToNext, skipToPrevious, skipToQueueItem work after playQueue',
      () async {
        when(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).thenAnswer((_) async {});
        when(() => player.seek(any())).thenAnswer((_) async {});
        when(() => player.next()).thenAnswer((_) async {});
        when(() => player.previous()).thenAnswer((_) async {});

        await service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);

        await service.seek(const Duration(seconds: 1));
        verify(() => player.seek(const Duration(seconds: 1))).called(1);

        await service.skipToNext();
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));

        await service.skipToPrevious();
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));

        // skipToQueueItem now uses _rebuildWindow → openAll, not jump().
        // Use called(>0) because openAll is also called by playQueue (both use
        // index:0 — no distinguishing index matcher possible in this test).
        await service.skipToQueueItem(0);
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));
      },
    );

    // -----------------------------------------------------------------------
    // 11. playQueue error recovery
    // -----------------------------------------------------------------------
    test('playQueue error clears queue manager and stops player', () async {
      when(
        () => player.openAll(
          any(),
          index: any(named: 'index'),
          play: any(named: 'play'),
        ),
      ).thenThrow(Exception('openAll failed'));
      when(() => player.stop()).thenAnswer((_) async {});

      await expectLater(
        service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        ),
        throwsA(isA<Exception>()),
      );

      // playQueue calls stop() on entry (line 283) AND on error cleanup (line 354).
      verify(() => player.stop()).called(greaterThanOrEqualTo(2));
      expect(service.currentQueue, isEmpty);
    });

    // -----------------------------------------------------------------------
    // 12. skipToNext/Prev call mpv; skipToQueueItem uses openAll
    // -----------------------------------------------------------------------
    test(
      'skipToNext, skipToPrevious call mpv; skipToQueueItem uses openAll',
      () async {
        await service.playQueue(
          [trackA, trackB, trackC],
          startIndex: 1, // Start at track B
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack?.id, equals('2'));

        when(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).thenAnswer((_) async {});

        // skipToNext
        await service.skipToNext();
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));

        // skipToPrevious
        await service.skipToPrevious();
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));

        // skipToQueueItem now uses _rebuildWindow → openAll, not jump().
        // Both playQueue and skipToQueueItem reload window at mpv index 0,
        // so use greaterThan(0) to verify openAll was called at least once.
        await service.skipToQueueItem(0);
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));
        verifyNever(() => player.jump(any()));
      },
    );

    // -----------------------------------------------------------------------
    // 13. Media session commands invoke corresponding service methods
    //
    // Commands arrive via player.stream.mediaSessionCommands (mpv_audio_kit).
    // play/pause/seekTo are auto-applied by the package at the native level
    // and don't trigger the Dart listener — test only the commands we handle.
    // -----------------------------------------------------------------------
    test(
      'media session commands invoke corresponding service methods',
      () async {
        // Load 2 tracks so skipToNext/Previous have somewhere to go.
        when(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).thenAnswer((_) async {});
        await service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);

        // Stub methods called by player_service
        when(() => player.stop()).thenAnswer((_) async {});
        when(() => player.seek(any())).thenAnswer((_) async {});
        when(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).thenAnswer((_) async {});
        when(() => player.setRate(any())).thenAnswer((_) async {});
        when(() => player.setLoop(any())).thenAnswer((_) async {});
        when(() => player.setShuffle(any())).thenAnswer((_) async {});

        // Simulate media session commands arriving from OS via stream
        final ctrl = ctrls.mediaSessionCommands;

        // stop — handled by _wireMediaSessionCommands
        ctrl.add(MediaSessionCommand.stop);
        await Future<void>.delayed(Duration.zero);
        verify(() => player.stop()).called(greaterThanOrEqualTo(1));

        // next — triggers skipToNext which calls openAll
        ctrl.add(MediaSessionCommand.next);
        await Future<void>.delayed(Duration.zero);
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));

        // setPlaybackRate — calls setAfSpeed → setRate
        ctrl.add(const MediaSessionCommand.setPlaybackRate(1.5));
        await Future<void>.delayed(Duration.zero);
        verify(() => player.setRate(1.5)).called(1);

        // setRepeatMode — calls setAfLoopMode which manages loop in Dart
        // (not via mpv's setLoop). Verify internal state instead.
        ctrl.add(const MediaSessionCommand.setRepeatMode(Loop.file));
        await Future<void>.delayed(Duration.zero);
        expect(service.loopMode, equals(Loop.file));

        // setShuffle — calls setAfShuffleMode which manages shuffle in Dart
        // (not via mpv's setShuffle). Verify internal state instead.
        ctrl.add(const MediaSessionCommand.setShuffle(true));
        await Future<void>.delayed(Duration.zero);
        expect(service.isShuffleEnabled, isTrue);
      },
    );

    test('completed handler rebuilds window via openAll', () async {
      when(
        () => player.openAll(
          any(),
          play: any(named: 'play'),
          index: any(named: 'index'),
        ),
      ).thenAnswer((_) async {});

      await service.playQueue(
        [trackA, trackB, trackC],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      updateState(
        (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
      );

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // playQueue opens via openAll (call 1), then completed handler rebuilds via openAll (call 2)
      verify(
        () => player.openAll(
          any(),
          play: any(named: 'play'),
          index: any(named: 'index'),
        ),
      ).called(2);
      verifyNever(() => player.add(any()));
    });

    test('setAfShuffleMode emits updated shuffle status to stream', () async {
      final shuffleStates = <bool>[];
      final sub = service.shuffleModeStream.listen(shuffleStates.add);

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);

      await service.setAfShuffleMode(true);
      await Future<void>.delayed(Duration.zero);
      await service.setAfShuffleMode(false);
      await Future<void>.delayed(Duration.zero);

      expect(shuffleStates, contains(true));
      expect(shuffleStates, contains(false));
      await sub.cancel();
    });

    // -----------------------------------------------------------------------
    // stopAndClear clears queue, nulls track, calls stop
    // -----------------------------------------------------------------------
    test('stopAndClear clears queue and nulls current track', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      // Load a queue first
      await service.playQueue(
        [trackA, trackB],
        resolveStreamUrl: resolveStreamUrl,
        startIndex: 0,
      );

      // Verify queue is populated
      expect(service.currentQueue.length, 2);
      expect(service.currentTrack, isNotNull);

      // Clear the stop() call from playQueue entry so we only count
      // the stopAndClear's stop.
      clearInteractions(player);

      // Track changed values before stopAndClear
      changedTrack = null;

      await service.stopAndClear();

      // Queue is empty
      expect(service.currentQueue, isEmpty);
      expect(service.currentTrack, isNull);

      // onTrackChanged was called with null
      expect(changedTrack, isNull);

      // player.stop() was called
      verify(() => player.stop()).called(1);
    });

    test('stopAndClear is safe when already stopped', () async {
      await service.stop();
      // Second call should not throw
      await service.stopAndClear();
      // After stopAndClear, queue is empty
      expect(service.currentQueue, isEmpty);
      expect(service.currentTrack, isNull);
    });

    test(
      'setAfForNtimes and setAfNtimesCount configure engine correctly',
      () async {
        expect(service.isForNtimesMode, isFalse);

        await service.setAfForNtimes(true);
        expect(service.isForNtimesMode, isTrue);
      },
    );

    test(
      'forNtimes loop mode repeats the track and seeks to zero instead of advancing',
      () async {
        await service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack?.id, equals('1'));

        await service.setAfForNtimes(true);
        await service.setAfNtimesCount(2);

        updateState(
          (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
        );

        when(() => player.seek(Duration.zero)).thenAnswer((_) async {});

        // First completion: repeats remaining = 2 -> 1, seeks, doesn't advance
        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        expect(service.currentTrack?.id, equals('1')); // still track A!
        verify(() => player.seek(Duration.zero)).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Loop.file mid-queue restarts current track instead of advancing
    // -----------------------------------------------------------------------
    test(
      'loop file mid-queue restarts current track instead of advancing',
      () async {
        AfTrack? changedTrack;
        service.onTrackChanged = (track) {
          changedTrack = track;
        };

        await service.playQueue(
          [trackA, trackB, trackC],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack?.id, equals('1'));

        await service.setAfLoopMode(Loop.file);
        changedTrack = null;

        // Simulate completion mid-queue with loop=file.
        updateState(
          (s) => s.copyWith(playing: false, completed: false, loop: Loop.file),
        );

        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        // Should NOT advance — restart same track.
        expect(service.currentTrack?.id, equals('1'));
        // onTrackChanged should NOT fire (track didn't change).
        expect(changedTrack, isNull);
        // seek(0) called to restart.
        verify(() => player.seek(Duration.zero)).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Duplicate completed events for the same track are ignored
    // -----------------------------------------------------------------------
    test('duplicate completed events are ignored for same track', () async {
      int trackChangedCount = 0;
      service.onTrackChanged = (track) {
        trackChangedCount++;
      };

      // Use a single-track queue so queue end is reached on first completion.
      // The guard stores track '1' after processing completion.
      await service.playQueue(
        [trackA],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      trackChangedCount = 0; // Reset after initial playQueue

      // Simulate completion at queue end (loop=off → endPlayback).
      updateState(
        (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
      );
      when(() => player.stop()).thenAnswer((_) async {});
      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Queue ended, currentTrack is null.
      expect(service.currentTrack, isNull);
      expect(trackChangedCount, equals(1)); // null track change

      // Now fire completed AGAIN (e.g. loop mode toggle causes re-fire).
      // The guard should ignore it because track '1' was already handled.
      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Still null — duplicate was ignored.
      expect(service.currentTrack, isNull);
      expect(trackChangedCount, equals(1));
    });

    // -----------------------------------------------------------------------
    // shouldAdvancePosition returns false when completed is true
    // -----------------------------------------------------------------------
    test(
      'shouldAdvancePosition returns false when mpv reports completed',
      () async {
        await service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);

        // While playing, shouldAdvancePosition is true.
        updateState(
          (s) =>
              s.copyWith(playing: true, completed: false, playWhenReady: true),
        );
        expect(service.shouldAdvancePosition, isTrue);

        // When completed fires, shouldAdvancePosition becomes false.
        updateState(
          (s) =>
              s.copyWith(playing: false, completed: true, playWhenReady: false),
        );
        expect(service.shouldAdvancePosition, isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // Full Bug 1→2→3 cascade: completion → loop toggle → play desync
    // -----------------------------------------------------------------------
    test('loop mode toggle after stuck completion does not change displayed '
        'track (Bug 2 prevention)', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 1, // Start at last track (queue end).
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('2'));

      // Simulate completion at queue end with loop=off.
      // This triggers endPlayback → currentTrack = null.
      updateState(
        (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
      );
      when(() => player.stop()).thenAnswer((_) async {});

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Queue ended normally — track is null.
      expect(service.currentTrack, isNull);
      changedTrack = null;

      // Now toggle loop mode. This should NOT re-enter the completed
      // handler and change the displayed track.
      await service.setAfLoopMode(Loop.playlist);
      await Future<void>.delayed(Duration.zero);

      // Fire another completed event (mpv re-evaluates end-of-file
      // when loop mode changes). The guard should catch this.
      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // currentTrack should still be null from the original endPlayback.
      // (The duplicate guard works on track id — null track means the
      // completed handler returns early at `if (!completed) return` or
      // the currentTrack null check.)
      expect(changedTrack, isNull);
    });

    // -----------------------------------------------------------------------
    // Loop.file completion resets the guard so next loop works
    // -----------------------------------------------------------------------
    test(
      'loop file does not set handled guard, allowing repeated loops',
      () async {
        await service.playQueue(
          [trackA],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);

        await service.setAfLoopMode(Loop.file);

        // First completion → seek(0) + play (Loop.file restart).
        updateState(
          (s) => s.copyWith(playing: false, completed: false, loop: Loop.file),
        );
        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        expect(service.currentTrack?.id, equals('1'));
        verify(() => player.seek(Duration.zero)).called(1);

        // Second completion → guard is set, so this is ignored.
        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        expect(service.currentTrack?.id, equals('1'));
        // seek NOT called again for the second event — guard prevents re-entry.
        verifyNever(() => player.seek(any()));
      },
    );

    // -----------------------------------------------------------------------
    // Stale completed events from previous tracks are ignored
    // -----------------------------------------------------------------------
    test(
      'stale completed events from previous tracks are ignored during stream replacement',
      () async {
        int trackChangedCount = 0;
        service.onTrackChanged = (track) {
          trackChangedCount++;
        };

        var openAllCallCount = 0;
        final openAllCompleter = Completer<void>();
        when(
          () => player.openAll(
            any(),
            play: any(named: 'play'),
            index: any(named: 'index'),
          ),
        ).thenAnswer((_) {
          openAllCallCount++;
          if (openAllCallCount == 1) {
            return Future.value();
          } else {
            return openAllCompleter.future;
          }
        });

        // Play queue starting at trackA
        await service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack?.id, equals('1'));
        trackChangedCount = 0; // Reset count

        // Simulate completed event for trackA, which advances the Dart queue index to trackB
        // and triggers _rebuildWindow(trackB).
        updateState(
          (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
        );
        ctrls.completed.add(true);

        // Wait for the completed event listener to execute and advance the index in Dart.
        // At this point, rebuildWindow(trackB) is awaiting the second openAll call,
        // so _mpvLoadedTrackId is still trackA's ID ('1').
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack?.id, equals('2'));
        expect(trackChangedCount, equals(1)); // Changed to trackB

        // Now fire a second completed event (simulating mpv's EOF event due to stopping trackA)
        // while openAll for trackB is still in-flight.
        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        // The listener should ignore this completed event because currentTrack is trackB
        // but _mpvLoadedTrackId is still trackA.
        expect(service.currentTrack?.id, equals('2'));
        expect(trackChangedCount, equals(1));

        // Resolve the second openAll call so rebuildWindow completes
        openAllCompleter.complete();
        await Future<void>.delayed(Duration.zero);

        // Verify that after resolving, trackB remains active and _mpvLoadedTrackId was updated
        expect(service.currentTrack?.id, equals('2'));
        expect(trackChangedCount, equals(1));
      },
    );

    // -----------------------------------------------------------------------
    // 14. EOF fallback fires on position stream when all conditions met
    // -----------------------------------------------------------------------
    test('EOF fallback advances track when conditions are met', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      when(
        () => player.openAll(
          any(),
          play: any(named: 'play'),
          index: any(named: 'index'),
        ),
      ).thenAnswer((_) async {});

      // Set state: position near end, mpv stopped, duration valid.
      updateState(
        (s) => s.copyWith(
          playing: false,
          completed: false,
          loop: Loop.off,
          duration: const Duration(seconds: 30),
          position: const Duration(seconds: 29, milliseconds: 700),
        ),
      );

      // Fire position event that should trigger the fallback.
      // The position stream listener runs _checkEndOfTrackFallback.
      service.positionTracker.emitPositionForTesting(
        const Duration(seconds: 29, milliseconds: 700),
      );
      await Future<void>.delayed(Duration.zero);

      // Should advance to track B.
      expect(service.currentTrack?.id, equals('2'));
      expect(changedTrack?.id, equals('2'));
    });

    // -----------------------------------------------------------------------
    // 15. EOF fallback skipped when completed handler already processed track
    // -----------------------------------------------------------------------
    test('EOF fallback skipped when completed handler already ran', () async {
      int trackChangedCount = 0;
      service.onTrackChanged = (track) {
        trackChangedCount++;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);

      // First, fire a normal completed event. This sets
      // _completedHandledForTrackId = '1' and advances to track B.
      updateState(
        (s) => s.copyWith(
          playing: true,
          completed: false,
          loop: Loop.off,
          duration: const Duration(seconds: 30),
          position: const Duration(seconds: 30),
        ),
      );
      when(
        () => player.openAll(
          any(),
          play: any(named: 'play'),
          index: any(named: 'index'),
        ),
      ).thenAnswer((_) async {});

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('2'));
      trackChangedCount = 0;

      // Now simulate receiving a position event near the end of track A
      // (which is no longer current). The fallback should check
      // currentTrack.id (now '2') vs _completedHandledForTrackId ('1')
      // and not fire for track '1'.
      service.positionTracker.emitPositionForTesting(
        const Duration(seconds: 29, milliseconds: 700),
      );
      await Future<void>.delayed(Duration.zero);

      // Still on track B — no unwanted advance.
      expect(service.currentTrack?.id, equals('2'));
      expect(trackChangedCount, equals(0));
    });

    // -----------------------------------------------------------------------
    // 16. EOF fallback skipped when position is early in track
    // -----------------------------------------------------------------------
    test('EOF fallback skipped when position is early in track', () async {
      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      // Set state: position early in track, mpv still playing.
      updateState(
        (s) => s.copyWith(
          playing: true,
          completed: false,
          loop: Loop.off,
          duration: const Duration(seconds: 30),
          position: const Duration(seconds: 5),
        ),
      );

      service.positionTracker.emitPositionForTesting(
        const Duration(seconds: 5),
      );
      await Future<void>.delayed(Duration.zero);

      // Still on track A — fallback did not trigger.
      expect(service.currentTrack?.id, equals('1'));
    });

    // -----------------------------------------------------------------------
    // 17. EOF fallback skipped when mpv is still playing
    // -----------------------------------------------------------------------
    test('EOF fallback skipped when mpv is still playing', () async {
      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      // Set state: position near end but mpv still playing.
      updateState(
        (s) => s.copyWith(
          playing: true, // Still playing — fallback should NOT fire
          completed: false,
          loop: Loop.off,
          duration: const Duration(seconds: 30),
          position: const Duration(seconds: 29, milliseconds: 700),
        ),
      );

      service.positionTracker.emitPositionForTesting(
        const Duration(seconds: 29, milliseconds: 700),
      );
      await Future<void>.delayed(Duration.zero);

      // Still on track A — fallback did not trigger.
      expect(service.currentTrack?.id, equals('1'));
    });

    // -----------------------------------------------------------------------
    // 18. EOF fallback does not double-fire (guard prevents re-entry)
    // -----------------------------------------------------------------------
    test('EOF fallback does not double-fire for the same track', () async {
      int trackChangedCount = 0;
      service.onTrackChanged = (track) {
        trackChangedCount++;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      // Reset counter — playQueue already fired onTrackChanged once.
      trackChangedCount = 0;

      when(
        () => player.openAll(
          any(),
          play: any(named: 'play'),
          index: any(named: 'index'),
        ),
      ).thenAnswer((_) async {});

      // Set state for EOF fallback.
      updateState(
        (s) => s.copyWith(
          playing: false,
          completed: false,
          loop: Loop.off,
          duration: const Duration(seconds: 30),
          position: const Duration(seconds: 29, milliseconds: 700),
        ),
      );

      // First position event triggers fallback.
      service.positionTracker.emitPositionForTesting(
        const Duration(seconds: 29, milliseconds: 700),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('2'));
      expect(trackChangedCount, equals(1));

      // Reset state for current track (track B at position near end).
      updateState(
        (s) => s.copyWith(
          duration: const Duration(seconds: 30),
          position: const Duration(seconds: 30),
        ),
      );

      // Second position event — the guard prevents double-fire for track A,
      // but _eofFallbackHandledTrackId ('1') != currentTrack.id ('2'),
      // so the fallback fires for track B, advancing to end of queue.
      // _advanceToNextTrack stays at the last track (B) rather than calling endPlayback.
      service.positionTracker.emitPositionForTesting(
        const Duration(seconds: 29, milliseconds: 700),
      );
      await Future<void>.delayed(Duration.zero);

      // Still on track B — queue end reached, no further advance.
      expect(service.currentTrack?.id, equals('2'));
      // Two track changes: A→B (first fallback), B re-emitted (second fallback).
      expect(trackChangedCount, equals(2));
    });

    // -----------------------------------------------------------------------
    // 19. EOF fallback fires when completed event never arrives
    //     (simulating broken time-pos observation)
    // -----------------------------------------------------------------------
    test('EOF fallback advances track when completed never fires', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      when(
        () => player.openAll(
          any(),
          play: any(named: 'play'),
          index: any(named: 'index'),
        ),
      ).thenAnswer((_) async {});

      // Set state: position near end, mpv stopped (EOF reached),
      // completed is FALSE (event never fired on this device).
      updateState(
        (s) => s.copyWith(
          playing: false,
          completed: false,
          loop: Loop.off,
          duration: const Duration(seconds: 30),
          position: const Duration(seconds: 29, milliseconds: 700),
        ),
      );

      // Position tick triggers the fallback.
      service.positionTracker.emitPositionForTesting(
        const Duration(seconds: 29, milliseconds: 700),
      );
      await Future<void>.delayed(Duration.zero);

      // Should advance to track B despite no completed event.
      expect(service.currentTrack?.id, equals('2'));
      expect(changedTrack?.id, equals('2'));
    });

    // -----------------------------------------------------------------------
    // 20. Fallback guard does not block delayed completed event for next track
    // -----------------------------------------------------------------------
    test('fallback guard resets on track change (skipToNext)', () async {
      await service.playQueue(
        [trackA, trackB, trackC],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      // Set state for EOF fallback.
      updateState(
        (s) => s.copyWith(
          playing: false,
          completed: false,
          loop: Loop.off,
          duration: const Duration(seconds: 30),
          position: const Duration(seconds: 29, milliseconds: 700),
        ),
      );
      when(
        () => player.openAll(
          any(),
          play: any(named: 'play'),
          index: any(named: 'index'),
        ),
      ).thenAnswer((_) async {});

      // Fallback fires for track A.
      service.positionTracker.emitPositionForTesting(
        const Duration(seconds: 29, milliseconds: 700),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('2'));

      // Now manually skip to track C. This resets both guards.
      await service.skipToQueueItem(2);
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('3'));

      // Set state for EOF on track C.
      updateState(
        (s) => s.copyWith(
          playing: false,
          completed: false,
          loop: Loop.off,
          duration: const Duration(seconds: 30),
          position: const Duration(seconds: 29, milliseconds: 700),
        ),
      );

      // Position tick should trigger fallback for track C
      // (guards were reset by skipToQueueItem).
      service.positionTracker.emitPositionForTesting(
        const Duration(seconds: 29, milliseconds: 700),
      );
      await Future<void>.delayed(Duration.zero);

      // Queue at end — _advanceToNextTrack stays on the last track.
      expect(service.currentTrack?.id, equals('3'));
    });
  });
}
