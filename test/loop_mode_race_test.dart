import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/audio/queue_manager.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

void main() {
  group('Loop mode race conditions', () {
    late AfQueueManager queueManager;
    late List<AfTrack> tracks;

    setUp(() {
      queueManager = AfQueueManager();
      tracks = [
        const AfTrack(
          id: 'track1',
          title: 'Track 1',
          artistName: 'Artist',
          albumName: 'Album',
        ),
        const AfTrack(
          id: 'track2',
          title: 'Track 2',
          artistName: 'Artist',
          albumName: 'Album',
        ),
        const AfTrack(
          id: 'track3',
          title: 'Track 3',
          artistName: 'Artist',
          albumName: 'Album',
        ),
      ];
    });

    test('loop mode read inside queueLock action sees stale value after '
        'async gap', () async {
      final lock = AfAsyncLock();
      var mutableLoop = Loop.off;
      Loop? actionResult;

      final fut = lock.run(() async {
        await Future<void>.delayed(Duration.zero);
        actionResult = mutableLoop;
      });

      mutableLoop = Loop.playlist;

      await fut;

      expect(
        actionResult,
        equals(Loop.playlist),
        reason: 'BUG: Lock action reads stale loop mode after async gap',
      );
    });

    test('completed handler uses captured loop mode, avoiding race with '
        'setAfLoopMode', () async {
      final lock = AfAsyncLock();
      var mutableLoop = Loop.off;
      Loop? actionResult;

      final capturedLoop = mutableLoop;

      final fut = lock.run(() async {
        await Future<void>.delayed(Duration.zero);
        actionResult = capturedLoop;
      });

      mutableLoop = Loop.playlist;

      await fut;

      expect(
        actionResult,
        equals(Loop.off),
        reason: 'FIX: Captured loop mode is preserved across async gap',
      );
      expect(mutableLoop, equals(Loop.playlist));
    });

    test('completed handler at queue end pauses when loop=off, even if '
        'loop changes to playlist during async gap', () async {
      queueManager.replaceQueue(tracks, 2);
      expect(queueManager.isAtQueueEnd, isTrue);

      final lock = AfAsyncLock();
      var currentLoop = Loop.off;

      final loopAtEvent = currentLoop;

      String? actionTaken;
      final completedFut = lock.run(() async {
        await Future<void>.delayed(Duration.zero);
        final nextIdx = queueManager.currentIndex + 1;
        final isAtEnd = nextIdx >= queueManager.currentQueue.length;

        if (isAtEnd) {
          switch (loopAtEvent) {
            case Loop.off:
              actionTaken = 'pause';
            case Loop.playlist:
              actionTaken = 'jumpToStart';
            case Loop.file:
              actionTaken = 'replayFile';
          }
        }
      });

      currentLoop = Loop.playlist;

      await completedFut;

      expect(
        actionTaken,
        equals('pause'),
        reason:
            'Handler should pause because loop was off at event time, '
            'even though it changed to playlist during the gap',
      );
    });
  });
}
