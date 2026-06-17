import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/queue_history_repository.dart';

void main() {
  group('QueueHistoryRepository', () {
    late AppDatabase db;
    late QueueHistoryRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = QueueHistoryRepository(db);
    });

    tearDown(() => db.close());

    test('save and loadRecent', () async {
      await repo.save(
        trackIds: ['t1', 't2', 't3'],
        sourceLabel: 'Album: Test',
        sourceType: 'album',
        sourceId: 'alb-1',
      );
      final recent = await repo.loadRecent(limit: 10);
      expect(recent.length, 1);
      expect(recent[0].trackIds, ['t1', 't2', 't3']);
      expect(recent[0].sourceLabel, 'Album: Test');
      expect(recent[0].sourceType, 'album');
      expect(recent[0].sourceId, 'alb-1');
    });

    test('deduplication: same sourceType+sourceId skips save', () async {
      await repo.save(
        trackIds: ['t1'],
        sourceLabel: 'Playlist: A',
        sourceType: 'playlist',
        sourceId: 'pl-1',
      );
      await repo.save(
        trackIds: ['t1', 't2'],
        sourceLabel: 'Playlist: A',
        sourceType: 'playlist',
        sourceId: 'pl-1',
      );
      final recent = await repo.loadRecent(limit: 10);
      expect(recent.length, 1);
    });

    test('loadRecent respects limit', () async {
      for (var i = 0; i < 20; i++) {
        await repo.save(
          trackIds: ['t$i'],
          sourceLabel: 'Item $i',
          sourceType: 'playlist',
          sourceId: 'pl-$i',
        );
      }
      final recent = await repo.loadRecent(limit: 10);
      expect(recent.length, 10);
    });

    test('loadRecent returns newest first', () async {
      await repo.save(
        trackIds: ['old'],
        sourceLabel: 'Old',
        sourceType: 'playlist',
        sourceId: 'old-pl',
      );
      await Future.delayed(const Duration(milliseconds: 10));
      await repo.save(
        trackIds: ['new'],
        sourceLabel: 'New',
        sourceType: 'playlist',
        sourceId: 'new-pl',
      );
      final recent = await repo.loadRecent(limit: 10);
      expect(recent[0].sourceLabel, 'New');
      expect(recent[1].sourceLabel, 'Old');
    });

    test('deleteOldest keeps only latest N entries', () async {
      for (var i = 0; i < 15; i++) {
        await repo.save(
          trackIds: ['t$i'],
          sourceLabel: 'Item $i',
          sourceType: 'playlist',
          sourceId: 'pl-$i',
        );
      }
      await repo.deleteOldest(keep: 10);
      final recent = await repo.loadRecent(limit: 20);
      expect(recent.length, 10);
    });
  });
}
