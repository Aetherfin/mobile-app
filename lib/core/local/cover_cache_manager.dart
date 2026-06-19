import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/log.dart';

/// Manages a local cover art cache with LRU eviction.
///
/// Tracks access timestamps via a metadata JSON file inside the cache
/// directory. On eviction, the least-recently-accessed files are deleted
/// until total size is below the configured maximum.
class CoverCacheManager {
  CoverCacheManager._({
    required String cacheDir,
    int maxBytes = _kDefaultMaxBytes,
  }) : _cacheDir = cacheDir,
       _maxBytes = maxBytes,
       _metaPath = '$cacheDir${Platform.pathSeparator}_access_meta.json';

  /// Async factory — loads metadata from disk before returning.
  static Future<CoverCacheManager> create({
    required String cacheDir,
    int maxBytes = _kDefaultMaxBytes,
  }) async {
    final manager = CoverCacheManager._(cacheDir: cacheDir, maxBytes: maxBytes);
    await manager._loadMeta();
    return manager;
  }

  final String _cacheDir;
  final int _maxBytes;
  final String _metaPath;

  static const int _kDefaultMaxBytes = 100 * 1024 * 1024; // 100 MB

  Map<String, int> _accessTimestamps = {};
  bool _dirty = false;
  Timer? _saveTimer;

  // ── Metadata persistence ──────────────────────────────────────────────

  Future<void> _loadMeta() async {
    final file = File(_metaPath);
    if (!await file.exists()) return;
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      _accessTimestamps = decoded.map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      );
    } on Exception catch (e, stack) {
      afLog(
        'local',
        'failed to load cover cache meta',
        error: e,
        stackTrace: stack,
      );
      _accessTimestamps = {};
    }
  }

  Future<void> _saveMeta() async {
    if (!_dirty) return;
    try {
      await File(_metaPath).writeAsString(jsonEncode(_accessTimestamps));
      _dirty = false;
    } on Exception catch (e, stack) {
      afLog(
        'local',
        'failed to save cover cache meta',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // ── Public API ────────────────────────────────────────────────────────

  /// Record an access to the cover at [path].
  ///
  /// This should be called whenever a cached cover file is created or
  /// read, so that the eviction order reflects actual usage.
  void trackAccess(String path) {
    _accessTimestamps[path] = DateTime.now().microsecondsSinceEpoch;
    _dirty = true;
    _scheduleSave();
  }

  /// Evict least-recently-accessed files until total size <= maxBytes.
  ///
  /// Returns the number of files deleted, or 0 if no eviction was needed.
  Future<int> evictIfNeeded() async {
    final cacheDir = Directory(_cacheDir);
    if (!await cacheDir.exists()) return 0;

    final files = (await cacheDir.list().toList()).whereType<File>().toList();
    int totalSize = 0;
    for (final f in files) {
      if (f.path == _metaPath) continue;
      totalSize += await f.length();
    }

    if (totalSize <= _maxBytes) return 0;

    files.sort((a, b) {
      if (a.path == _metaPath) return 1;
      if (b.path == _metaPath) return -1;
      final aTime = _accessTimestamps[a.path] ?? 0;
      final bTime = _accessTimestamps[b.path] ?? 0;
      return aTime.compareTo(bTime);
    });

    int deleted = 0;
    for (final f in files) {
      if (totalSize <= _maxBytes) break;
      if (f.path == _metaPath) continue;
      final len = await f.length();
      try {
        await f.delete();
        _accessTimestamps.remove(f.path);
        totalSize -= len;
        deleted++;
      } on Exception catch (e, stack) {
        afLog(
          'local',
          'failed to delete cover cache file',
          error: e,
          stackTrace: stack,
        );
      }
    }

    _dirty = true;
    await _saveMeta();
    return deleted;
  }

  /// Remove all cached covers and reset the access log.
  Future<void> clear() async {
    final cacheDir = Directory(_cacheDir);
    if (await cacheDir.exists()) {
      await for (final entity in cacheDir.list()) {
        if (entity is File && entity.path != _metaPath) {
          try {
            await entity.delete();
          } on Exception catch (e, stack) {
            afLog(
              'error',
              'Cover cache cleanup failed',
              error: e,
              stackTrace: stack,
            );
          }
        }
      }
    }
    _accessTimestamps.clear();
    _dirty = true;
    await _saveMeta();
  }

  /// Release resources — cancels any pending debounced save.
  void dispose() {
    _saveTimer?.cancel();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 5), () {
      if (_dirty) _saveMeta();
    });
  }

  /// Remove entries from the access log whose files no longer exist.
  ///
  /// Call this after external deletion (e.g., user clearing app data) to
  /// keep the metadata file consistent with on-disk state.
  Future<void> pruneStaleEntries() async {
    final before = _accessTimestamps.length;
    final stale = <String>[];
    for (final path in _accessTimestamps.keys) {
      if (!await File(path).exists()) stale.add(path);
    }
    for (final path in stale) {
      _accessTimestamps.remove(path);
    }
    if (_accessTimestamps.length != before) {
      _dirty = true;
      await _saveMeta();
    }
  }
}
