import 'package:aetherfin/core/audio/active_queue_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ActiveQueueStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = ActiveQueueStore();
  });

  group('ActiveQueueStore', () {
    group('save / restore round-trip', () {
      test('saves and restores basic queue state', () async {
        const trackIds = <String>['a', 'b', 'c', 'd', 'e'];
        const currentIndex = 2;
        const position = Duration(seconds: 30);
        const shuffleEnabled = false;

        await store.save(
          trackIds: trackIds,
          currentIndex: currentIndex,
          position: position,
          shuffleEnabled: shuffleEnabled,
        );

        final restored = await store.restore();
        expect(restored, isNotNull);
        expect(restored!.trackIds, orderedEquals(trackIds));
        expect(restored.currentIndex, currentIndex);
        expect(restored.position, position);
        expect(restored.shuffleMapping, isNull);
        expect(restored.shuffleEnabled, isFalse);
      });

      test('preserves shuffle mapping', () async {
        const trackIds = <String>['a', 'b', 'c', 'd', 'e'];
        const shuffleMapping = [2, 0, 4, 1, 3];

        await store.save(
          trackIds: trackIds,
          currentIndex: 0,
          position: Duration.zero,
          shuffleMapping: shuffleMapping,
          shuffleEnabled: true,
        );

        final restored = await store.restore();
        expect(restored, isNotNull);
        expect(restored!.shuffleEnabled, isTrue);
        expect(restored.shuffleMapping, orderedEquals(shuffleMapping));
      });

      test('handles empty track list', () async {
        await store.save(
          trackIds: <String>[],
          currentIndex: 0,
          position: Duration.zero,
        );

        final restored = await store.restore();
        expect(restored, isNull);
      });

      test('restore returns null when nothing saved', () async {
        final restored = await store.restore();
        expect(restored, isNull);
      });
    });

    group('windowed save', () {
      test('keeps full list when under maxPersistedTracks', () async {
        final ids = List<String>.generate(50, (i) => 'id_$i');
        const index = 10;

        await store.save(
          trackIds: ids,
          currentIndex: index,
          position: Duration.zero,
        );

        final restored = await store.restore();
        expect(restored, isNotNull);
        expect(restored!.trackIds.length, 50);
        expect(restored.currentIndex, index);
      });

      test('windows to 71 tracks around current index', () async {
        final ids = List<String>.generate(200, (i) => 'id_$i');
        const index = 100;

        await store.save(
          trackIds: ids,
          currentIndex: index,
          position: Duration.zero,
        );

        final restored = await store.restore();
        expect(restored, isNotNull);
        // Window: 20 before + 1 current + 50 after = 71
        expect(restored!.trackIds.length, 71);
        // Current track should be 'id_100' at adjusted index 20
        expect(restored.trackIds[20], 'id_100');
        expect(restored.currentIndex, 20);
      });

      test('windows near start of queue', () async {
        final ids = List<String>.generate(200, (i) => 'id_$i');
        const index = 0;

        await store.save(
          trackIds: ids,
          currentIndex: index,
          position: Duration.zero,
        );

        final restored = await store.restore();
        expect(restored, isNotNull);
        // Window clamps to start: 0..51 = 52 tracks (before=0, current, after=50)
        expect(restored!.trackIds.length, 51);
        expect(restored.trackIds[0], 'id_0');
        expect(restored.currentIndex, 0);
      });

      test('windows near end of queue', () async {
        final ids = List<String>.generate(200, (i) => 'id_$i');
        const index = 195;

        await store.save(
          trackIds: ids,
          currentIndex: index,
          position: Duration.zero,
        );

        final restored = await store.restore();
        expect(restored, isNotNull);
        // Window clamps to end: 175..200 = 25 tracks
        expect(restored!.trackIds.length, 25);
        expect(restored.currentIndex, 20);
        expect(restored.trackIds.last, 'id_199');
      });
    });

    group('clear', () {
      test('removes all persisted data', () async {
        await store.save(
          trackIds: ['a', 'b', 'c'],
          currentIndex: 1,
          position: const Duration(seconds: 10),
          shuffleMapping: [2, 0, 1],
          shuffleEnabled: true,
        );

        await store.clear();
        final restored = await store.restore();
        expect(restored, isNull);
      });
    });

    group('corner cases', () {
      test('handles single track queue', () async {
        const trackIds = <String>['only_track'];

        await store.save(
          trackIds: trackIds,
          currentIndex: 0,
          position: Duration.zero,
        );

        final restored = await store.restore();
        expect(restored, isNotNull);
        expect(restored!.trackIds, orderedEquals(trackIds));
        expect(restored.currentIndex, 0);
      });

      test('handles currentIndex at bounds', () async {
        const trackIds = <String>['x', 'y', 'z'];

        // Save with index at start
        await store.save(
          trackIds: trackIds,
          currentIndex: 0,
          position: Duration.zero,
        );
        var restored = await store.restore();
        expect(restored!.currentIndex, 0);
        expect(restored.trackIds[0], 'x');

        // Save with index at end
        await store.save(
          trackIds: trackIds,
          currentIndex: 2,
          position: Duration.zero,
        );
        restored = await store.restore();
        expect(restored!.currentIndex, 2);
        expect(restored.trackIds[2], 'z');
      });

      test('clamps invalid currentIndex on restore', () async {
        final p = await SharedPreferences.getInstance();
        await p.setStringList('af.active_queue.track_ids', ['a', 'b', 'c']);
        await p.setInt('af.active_queue.current_index', 10); // out of bounds
        await p.setInt('af.active_queue.position_ms', 0);

        final restored = await store.restore();
        expect(restored, isNotNull);
        // currentIndex should be clamped to trackIds.length - 1
        expect(restored!.currentIndex, 2);
      });

      test('position defaults to zero when not saved', () async {
        final p = await SharedPreferences.getInstance();
        await p.setStringList('af.active_queue.track_ids', ['a']);

        final restored = await store.restore();
        expect(restored, isNotNull);
        expect(restored!.position, Duration.zero);
      });
    });
  });
}
