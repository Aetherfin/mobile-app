import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/local/cover_cache_manager.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('cover_cache_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  Future<CoverCacheManager> createManager({int? maxBytes}) =>
      CoverCacheManager.create(
        cacheDir: tmpDir.path,
        maxBytes: maxBytes ?? 1000,
      );

  group('CoverCacheManager', () {
    test('tracks access timestamps', () async {
      final manager = await createManager();
      final f = File('${tmpDir.path}/cover1.jpg');
      f.writeAsBytesSync(List.filled(100, 1));
      manager.trackAccess(f.path);
    });

    test('evicts when over limit', () async {
      final manager = await createManager(maxBytes: 1000);
      for (int i = 0; i < 5; i++) {
        final f = File('${tmpDir.path}/cover$i.jpg');
        f.writeAsBytesSync(List.filled(400, i));
        manager.trackAccess(f.path);
      }
      final deleted = await manager.evictIfNeeded();
      expect(deleted, greaterThan(0));
      int remaining = 0;
      for (final f in tmpDir.listSync().whereType<File>()) {
        if (f.path.endsWith('_access_meta.json')) continue;
        remaining += f.lengthSync();
      }
      expect(remaining, lessThanOrEqualTo(1000));
    });

    test('does not evict when under limit', () async {
      final manager = await createManager(maxBytes: 1000);
      final f = File('${tmpDir.path}/cover.jpg');
      f.writeAsBytesSync(List.filled(100, 1));
      manager.trackAccess(f.path);
      expect(await manager.evictIfNeeded(), equals(0));
    });

    test('pruneStaleEntries removes missing file entries', () async {
      final manager = await createManager();
      final f = File('${tmpDir.path}/cover.jpg');
      f.writeAsBytesSync(List.filled(100, 1));
      manager.trackAccess(f.path);
      f.deleteSync();
      await manager.pruneStaleEntries();
      final m2 = await CoverCacheManager.create(
        cacheDir: tmpDir.path,
        maxBytes: 1000,
      );
      expect(await m2.evictIfNeeded(), equals(0));
    });
  });
}
