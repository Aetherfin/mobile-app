import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../../utils/log.dart';
import '../network/shared_dio_client.dart';

/// Prefetches audio stream bytes for upcoming tracks into local temporary files
/// to facilitate smooth, gapless-like transition on completion.
///
/// Optimizations implemented:
/// - Connection pooling via shared Dio client (SharedDioClient)
/// - Exponential backoff with jitter for retries
/// - Configurable timeouts for network operations
/// - Batching support for multiple concurrent prefetches
/// - LRU cache eviction for cached files
class StreamPrefetcher {
  StreamPrefetcher({Dio? dio, int? maxConcurrent})
    : _dio = dio ?? SharedDioClient().dio,
      _maxConcurrent = maxConcurrent ?? _maxConcurrentPrefetches {
    _init();
  }

  final Dio _dio;
  final int _maxConcurrent;
  String? _cacheDir;
  bool _disposed = false;
  final Map<String, File> _cachedFiles = {};
  final Map<String, Future<File?>> _prefetchFutures = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final List<({String url, Map<String, String> headers, String trackId})>
  _prefetchQueue = [];

  /// Track total cache size for LRU eviction
  int _totalCacheSize = 0;

  /// Maximum number of concurrent prefetch operations
  static const int _maxConcurrentPrefetches = 2;

  /// Maximum cache size in bytes (100MB)
  static const int _maxCacheSizeBytes = 100 * 1024 * 1024;

  /// Maximum age of cached files in minutes
  static const int _maxCacheAgeMinutes = 2;

  /// Maximum number of cached files
  static const int _maxCachedFiles = 10;

  /// Base delay for exponential backoff in milliseconds
  static const int _baseBackoffMs = 1000;

  /// Maximum number of retry attempts
  static const int _maxRetries = 3;

  Future<void> _init() async {
    try {
      // Timeouts and connection pooling are inherited from SharedDioClient.
      final tempDir = await getTemporaryDirectory();
      _cacheDir = tempDir.path;
      await clearStaleTempFiles();
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'StreamPrefetcher init failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Returns the cached prefetch file for [trackId], if it exists and is valid.
  Future<File?> getCachedFile(String trackId) async {
    final file = _cachedFiles[trackId];
    if (file == null) return null;
    try {
      if (await file.exists()) {
        final stat = await file.stat();
        final ageMinutes = DateTime.now().difference(stat.modified).inMinutes;
        if (ageMinutes <= _maxCacheAgeMinutes) {
          return file;
        } else {
          // File is too old, remove it
          await _removeFromCache(trackId);
        }
      }
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to check cache file age for $trackId',
        error: e,
        stackTrace: stack,
      );
    }
    return null;
  }

  /// Calculates exponential backoff delay with jitter
  Duration _calculateBackoff(int retryCount) {
    // Exponential backoff: base * 2^retryCount
    final exponentialDelay = _baseBackoffMs * pow(2, retryCount);
    // Add jitter: random value between 0 and 50% of the delay
    final jitter = Random().nextDouble() * exponentialDelay * 0.5;
    final totalDelayMs = exponentialDelay + jitter;
    return Duration(milliseconds: totalDelayMs.toInt());
  }

  /// Starts prefetching the track stream at [url] to a temp file.
  ///
  /// Uses exponential backoff with jitter for retries, and supports
  /// batching multiple prefetch requests.
  Future<File?> prefetch(
    String url,
    Map<String, String> headers, {
    required String trackId,
  }) async {
    if (_disposed) return null;

    // Check if already prefetching this track
    if (_prefetchFutures.containsKey(trackId)) {
      afLog('audio', 'Prefetch already in progress for trackId=$trackId');
      return _prefetchFutures[trackId];
    }

    // Check if already cached
    final cached = await getCachedFile(trackId);
    if (cached != null) {
      afLog('audio', 'Using cached file for trackId=$trackId');
      return cached;
    }

    // Add to prefetch queue if at capacity
    if (_prefetchFutures.length >= _maxConcurrent) {
      afLog('audio', 'Prefetch queue full, adding trackId=$trackId to queue');
      _prefetchQueue.add((url: url, headers: headers, trackId: trackId));
      return null; // Will be processed when a slot opens
    }

    // Start prefetch
    final future = _doPrefetch(url, headers, trackId);
    _prefetchFutures[trackId] = future;

    unawaited(
      future
          .then((file) {
            _prefetchFutures.remove(trackId);
            _cancelTokens.remove(trackId);
            _processPrefetchQueue();
          })
          .catchError((_) {
            _prefetchFutures.remove(trackId);
            _cancelTokens.remove(trackId);
            _processPrefetchQueue();
          }),
    );

    return future;
  }

  /// Internal prefetch implementation with retry logic
  Future<File?> _doPrefetch(
    String url,
    Map<String, String> headers,
    String trackId,
  ) async {
    if (_cacheDir == null) {
      try {
        final tempDir = await getTemporaryDirectory();
        _cacheDir = tempDir.path;
      } on Exception catch (e, stack) {
        afLog(
          'audio',
          'Failed to retrieve temp dir in prefetch',
          error: e,
          stackTrace: stack,
        );
        return null;
      }
    }

    final tempFile = File(
      p.join(
        _cacheDir!,
        'prefetch_${trackId}_${DateTime.now().millisecondsSinceEpoch}.tmp',
      ),
    );

    afLog('audio', 'Starting prefetch for trackId=$trackId');

    final cancelToken = CancelToken();
    _cancelTokens[trackId] = cancelToken;

    int retryCount = 0;
    while (true) {
      try {
        final response = await _dio.get<ResponseBody>(
          url,
          options: Options(headers: headers, responseType: ResponseType.stream),
          cancelToken: cancelToken,
        );

        final body = response.data;
        if (body == null) {
          afLog('audio', 'Prefetch got null body for trackId=$trackId');
          _cancelTokens.remove(trackId);
          return null;
        }

        final sink = tempFile.openWrite();
        await body.stream.forEach(sink.add);
        await sink.close();

        // Add to cache
        await _addToCache(trackId, tempFile);

        afLog('audio', 'Prefetch completed successfully for trackId=$trackId');
        return tempFile;
      } on Exception catch (e, stack) {
        retryCount++;

        // Clean up partial file
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } on Exception catch (e, stack) {
            afLog(
              'error',
              'Prefetch temp file cleanup failed',
              error: e,
              stackTrace: stack,
            );
          }
        }

        if (e is DioException && DioExceptionType.cancel == e.type) {
          afLog('audio', 'Prefetch cancelled for trackId=$trackId');
          return null;
        }

        if (retryCount >= _maxRetries) {
          afLog(
            'audio',
            'Prefetch failed after $retryCount retries for trackId=$trackId',
            error: e,
            stackTrace: stack,
          );
          return null;
        }

        // Wait with exponential backoff before retrying
        final backoff = _calculateBackoff(retryCount);
        afLog(
          'audio',
          'Prefetch failed, retrying (retry=$retryCount) after ${backoff.inMilliseconds}ms',
          error: e,
        );
        await Future.delayed(backoff);
      }
    }
  }

  /// Process the prefetch queue when slots become available
  void _processPrefetchQueue() {
    while (_prefetchQueue.isNotEmpty &&
        _prefetchFutures.length < _maxConcurrent) {
      final request = _prefetchQueue.removeAt(0);
      unawaited(
        prefetch(request.url, request.headers, trackId: request.trackId),
      );
    }
  }

  /// Prefetches multiple tracks concurrently
  Future<List<File?>> prefetchMultiple(
    List<({String url, Map<String, String> headers, String trackId})> tracks,
  ) async {
    final futures = tracks.map(
      (t) => prefetch(t.url, t.headers, trackId: t.trackId),
    );
    return Future.wait(futures);
  }

  /// Cancels the current prefetch download and deletes the partial temp file.
  void cancelCurrentPrefetch() {
    // Cancel all in-flight Dio requests via CancelToken
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel('Prefetch cancelled');
      }
    }
    _cancelTokens.clear();
    _prefetchFutures.clear();
    _prefetchQueue.clear();
  }

  /// Adds a file to the cache with size tracking
  Future<void> _addToCache(String trackId, File file) async {
    // Remove oldest entries if cache is full
    while (_cachedFiles.length >= _maxCachedFiles ||
        _totalCacheSize >= _maxCacheSizeBytes) {
      final oldestTrackId = _cachedFiles.keys.first;
      await _removeFromCache(oldestTrackId);
    }

    try {
      final size = await file.length();
      _cachedFiles[trackId] = file;
      _totalCacheSize += size;
      afLog(
        'audio',
        'Added to cache: trackId=$trackId, size=${size ~/ 1024}KB, total=$_totalCacheSize',
      );
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to add to cache: trackId=$trackId',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Removes a file from the cache
  Future<void> _removeFromCache(String trackId) async {
    final file = _cachedFiles.remove(trackId);
    if (file != null) {
      try {
        final size = await file.length();
        _totalCacheSize -= size;
        if (await file.exists()) {
          await file.delete();
        }
        afLog(
          'audio',
          'Removed from cache: trackId=$trackId, remaining=$_totalCacheSize',
        );
      } on Exception catch (e, stack) {
        afLog(
          'audio',
          'Failed to remove from cache: trackId=$trackId',
          error: e,
          stackTrace: stack,
        );
      }
    }
  }

  /// Deletes all prefetch_*.tmp files in the temp directory that are older than threshold.
  Future<void> clearStaleTempFiles() async {
    // Fall back to system temp if _cacheDir not yet initialized (async init race)
    final dirPath = _cacheDir ?? Directory.systemTemp.path;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;

      final now = DateTime.now();
      final threshold = now.subtract(
        const Duration(minutes: _maxCacheAgeMinutes),
      );

      final files = await dir.list().toList();
      for (final f in files) {
        if (f is File &&
            p.basename(f.path).startsWith('prefetch_') &&
            f.path.endsWith('.tmp')) {
          try {
            final stat = await f.stat();
            if (stat.modified.isBefore(threshold)) {
              await f.delete();
              afLog('audio', 'Deleted stale prefetch file: ${f.path}');
            }
          } on Exception catch (e, stack) {
            afLog(
              'audio',
              'Failed to delete stale file: ${f.path}',
              error: e,
              stackTrace: stack,
            );
          }
        }
      }
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Error clearing stale temp files',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Clears all cached files
  Future<void> clearCache() async {
    for (final trackId in _cachedFiles.keys.toList()) {
      await _removeFromCache(trackId);
    }
    _cachedFiles.clear();
    _totalCacheSize = 0;
    afLog('audio', 'Cleared all cached files');
  }

  /// Releases resources held by this prefetcher.
  ///
  /// Only cancels in-flight requests — does NOT close the Dio instance
  /// because it may be the shared singleton used by other services.
  /// After disposal, [prefetch] returns `null` immediately.
  void dispose() {
    _disposed = true;
    cancelCurrentPrefetch();
  }
}
