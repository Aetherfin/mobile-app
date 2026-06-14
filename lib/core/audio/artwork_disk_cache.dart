import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../utils/log.dart';

/// Manages the on-disk artwork cache — directory init, lookups, eviction,
/// and expired-file cleanup.
///
/// Separated from [AfArtworkManager] to keep the file under 250 LOC while
/// preserving all cache-invariant logic in one place.
class ArtworkDiskCache {
  ArtworkDiskCache();

  /// Maximum disk cache size in bytes (100MB)
  static const int maxSizeBytes = 100 * 1024 * 1024;

  /// Cache TTL
  static const Duration ttl = Duration(days: 7);

  /// Maximum number of disk cache files
  static const int maxFiles = 200;

  /// Maximum number of entries in the confirmed-exists fast-path set.
  static const int maxCheckedSize = 10000;

  String? _diskCacheDir;
  int _size = 0;

  /// Set of trackIds whose disk cache file has been confirmed to exist.
  /// Avoids redundant `existsSync()` + `statSync()` calls in the hot path.
  final Set<String> _checked = {};

  String? get directory => _diskCacheDir;
  int get size => _size;

  /// Initialise the cache directory. Idempotent — subsequent calls are no-ops.
  Future<void> init() async {
    if (_diskCacheDir != null) return;

    try {
      final cacheDir = await getApplicationCacheDirectory();
      _diskCacheDir = '${cacheDir.path}${Platform.pathSeparator}artwork_cache';
      final dir = Directory(_diskCacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // Initialize disk cache size from actual files on disk.
      int totalSize = 0;
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith('.tmp')) {
          totalSize += await entity.length();
        }
      }
      _size = totalSize;
      await cleanupExpired();
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to initialize disk cache',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Return the cached file path for [trackId] or `null`.
  ///
  /// Uses [_checked] to avoid redundant `existsSync()` + `statSync()`
  /// calls on confirmed-cached files. Stale entries are evicted lazily.
  String? getPath(String trackId) {
    if (_diskCacheDir == null) return null;
    final cachePath = '$_diskCacheDir/$trackId';

    // Fast path: file was confirmed to exist in a prior call.
    if (_checked.contains(trackId)) {
      if (File(cachePath).existsSync()) {
        return cachePath;
      }
      _checked.remove(trackId);
      return null;
    }

    final cacheFile = File(cachePath);
    if (cacheFile.existsSync()) {
      try {
        final stat = cacheFile.statSync();
        final ageDays = DateTime.now().difference(stat.modified).inDays;
        if (ageDays <= ttl.inDays) {
          if (_checked.length >= maxCheckedSize) {
            _checked.clear();
          }
          _checked.add(trackId);
          return cacheFile.path;
        } else {
          cacheFile.deleteSync();
          _checked.remove(trackId);
        }
      } on Exception catch (e, stack) {
        afLog(
          'audio',
          'Failed to check disk cache for $trackId',
          error: e,
          stackTrace: stack,
        );
      }
    }
    return null;
  }

  /// Add [trackId] to the fast-path set after a successful download.
  void markCached(String trackId) {
    if (_checked.length >= maxCheckedSize) {
      _checked.clear();
    }
    _checked.add(trackId);
  }

  /// Update tracked size by [delta] bytes (positive = added, negative = removed).
  void adjustSize(int delta) => _size += delta;

  /// Clean up expired disk cache files — async to avoid blocking main thread.
  Future<void> cleanupExpired() async {
    if (_diskCacheDir == null) return;
    try {
      final dir = Directory(_diskCacheDir!);
      final threshold = DateTime.now().subtract(ttl);

      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(threshold)) {
              final fileSize = stat.size;
              await entity.delete();
              _size -= fileSize;
              afLog('audio', 'Cleaned up expired cache file: ${entity.path}');
            }
          } on Exception catch (e, stack) {
            afLog(
              'audio',
              'Failed to clean up cache file: ${entity.path}',
              error: e,
              stackTrace: stack,
            );
          }
        }
      }

      await enforceSizeLimit();
    } on Exception catch (e, stack) {
      afLog('audio', 'Cache cleanup failed', error: e, stackTrace: stack);
    }
  }

  /// Enforce disk cache size limit by removing oldest files.
  Future<void> enforceSizeLimit() async {
    if (_diskCacheDir == null) return;

    try {
      final dir = Directory(_diskCacheDir!);
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith('.tmp')) {
          files.add(entity);
        }
      }

      // Pre-compute modification times to avoid repeated stat in sort.
      final entries = <({File file, DateTime modified})>[];
      for (final f in files) {
        try {
          final stat = await f.stat();
          entries.add((file: f, modified: stat.modified));
        } catch (e, stack) {
          afLog(
            'error',
            'Artwork cache file stat failed',
            error: e,
            stackTrace: stack,
          );
        }
      }
      entries.sort((a, b) => a.modified.compareTo(b.modified));

      while (_size > maxSizeBytes || entries.length > maxFiles) {
        if (entries.isEmpty) break;
        final oldest = entries.removeAt(0).file;
        try {
          final size = await oldest.length();
          await oldest.delete();
          _size -= size;
          afLog('audio', 'Evicted oldest cache file to enforce size limit');
        } on Exception catch (e, stack) {
          afLog(
            'audio',
            'Failed to evict cache file: ${oldest.path}',
            error: e,
            stackTrace: stack,
          );
        }
      }
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to enforce cache size limit',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Delete the entire cache directory and reset state.
  Future<void> clear() async {
    _checked.clear();
    if (_diskCacheDir != null) {
      try {
        final dir = Directory(_diskCacheDir!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          await dir.create(recursive: true);
          _size = 0;
        }
      } on Exception catch (e, stack) {
        afLog(
          'audio',
          'Failed to clear disk cache',
          error: e,
          stackTrace: stack,
        );
      }
    }
  }

  void resetTracking() {
    _checked.clear();
  }

  /// Download artwork from [imageUrl] and persist to the disk cache.
  ///
  /// Returns the local file path on success, or `null` on failure.
  Future<String?> downloadFromUrl(
    String trackId,
    String imageUrl,
    Map<String, String> authHeaders,
    HttpClient httpClient,
  ) async {
    if (_diskCacheDir == null) return null;
    try {
      final uri = Uri.parse(imageUrl);
      final request = await httpClient.getUrl(uri);
      authHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<int>(0);
        return null;
      }

      final contentType = response.headers.contentType;
      var ext = 'jpg';
      if (contentType != null && contentType.subType.isNotEmpty) {
        ext = contentType.subType == 'jpeg' ? 'jpg' : contentType.subType;
      }

      final path = '$_diskCacheDir/$trackId.$ext';
      final tmpPath = '$path.tmp';
      final tmpFile = File(tmpPath);
      final sink = tmpFile.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }

      await tmpFile.rename(path);

      final fileSize = (await File(path).stat()).size;
      _size += fileSize;
      await enforceSizeLimit();

      return path;
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'artwork download for notification failed',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }
}
