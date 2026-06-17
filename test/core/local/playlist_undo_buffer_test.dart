import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/local/playlist_undo_buffer.dart';

void main() {
  group('PlaylistUndoBuffer', () {
    test('push and pop an undo action', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushRemove('pl-1', 'entry-1', 'track-1');
      final action = buffer.pop('pl-1');
      expect(action, isNotNull);
      expect(action!.playlistId, 'pl-1');
      expect(action.type, PlaylistUndoType.remove);
    });

    test('pushAdd creates correct undo data', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushAdd('pl-1', ['track-1', 'track-2']);
      final action = buffer.pop('pl-1')!;
      expect(action.type, PlaylistUndoType.add);
      expect(action.entryIds, isEmpty);
      expect(action.trackIds, ['track-1', 'track-2']);
    });

    test('auto-clears after 8 seconds', () {
      fakeAsync((async) {
        final buffer = PlaylistUndoBuffer();
        buffer.pushRemove('pl-1', 'entry-1', 'track-1');
        async.elapse(const Duration(seconds: 9));
        expect(buffer.pop('pl-1'), isNull);
      });
    });

    test('pop removes the action from buffer', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushRemove('pl-1', 'entry-1', 'track-1');
      buffer.pop('pl-1');
      expect(buffer.pop('pl-1'), isNull);
    });

    test('different playlists have independent actions', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushRemove('pl-1', 'e1', 't1');
      buffer.pushAdd('pl-2', ['t2']);
      expect(buffer.pop('pl-1')!.playlistId, 'pl-1');
      expect(buffer.pop('pl-2')!.playlistId, 'pl-2');
    });
  });
}
