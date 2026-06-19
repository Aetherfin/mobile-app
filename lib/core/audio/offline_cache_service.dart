import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/log.dart';
import '../local/app_database.dart';
import '../network/shared_dio_client.dart';

/// Persistent offline track cache for server-mode playback.
///
/// After a track finishes streaming, its raw audio bytes are downloaded
/// to `getApplicationSupportDirectory()/audio_cache/{trackId}`. Before
/// building a network stream URL, [isCached] is checked — if the file
/// exists locally mpv gets a `file://` URI instead.
///
/// The manifest is stored in the [CacheEntries] drift table (track ID,
/// file size, last-played timestamp) for LRU eviction and stats.
class OfflineCacheService {
  OfflineCacheService({required AppDatabase database})
    : _db = database,
      _dio = SharedDioClient().createWithOptions(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
          headers: {'User-Agent': 'Aetherfin'},
        ),
      );
  final AppDatabase _db;
  final Dio _dio;
  String? _cacheDirPath;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _cacheDirPath = p.join(dir.path, 'audio_cache');
    await Directory(_cacheDirPath!).create(recursive: true);
    await _cleanOrphanedTempFiles();
    afLog('cache', 'OfflineCacheService initialized at $_cacheDirPath');
  }

  String get _cacheDir {
    if (_cacheDirPath == null) {
      throw StateError(
        'OfflineCacheService not initialized — call init() first',
      );
    }
    return _cacheDirPath!;
  }

  File _fileFor(String trackId) => File(p.join(_cacheDir, trackId));
  File _tempFileFor(String trackId) => File(p.join(_cacheDir, '.$trackId.tmp'));

  /// Check if a track is cached on disk (async).
  Future<bool> isCached(String trackId) async {
    if (trackId.isEmpty) return false;
    return _fileFor(trackId).exists();
  }

  /// `file://` URI for a cached track, or null if not cached.
  Future<String?> cachedFileUri(String trackId) async {
    if (!await isCached(trackId)) return null;
    return 'file://${_fileFor(trackId).path}';
  }

  /// Download [streamUrl] and save to the cache.
  Future<void> cacheTrack(
    String trackId,
    String streamUrl, {
    Map<String, String> headers = const {},
  }) async {
    final tempFile = _tempFileFor(trackId);
    final realFile = _fileFor(trackId);

    try {
      if (await realFile.exists()) {
        // Update lastPlayedAt even for already-cached tracks so LRU
        // eviction doesn't evict recently-played tracks.
        final now = DateTime.now().millisecondsSinceEpoch;
        await (_db.update(_db.cacheEntries)
              ..where((t) => t.trackId.equals(trackId)))
            .write(CacheEntriesCompanion(lastPlayedAt: Value(now)));
        afLog(
          'cache',
          'cacheTrack: already cached $trackId (refreshed lastPlayedAt)',
        );
        return;
      }

      await _dio.download(
        streamUrl,
        tempFile.path,
        options: Options(headers: headers),
      );

      if (!await tempFile.exists()) {
        afLog('cache', 'cacheTrack: download produced no file for $trackId');
        return;
      }

      final fileSize = await tempFile.length();
      if (fileSize == 0) {
        await tempFile.delete();
        afLog('cache', 'cacheTrack: empty download for $trackId');
        return;
      }

      await tempFile.rename(realFile.path);
      final now = DateTime.now().millisecondsSinceEpoch;

      await _db
          .into(_db.cacheEntries)
          .insertOnConflictUpdate(
            CacheEntriesCompanion.insert(
              trackId: trackId,
              fileSize: fileSize,
              lastPlayedAt: now,
            ),
          );

      afLog('cache', 'cached $trackId (${_formatBytes(fileSize)})');

      await evictLRU();
    } on Exception catch (e, stack) {
      afLog(
        'cache',
        'cacheTrack failed for $trackId',
        error: e,
        stackTrace: stack,
      );
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Evict least-recently-played tracks until under the max cache size.
  /// Uses SQL aggregate for total size and batched ORDER BY to avoid loading
  /// all entries into memory.
  Future<void> evictLRU({int? maxCacheSizeBytes}) async {
    final maxSize = maxCacheSizeBytes ?? await _loadMaxCacheSize();

    // Single aggregate query instead of loading all rows
    final sizeResult = await _db
        .customSelect(
          'SELECT COALESCE(SUM(file_size), 0) AS total FROM cache_entries',
          readsFrom: {_db.cacheEntries},
        )
        .getSingle();
    var totalSize = sizeResult.read<int>('total');

    if (totalSize <= maxSize) return;

    // Evict oldest entries in batches of 50 — loads only eviction candidates
    var evicted = 0;
    while (totalSize > maxSize) {
      final entries =
          await (_db.select(_db.cacheEntries)
                ..orderBy([(t) => OrderingTerm.asc(t.lastPlayedAt)])
                ..limit(50))
              .get();

      if (entries.isEmpty) break;

      for (final entry in entries) {
        if (totalSize <= maxSize) break;
        final file = _fileFor(entry.trackId);
        if (await file.exists()) {
          await file.delete();
          totalSize -= entry.fileSize;
          evicted++;
        }
        await (_db.delete(
          _db.cacheEntries,
        )..where((t) => t.trackId.equals(entry.trackId))).go();
      }
    }

    if (evicted > 0) {
      afLog('cache', 'LRU evicted $evicted tracks');
    }
  }

  /// Total size of all cached files in bytes.
  Future<int> cacheSize() async {
    final r = await _db
        .customSelect(
          'SELECT COALESCE(SUM(file_size), 0) AS s FROM cache_entries',
          readsFrom: {_db.cacheEntries},
        )
        .getSingle();
    return r.read<int>('s');
  }

  /// Number of cached tracks.
  Future<int> cachedCount() async {
    final r = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM cache_entries',
          readsFrom: {_db.cacheEntries},
        )
        .getSingle();
    return r.read<int>('c');
  }

  /// Remove all cached files and clear the manifest.
  Future<void> clearCache() async {
    final dir = Directory(_cacheDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    await _db.delete(_db.cacheEntries).go();
    afLog('cache', 'cache cleared');
  }

  Future<void> _cleanOrphanedTempFiles() async {
    final dir = Directory(_cacheDir);
    if (!await dir.exists()) return;
    var cleaned = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        await entity.delete();
        cleaned++;
      }
    }
    if (cleaned > 0) {
      afLog('cache', 'cleaned $cleaned orphaned temp files');
    }
  }

  static Future<int> _loadMaxCacheSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('af.offline_cache_max_size') ?? _kDefaultMaxCacheSize;
  }

  static const int _kDefaultMaxCacheSize = 1024 * 1024 * 1024; // 1 GB

  /// Human-readable size string (e.g. "1.2 GB").
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _formatBytes(int bytes) => formatSize(bytes);

  /// Releases the Dio HTTP client held by this service.
  void dispose() {
    _dio.close(force: true);
  }
}
