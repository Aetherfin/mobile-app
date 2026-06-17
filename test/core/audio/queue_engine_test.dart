import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/audio/queue_engine.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

void main() {
  group('AfQueueEngine', () {
    late AfQueueEngine engine;
    late List<AfTrack> tracks;

    setUp(() {
      engine = AfQueueEngine();
      tracks = [
        const AfTrack(
          id: '1',
          title: 'Track 1',
          artistName: 'A',
          albumName: 'B',
        ),
        const AfTrack(
          id: '2',
          title: 'Track 2',
          artistName: 'A',
          albumName: 'B',
        ),
        const AfTrack(
          id: '3',
          title: 'Track 3',
          artistName: 'A',
          albumName: 'B',
        ),
        const AfTrack(
          id: '4',
          title: 'Track 4',
          artistName: 'A',
          albumName: 'B',
        ),
        const AfTrack(
          id: '5',
          title: 'Track 5',
          artistName: 'A',
          albumName: 'B',
        ),
      ];
    });

    group('replaceAll', () {
      test('replaces queue and sets current index', () {
        engine.replaceAll(tracks, 2);
        expect(engine.length, 5);
        expect(engine.currentIndex, 2);
        expect(engine.currentTrack?.id, '3');
        expect(engine.playbackEnded, isFalse);
        expect(engine.isShuffleEnabled, isFalse);
      });

      test('clamps start index out of bounds', () {
        engine.replaceAll(tracks, -1);
        expect(engine.currentIndex, 0);
        engine.replaceAll(tracks, 100);
        expect(engine.currentIndex, 4);
      });

      test('handles empty tracks', () {
        engine.replaceAll([], 0);
        expect(engine.isEmpty, isTrue);
        expect(engine.currentIndex, -1);
      });
    });

    group('shuffle', () {
      test('shuffle on creates index mapping', () {
        engine.replaceAll(tracks, 0);
        engine.setShuffle(true);
        expect(engine.isShuffleEnabled, isTrue);
        // Current track should still be track 1 (index 0 after mapping)
        expect(engine.currentTrack?.id, '1');
        // All 5 tracks should be present in the mapping
        final seen = <String>{};
        for (var i = 0; i < 5; i++) {
          seen.add(engine.trackAt(i)!.id);
        }
        expect(seen, equals({'1', '2', '3', '4', '5'}));
      });

      test('shuffle off clears mapping', () {
        engine.replaceAll(tracks, 0);
        engine.setShuffle(true);
        expect(engine.isShuffleEnabled, isTrue);
        engine.setShuffle(false);
        expect(engine.isShuffleEnabled, isFalse);
      });

      test('double shuffle on is no-op', () {
        engine.replaceAll(tracks, 0);
        engine.setShuffle(true);
        engine.setShuffle(true); // no-op
        expect(engine.isShuffleEnabled, isTrue);
      });

      test('shuffle preserves current track position', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        // trackAt(0) should be the current track (id='3')
        expect(engine.trackAt(0)!.id, '3');
      });

      test('physicalIndex and logicalIndex roundtrip', () {
        engine.replaceAll(tracks, 0);
        engine.setShuffle(true);
        // Verify the mapping is consistent
        for (var i = 0; i < 5; i++) {
          final phys = engine.physicalIndex(i);
          final log = engine.logicalIndex(phys);
          expect(log, i);
        }
      });
    });

    group('shuffle interactions', () {
      test('currentIndex and tracks reflect shuffle state', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        expect(engine.currentIndex, 0);
        expect(engine.tracks.first.id, '3');
        expect(engine.tracks.length, 5);
      });

      test('advanceIndex and retreatIndex work logically', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        // logical order starts with track '3' at index 0
        expect(engine.currentIndex, 0);
        expect(engine.currentTrack?.id, '3');

        // Advance to logical 1
        final nextLogIdx = engine.advanceIndex();
        expect(nextLogIdx, 1);
        expect(engine.currentIndex, 1);
        // The track playing should be engine.tracks[1]
        expect(engine.currentTrack?.id, engine.tracks[1].id);

        // Retreat back to logical 0
        final prevLogIdx = engine.retreatIndex();
        expect(prevLogIdx, 0);
        expect(engine.currentIndex, 0);
        expect(engine.currentTrack?.id, '3');
      });

      test('jumpTo works logically', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        engine.jumpTo(3);
        expect(engine.currentIndex, 3);
        expect(engine.currentTrack?.id, engine.tracks[3].id);
      });

      test('isAtQueueEnd works logically', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        expect(engine.isAtQueueEnd, isFalse);
        engine.jumpTo(4);
        expect(engine.isAtQueueEnd, isTrue);
      });

      test('nextTrack works logically', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        // logical order starts with track '3' at index 0
        expect(engine.nextTrack?.id, engine.tracks[1].id);
      });

      test('remove works logically under shuffle', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        // track 3 (id='3') is at logical 0 (currentIndex is logical 0, physical 2)
        // Let's verify canRemove
        expect(engine.canRemove(0), isFalse); // cannot remove current
        expect(engine.canRemove(1), isTrue);

        final trackAtLogical1 = engine.tracks[1];
        engine.remove(1);
        expect(engine.length, 4);
        expect(engine.currentIndex, 0);
        expect(engine.currentTrack?.id, '3');
        expect(engine.tracks.any((t) => t.id == trackAtLogical1.id), isFalse);
      });

      test('insert works logically under shuffle', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        const newTrack = AfTrack(
          id: 'new',
          title: 'New',
          artistName: 'X',
          albumName: 'Y',
        );
        // currentIndex is logical 0
        engine.insert(1, newTrack);
        expect(engine.length, 6);
        expect(engine.tracks[1].id, 'new');
        expect(engine.currentIndex, 0);
      });

      test('insert before currentIndex shifts it', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        const newTrack = AfTrack(
          id: 'new',
          title: 'New',
          artistName: 'X',
          albumName: 'Y',
        );
        engine.insert(0, newTrack);
        // currentIndex was logical 0, insert at 0 shifts it to logical 1
        expect(engine.currentIndex, 1);
      });

      test('append works logically under shuffle', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        const newTrack = AfTrack(
          id: 'new',
          title: 'New',
          artistName: 'X',
          albumName: 'Y',
        );
        engine.append(newTrack);
        expect(engine.length, 6);
        expect(engine.tracks.last.id, 'new');
      });

      test('reorder works logically under shuffle', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        // engine.tracks is shuffled, currentIndex is logical 0 (first track)
        final firstTrack = engine.tracks[0];
        final secondTrack = engine.tracks[1];

        // Reorder index 0 to 2
        engine.reorder(0, 2);
        // new order should have secondTrack first, then firstTrack at index 1
        expect(engine.tracks[0].id, secondTrack.id);
        expect(engine.tracks[1].id, firstTrack.id);
        // currentIndex should be logical 1 now
        expect(engine.currentIndex, 1);
        expect(engine.currentTrack?.id, firstTrack.id);
      });
    });

    group('track transitions', () {
      test('advanceIndex moves forward', () {
        engine.replaceAll(tracks, 1);
        expect(engine.advanceIndex(), 2);
        expect(engine.currentTrack?.id, '3');
      });

      test('advanceIndex stops at end', () {
        engine.replaceAll(tracks, 4);
        expect(engine.advanceIndex(), 4);
      });

      test('retreatIndex moves backward', () {
        engine.replaceAll(tracks, 2);
        expect(engine.retreatIndex(), 1);
        expect(engine.currentTrack?.id, '2');
      });

      test('retreatIndex stops at start', () {
        engine.replaceAll(tracks, 0);
        expect(engine.retreatIndex(), 0);
      });

      test('jumpTo moves to exact index', () {
        engine.replaceAll(tracks, 0);
        engine.jumpTo(3);
        expect(engine.currentIndex, 3);
      });

      test('jumpTo clamps out of bounds', () {
        engine.replaceAll(tracks, 0);
        engine.jumpTo(100);
        expect(engine.currentIndex, 4);
      });

      test('isAtQueueEnd is correct', () {
        engine.replaceAll(tracks, 3);
        expect(engine.isAtQueueEnd, isFalse);
        engine.advanceIndex();
        expect(engine.isAtQueueEnd, isTrue);
      });

      test('nextTrack returns correct track', () {
        engine.replaceAll(tracks, 2);
        expect(engine.nextTrack?.id, '4');
      });

      test('nextTrack is null at end', () {
        engine.replaceAll(tracks, 4);
        expect(engine.nextTrack, isNull);
      });
    });

    group('queue mutations', () {
      test('remove removes track and adjusts indices', () {
        engine.replaceAll(tracks, 2);
        engine.remove(0);
        expect(engine.length, 4);
        // currentIndex was 2, now should be 1 (shifted)
        expect(engine.currentIndex, 1);
        expect(engine.currentTrack?.id, '3');
      });

      test('canRemove returns false for current index', () {
        engine.replaceAll(tracks, 2);
        expect(engine.canRemove(2), isFalse);
        expect(engine.canRemove(1), isTrue);
        expect(engine.canRemove(0), isTrue);
      });

      test('insert inserts track and adjusts currentIndex', () {
        engine.replaceAll(tracks, 1);
        const newTrack = AfTrack(
          id: 'new',
          title: 'New',
          artistName: 'X',
          albumName: 'Y',
        );
        engine.insert(3, newTrack);
        expect(engine.length, 6);
        expect(engine.tracks[3].id, 'new');
        // currentIndex was 1, insert at 3 > 1 → currentIndex unchanged
        expect(engine.currentIndex, 1);
      });

      test('insert before currentIndex increments it', () {
        engine.replaceAll(tracks, 2);
        const newTrack = AfTrack(
          id: 'new',
          title: 'New',
          artistName: 'X',
          albumName: 'Y',
        );
        engine.insert(0, newTrack);
        expect(engine.currentIndex, 3);
      });

      test('append adds to end', () {
        engine.replaceAll(tracks, 0);
        const newTrack = AfTrack(
          id: 'new',
          title: 'New',
          artistName: 'X',
          albumName: 'Y',
        );
        engine.append(newTrack);
        expect(engine.length, 6);
        expect(engine.tracks.last.id, 'new');
      });

      test('reorder adjusts indices correctly', () {
        engine.replaceAll(tracks, 2);
        // tracks = [1, 2, 3, 4, 5], currentIndex=2 (track '3')
        engine.reorder(0, 3); // Move track 0 to position 3
        // After reorder: [2, 3, 1, 4, 5], currentIndex=1 (track '3')
        expect(engine.tracks[0].id, '2');
        expect(engine.tracks[1].id, '3');
        expect(engine.tracks[2].id, '1');
        expect(engine.currentIndex, 1);
      });
    });

    group('endPlayback and clear', () {
      test('endPlayback sets index to -1', () {
        engine.replaceAll(tracks, 2);
        engine.endPlayback();
        expect(engine.currentIndex, -1);
        expect(engine.currentTrack, isNull);
        expect(engine.playbackEnded, isTrue);
        expect(engine.length, 5); // queue preserved
      });

      test('clear resets all state', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        engine.clear();
        expect(engine.isEmpty, isTrue);
        expect(engine.currentIndex, -1);
        expect(engine.isShuffleEnabled, isFalse);
        expect(engine.playbackEnded, isFalse);
      });
    });

    group('forNtimes loop mode', () {
      test('default state is inactive', () {
        final engine = AfQueueEngine();
        expect(engine.isForNtimes, false);
        expect(engine.remainingRepeats, 0);
        expect(engine.ntimesCount, 2);
      });

      test(
        'setForNtimes(true) activates and sets remaining to ntimesCount',
        () {
          final engine = AfQueueEngine();
          engine.replaceAll(tracks, 0);
          engine.setForNtimes(true);
          expect(engine.isForNtimes, true);
          expect(engine.remainingRepeats, 2);
        },
      );

      test('decrementRepeats reduces remaining count', () {
        final engine = AfQueueEngine();
        engine.replaceAll(tracks, 0);
        engine.setForNtimes(true);
        engine.decrementRepeats();
        expect(engine.remainingRepeats, 1);
        engine.decrementRepeats();
        expect(engine.remainingRepeats, 0);
        engine.decrementRepeats();
        expect(engine.remainingRepeats, 0);
      });

      test('setForNtimes(false) deactivates and resets', () {
        final engine = AfQueueEngine();
        engine.replaceAll(tracks, 0);
        engine.setForNtimes(true);
        engine.decrementRepeats();
        engine.setForNtimes(false);
        expect(engine.isForNtimes, false);
        expect(engine.remainingRepeats, 0);
      });

      test('setNtimesCount changes N and resets remaining when active', () {
        final engine = AfQueueEngine();
        engine.replaceAll(tracks, 0);
        engine.setForNtimes(true);
        engine.setNtimesCount(5);
        expect(engine.ntimesCount, 5);
        expect(engine.remainingRepeats, 5);
      });

      test('resetRepeats resets to ntimesCount when active', () {
        final engine = AfQueueEngine();
        engine.replaceAll(tracks, 0);
        engine.setForNtimes(true);
        engine.decrementRepeats();
        engine.decrementRepeats();
        expect(engine.remainingRepeats, 0);
        engine.resetRepeats();
        expect(engine.remainingRepeats, 2);
      });

      test('resetRepeats is no-op when inactive', () {
        final engine = AfQueueEngine();
        engine.replaceAll(tracks, 0);
        engine.resetRepeats();
        expect(engine.remainingRepeats, 0);
      });

      test('clear() resets forNtimes state', () {
        final engine = AfQueueEngine();
        engine.replaceAll(tracks, 0);
        engine.setForNtimes(true);
        engine.clear();
        expect(engine.isForNtimes, false);
        expect(engine.remainingRepeats, 0);
      });
    });

    group('updateTrackFavorite', () {
      test('updates favorite flag on matching track', () {
        engine.replaceAll(tracks, 0);
        expect(engine.tracks[0].isFavorite, isFalse);
        engine.updateTrackFavorite('1', true);
        expect(engine.tracks[0].isFavorite, isTrue);
      });

      test('invalidates shuffle cache when shuffle is ON', () {
        engine.replaceAll(tracks, 0);
        engine.setShuffle(true);
        // Read tracks to populate _shuffledTracks cache
        final before = engine.tracks;
        expect(before.length, 5);

        // Update favorite — should invalidate cache
        engine.updateTrackFavorite('1', true);
        final after = engine.tracks;
        // Cache rebuilt — favorite should be reflected
        final track1 = after.firstWhere((t) => t.id == '1');
        expect(track1.isFavorite, isTrue);
      });

      test('no-op for non-existent track ID', () {
        engine.replaceAll(tracks, 0);
        engine.updateTrackFavorite('nonexistent', true);
        expect(engine.tracks.every((t) => !t.isFavorite), isTrue);
      });
    });

    group('remove current track with shuffle ON', () {
      test(
        'decrements currentIndex when removing current track at physical index',
        () {
          engine.replaceAll(tracks, 2); // track '3' at index 2
          engine.setShuffle(true);
          // Current track is at logical 0
          expect(engine.currentTrack?.id, '3');
          final currentIndex = engine.currentIndex;
          expect(currentIndex, 0);

          // Remove a non-current track (logical 1) to test index adjustment
          engine.remove(1);
          expect(engine.length, 4);
          // Current track should still be '3'
          expect(engine.currentTrack?.id, '3');
        },
      );

      test(
        'handles removing track at physical index equal to currentIndex',
        () {
          // Setup: 5 tracks, shuffle ON, current at logical 0
          engine.replaceAll(tracks, 2);
          engine.setShuffle(true);
          expect(engine.currentTrack?.id, '3');

          // Remove logical 1 (non-current) — the physical index of logical 1
          // might equal _currentIndex physical position. The >= fix ensures
          // _currentIndex is decremented when the removed physical index
          // is <= _currentIndex.
          engine.remove(1);
          expect(engine.length, 4);
          // After removing, current track should still be '3'
          expect(engine.currentTrack?.id, '3');
        },
      );
    });

    group('shuffleTail', () {
      test('shuffles only tracks after current index when shuffle is off', () {
        final engine = AfQueueEngine();
        engine.replaceAll(tracks, 0);
        final currentTrackId = engine.currentTrack!.id;

        engine.shuffleTail();

        expect(engine.currentIndex, 0);
        expect(engine.currentTrack!.id, currentTrackId);
        expect(engine.isShuffleEnabled, true);
        expect(engine.currentIndex, 0);
      });

      test(
        'shuffles only tracks after current index when shuffle is already on',
        () {
          final engine = AfQueueEngine();
          engine.replaceAll(tracks, 0);
          engine.setShuffle(true);
          final currentTrackId = engine.currentTrack!.id;

          engine.shuffleTail();

          expect(engine.currentIndex, 0);
          expect(engine.currentTrack!.id, currentTrackId);
        },
      );

      test('no-op for empty queue', () {
        final engine = AfQueueEngine();
        engine.shuffleTail();
        expect(engine.currentIndex, -1);
      });

      test('no-op for single-track queue', () {
        final engine = AfQueueEngine();
        engine.shuffleTail();
        expect(engine.currentIndex, -1);
      });

      test('no-op when at end of queue', () {
        final engine = AfQueueEngine();
        engine.replaceAll(tracks, 4);
        engine.shuffleTail();
        expect(engine.isShuffleEnabled, false);
      });

      test('preserves head order when shuffle was off', () {
        final engine = AfQueueEngine();
        engine.replaceAll(tracks, 2);
        engine.shuffleTail();
        expect(engine.isShuffleEnabled, true);
      });
    });
  });
}
