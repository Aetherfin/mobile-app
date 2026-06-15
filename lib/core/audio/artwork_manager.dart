import 'dart:convert' show utf8;
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show CoverArt;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/log.dart';
import '../../utils/url.dart';
import '../jellyfin/models/items.dart';
import 'artwork_disk_cache.dart';

/// Manages cover art persistence and notification artwork download.
///
/// Handles two sources of cover art:
/// 1. mpv's `coverArt` stream (embedded audio file art) → persisted to temp file
/// 2. Remote artwork URLs → downloaded to temp file for notification display
///
/// Optimizations implemented:
/// - Shared HttpClient across all instances
/// - Two-level caching (memory + disk)
/// - LRU eviction for memory cache
/// - Disk cache with TTL and size limits (delegated to [ArtworkDiskCache])
///
/// Tracks the latest cover path so [artUri] always returns the current best
/// available artwork URI for native notification updates.
class AfArtworkManager {
  /// Shared HttpClient instance for all AfArtworkManager instances
  static final HttpClient _sharedHttpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 15);

  /// Maximum memory cache entries
  static const int _memoryCacheSize = 50;

  /// Cleans up orphan `.tmp` files left behind by aborted or crashed
  /// [persistCover] / [downloadArtworkForNotification] calls.
  static Future<void> cleanupOrphanTempFiles() async {
    try {
      final tmpDir = Directory.systemTemp;
      final orphans = <File>[];
      await for (final entity in tmpDir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('aetherfin_') && name.endsWith('.tmp')) {
            orphans.add(entity);
          }
        }
      }
      if (orphans.isEmpty) return;
      for (final f in orphans) {
        try {
          await f.delete();
        } on Exception catch (e, stack) {
          afLog(
            'audio',
            'Failed to delete orphan temp file',
            error: e,
            stackTrace: stack,
          );
        }
      }
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to list temp directory for orphan cleanup',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Called when artwork is persisted or downloaded so the owner can
  /// update the native notification artwork.
  void Function()? onArtworkChanged;

  /// Called when cover art extracted by mpv is saved permanently to the
  /// cover cache. The callback receives (trackId, coverPath) so the
  /// caller can update the DB `cover_path` column.
  void Function(String trackId, String coverPath)? onPermanentCoverSaved;

  /// Directory for permanent cover art cache. Lazily initialized.
  String? _permanentCoverCacheDir;

  int _coverCounter = 0;
  String? _coverPath;
  String? _networkCoverPath;
  Map<String, String> _authHeaders = const <String, String>{};
  String? _networkCoverTrackId;
  bool _disposed = false;

  /// Memory cache: trackId -> file path
  final Map<String, String> _memoryCache = {};

  /// Disk cache (delegates to [ArtworkDiskCache] for persistence).
  final ArtworkDiskCache _diskCache = ArtworkDiskCache();

  /// Cache of file paths confirmed to exist via [File.existsSync].
  /// Avoids repeated sync disk I/O on the hot path called every 2 seconds
  /// from [updateMediaSession]. Cleared when artwork changes.
  final Set<String> _existsCache = {};

  /// Update the auth headers used for authenticated artwork downloads.
  void setAuthHeaders(Map<String, String> headers) {
    _authHeaders = headers;
  }

  /// Returns the best available artwork URI for the given track, or `null`
  /// when neither local nor remote cover is ready.
  Uri? artUri(AfTrack track) {
    if (_coverPath != null) return Uri.file(_coverPath!);
    if (_memoryCache.containsKey(track.id)) {
      return Uri.file(_memoryCache[track.id]!);
    }
    if (_networkCoverPath != null && _networkCoverTrackId == track.id) {
      return Uri.file(_networkCoverPath!);
    }
    final diskCached = _diskCache.getPath(track.id);
    if (diskCached != null) return Uri.file(diskCached);
    if (track.imageUrl != null && track.imageUrl!.startsWith('file://')) {
      // Verify the file exists before returning — cover_cache_manager
      // evicts files without nulling cover_path in the DB, so the path
      // can be stale between scans. Uses _existsCache to avoid repeated
      // sync disk I/O on the hot path (called every 2 seconds).
      final filePath = track.imageUrl!.substring('file://'.length);
      if (_existsCache.contains(filePath) || File(filePath).existsSync()) {
        _existsCache.add(filePath);
        return Uri.parse(track.imageUrl!);
      }
    }
    return null;
  }

  /// Returns `true` when a remote artwork download is needed for this track.
  bool needsRemoteArtwork(AfTrack track) =>
      track.imageUrl != null &&
      !track.imageUrl!.startsWith('file://') &&
      !(_networkCoverTrackId == track.id && _networkCoverPath != null) &&
      !_memoryCache.containsKey(track.id) &&
      _diskCache.getPath(track.id) == null;

  /// Persist embedded cover art from mpv's `coverArt` stream to a temp file.
  Future<void> persistCover(CoverArt? raw) async {
    if (_disposed) return;
    if (raw == null) {
      _coverPath = null;
      return;
    }

    final ext = raw.extension.isNotEmpty ? raw.extension : 'jpg';
    final tmpDir = Directory.systemTemp.path;
    final path =
        '$tmpDir${Platform.pathSeparator}aetherfin_cover_${++_coverCounter}.$ext';

    try {
      final tmpPath = '$path.tmp';
      await File(tmpPath).writeAsBytes(raw.bytes);

      if (_coverPath != null) {
        final prev = File(_coverPath!);
        if (await prev.exists()) {
          await prev.delete();
        }
      }

      await File(tmpPath).rename(path);
      _coverPath = path;
      _networkCoverPath = null;
      _networkCoverTrackId = null;
      _existsCache.clear();
      onArtworkChanged?.call();
    } on Exception catch (e, stack) {
      afLog('audio', 'cover art persist failed', error: e, stackTrace: stack);
    }
  }

  /// Save mpv-extracted cover art permanently to the cover cache directory.
  ///
  /// Uses the same filename scheme as [MetadataScanner] (SHA-1 of track ID)
  /// so subsequent scans find the cached file and skip re-extraction.
  /// Calls [onPermanentCoverSaved] with the saved path so the caller can
  /// update the DB `cover_path` column.
  Future<void> persistCoverToPermanentCache(
    String trackId,
    CoverArt raw,
  ) async {
    if (_disposed) return;
    try {
      _permanentCoverCacheDir ??= await _resolveCoverCacheDir();
      final cacheDir = _permanentCoverCacheDir!;
      await Directory(cacheDir).create(recursive: true);

      final digest = sha1.convert(utf8.encode(trackId)).toString();
      final filename = '${digest.substring(0, 16)}.jpg';
      final coverPath = p.join(cacheDir, filename);

      // Skip if already cached (idempotent).
      if (await File(coverPath).exists()) return;

      final tmpPath = '$coverPath.tmp';
      await File(tmpPath).writeAsBytes(raw.bytes);
      await File(tmpPath).rename(coverPath);

      afLog('audio', 'cover art saved permanently for $trackId');
      onPermanentCoverSaved?.call(trackId, coverPath);
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'permanent cover save failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Resolve the permanent cover cache directory path.
  ///
  /// Uses the same location as [MetadataScanner]: `<appCacheDir>/local_covers`.
  Future<String> _resolveCoverCacheDir() async {
    final appDir = await getApplicationCacheDirectory();
    return p.join(appDir.path, 'local_covers');
  }

  /// Download artwork from a remote URL for use in the notification/
  /// lockscreen.
  Future<void> downloadArtworkForNotification(AfTrack track) async {
    if (_disposed) return;
    await _diskCache.init();

    var imageUrl = track.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) return;

    // Upgrade YouTube/Google usercontent thumbnails to high quality (2048x2048).
    imageUrl = upgradeYtThumbnail(imageUrl);

    // Check memory cache first
    if (_memoryCache.containsKey(track.id)) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = _memoryCache[track.id];
      onArtworkChanged?.call();
      return;
    }

    // Check disk cache
    final diskCached = _diskCache.getPath(track.id);
    if (diskCached != null) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = diskCached;
      _memoryCache[track.id] = diskCached;
      if (_memoryCache.length > _memoryCacheSize) {
        _memoryCache.remove(_memoryCache.keys.first);
      }
      onArtworkChanged?.call();
      return;
    }

    // Local file:// URL
    if (imageUrl.startsWith('file://')) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = imageUrl.substring('file://'.length);
      _memoryCache[track.id] = _networkCoverPath!;
      onArtworkChanged?.call();
      return;
    }

    // Download from remote URL
    final path = await _diskCache.downloadFromUrl(
      track.id,
      imageUrl,
      _authHeaders,
      _sharedHttpClient,
    );
    if (path == null || _disposed) return;

    if (_networkCoverPath != null) {
      try {
        final prev = File(_networkCoverPath!);
        if (await prev.exists()) await prev.delete();
      } on Exception catch (e, stack) {
        afLog(
          'audio',
          'Failed to delete previous network cover',
          error: e,
          stackTrace: stack,
        );
      }
    }

    _networkCoverPath = path;
    _networkCoverTrackId = track.id;
    _memoryCache[track.id] = path;
    if (_memoryCache.length > _memoryCacheSize) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    onArtworkChanged?.call();
  }

  /// Clears all artwork caches
  Future<void> clearCache() async {
    _memoryCache.clear();
    await _diskCache.clear();
    _coverPath = null;
    _networkCoverPath = null;
    _networkCoverTrackId = null;
    _existsCache.clear();
  }

  void dispose() {
    _disposed = true;
    _memoryCache.clear();
    _existsCache.clear();
    _diskCache.resetTracking();
  }
}
