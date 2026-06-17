import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/features/queue/queue_actions.dart';
import 'package:flutter_test/flutter_test.dart';

const _track1 = AfTrack(
  id: 't1',
  title: 'Song 1',
  artistName: 'A',
  albumName: 'B',
);
const _track2 = AfTrack(
  id: 't2',
  title: 'Song 2',
  artistName: 'A',
  albumName: 'B',
);
const _track3 = AfTrack(
  id: 't3',
  title: 'Song 3',
  artistName: 'A',
  albumName: 'B',
);
const _track4 = AfTrack(
  id: 't4',
  title: 'Song 4',
  artistName: 'A',
  albumName: 'B',
);

final _queue = [_track1, _track2, _track3, _track4];

void main() {
  group('resolveBatchRemoveTargets', () {
    test('returns empty list when no indices selected', () {
      final result = resolveBatchRemoveTargets(
        items: _queue,
        selectedIndices: {},
        currentId: 't1',
        playerQueue: _queue,
      );
      expect(result, isEmpty);
    });

    test('skips currently playing track', () {
      final result = resolveBatchRemoveTargets(
        items: _queue,
        selectedIndices: {0, 1, 2},
        currentId: 't1',
        playerQueue: _queue,
      );
      expect(result.length, 2);
      expect(result.every((t) => t.$2.id != 't1'), isTrue);
    });

    test('returns targets sorted descending by actual index', () {
      final result = resolveBatchRemoveTargets(
        items: _queue,
        selectedIndices: {0, 2, 3},
        currentId: 't2',
        playerQueue: _queue,
      );
      expect(result.length, 3);
      expect(result[0].$1, greaterThanOrEqualTo(result[1].$1));
      expect(result[1].$1, greaterThanOrEqualTo(result[2].$1));
    });

    test('returns empty when only playing track is selected', () {
      final result = resolveBatchRemoveTargets(
        items: _queue,
        selectedIndices: {0},
        currentId: 't1',
        playerQueue: _queue,
      );
      expect(result, isEmpty);
    });
  });

  group('localIndicesToRemove', () {
    test('excludes playing track index', () {
      final result = localIndicesToRemove(
        items: _queue,
        selectedIndices: {0, 1, 2},
        currentId: 't1',
      );
      expect(result, {1, 2});
      expect(result.contains(0), isFalse);
    });
  });
}
