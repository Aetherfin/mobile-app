import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' show min;

import 'package:crypto/crypto.dart' show sha1;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/audio/spectral_extractor.dart';
import '../../utils/log.dart';
import 'cover_cache_manager.dart';
import 'local_db.dart';
import 'saf_picker.dart';

/// Orchestrates scanning SAF folders: lists files → reads metadata → inserts
/// into the local SQLite database. Reports progress via a callback.
class MetadataScanner {
  MetadataScanner(this.db);
  final LocalDb db;
  bool _isScanning = false;
  CoverCacheManager? _coverCacheManager;
  final SpectralExtractor _spectralExtractor = SpectralExtractor();

  /// Check scanning state to allow UI buttons to show progress or disable themselves.
  bool get isScanning => _isScanning;

  /// Cache of folder artwork paths: SAF URI → cover file path.
  /// Populated during scan, used to assign folder artwork to tracks
  /// that don't have embedded cover art.
  final Map<String, String> _folderArtworkCache = {};

  /// Scan a folder tree URI. Calls [onProgress] with (completed, total).
  /// Returns the number of tracks inserted/updated.
  Future<int> scanFolder(
    String treeUri, {
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_isScanning) {
      afLog('local', 'scanFolder bypassed: scan already in progress');
      return 0;
    }

    _isScanning = true;
    try {
      afLog('local', 'scanFolder start: $treeUri');

      // 1. List all audio files
      final files = await _listFiles(treeUri);
      afLog('local', 'found ${files.length} audio files');

      if (files.isEmpty) return 0;

      int completed = 0;
      int inserted = 0;
      final coverCacheDir = await _coverCacheDir();
      _coverCacheManager ??= await CoverCacheManager.create(
        cacheDir: coverCacheDir,
      );

      // 2. Evict OLD covers BEFORE extracting new ones.
      // This prevents newly extracted covers from being immediately evicted.
      final evicted = await _coverCacheManager?.evictIfNeeded() ?? 0;
      if (evicted > 0) {
        afLog('local', 'evicted $evicted stale cover art files before scan');
        // Null out cover_path for tracks whose cover files were just evicted.
        final nulled = await db.nullStaleCoverPaths();
        if (nulled > 0) {
          afLog('local', 'nulled $nulled stale cover_path entries before scan');
        }
      }

      // 3. Batch-load scan info for all files in this folder,
      //    replacing N per-file DB queries with a single SELECT.
      final prefix = treeUri.endsWith('/') ? treeUri : '$treeUri/';
      final scanInfo = await db.getTrackScanInfoByPrefix(prefix);

      // 3. Process in chunks: metadata reads fire concurrently per chunk
      //    (MethodChannel calls are independent), cover art + disk writes
      //    remain sequential. DB batch writes stay sequential (SQLite single-writer).
      const chunkSize = 10;
      final batch = <Map<String, dynamic>>[];

      for (var i = 0; i < files.length; i += chunkSize) {
        final end = min(i + chunkSize, files.length);
        final chunk = files.sublist(i, end);

        // Separate files that need processing from those already cached.
        final (:toProcess, :coverOnly) = await _separateNewFromCached(
          chunk,
          scanInfo,
          coverCacheDir,
        );
        completed += chunk.length - toProcess.length;
        onProgress?.call(completed, files.length);

        if (toProcess.isEmpty && coverOnly.isEmpty) continue;

        // Retry cover art extraction for files that have metadata but
        // are missing cover art (extraction failed on a previous scan).
        for (final file in coverOnly) {
          final coverFile = File(
            p.join(coverCacheDir, _coverFilename(file.uri)),
          );
          if (await coverFile.exists()) {
            // File exists on disk — just make sure DB points to it.
            await db.updateCoverPath(file.uri, coverFile.path);
            _coverCacheManager?.trackAccess(coverFile.path);
            continue;
          }
          try {
            final artBytes = await SafPicker.readCoverArt(file.uri);
            if (artBytes != null && artBytes.isNotEmpty) {
              await coverFile.writeAsBytes(artBytes);
              // Update ONLY cover_path — don't corrupt the rest of the row.
              await db.updateCoverPath(file.uri, coverFile.path);
              _coverCacheManager?.trackAccess(coverFile.path);
              afLog('local', 'cover art recovered for ${file.name}');
            }
          } on Exception catch (e, stack) {
            afLog(
              'local',
              'cover art retry failed for ${file.name}',
              error: e,
              stackTrace: stack,
            );
          }
        }

        if (toProcess.isEmpty) continue;

        // Fire all metadata reads concurrently within this chunk.
        final results = await _processChunk(toProcess);

        // Process results sequentially: cover art reads/writes + batch build.
        for (final result in results) {
          final file = result.file;
          final meta = result.meta;

          if (meta != null) {
            final title = meta.title?.isNotEmpty == true
                ? meta.title!
                : _titleFromFilename(file.name);

            // Extract cover art + spectral hue
            final (:coverPath, :spectralHue) = await _extractCoverArtForTrack(
              file,
              coverCacheDir,
            );

            batch.add({
              'id': file.uri,
              'title': title,
              'artist': meta.artist ?? '',
              'album': meta.album ?? '',
              'album_artist': meta.albumArtist ?? '',
              'track_number': meta.trackNum,
              'duration_ms': meta.durationMs,
              'year': meta.yearInt,
              'genre': meta.genre ?? '',
              'file_path': file.name,
              'file_size': file.size,
              'last_modified': file.lastModified,
              'cover_path': coverPath,
              'codec': meta.codec,
              'bitrate': meta.bitrateKbps,
              'sample_rate': meta.sampleRateHz,
              'spectral_hue': spectralHue,
            });

            inserted++;
          }

          completed++;
          onProgress?.call(completed, files.length);

          // Flush batch every 50 tracks
          if (batch.length >= 50) {
            await _flushBatch(batch);
            batch.clear();
          }
        }
      }

      // Flush remaining
      if (batch.isNotEmpty) {
        await _flushBatch(batch);
      }

      // Propagate album art: copy cover_path from tracks that have art
      // to all tracks in the same album. This ensures consistent album
      // art across all tracks, even if only one has embedded cover art.
      final propagated = await db.propagateAlbumArt();

      afLog(
        'local',
        'scanFolder done: $inserted tracks inserted/updated, $propagated tracks got album art',
      );
      return inserted;
    } finally {
      _isScanning = false;
    }
  }

  /// Remove tracks from DB that no longer exist on disk for a given folder.
  ///
  /// Membership test: SAF document URIs for files inside [treeUri] always
  /// take the form `<treeUri>/document/<encodedDocId>`, so we test for the
  /// `<treeUri>/` boundary instead of a raw `startsWith(treeUri)`.
  ///
  /// Without the trailing slash, two sibling folders whose tree URIs share
  /// a prefix — e.g. `…/tree/primary%3AMusic` and
  /// `…/tree/primary%3AMusic2` — would alias: pruning Music would treat
  /// all of Music2's documents as candidates, never find them in
  /// Music's directory listing, and silently delete them from the DB.
  Future<int> pruneDeletedFiles(String treeUri) async {
    final files = await SafPicker.listAudioFiles(treeUri);
    final existingUris = files.map((f) => f.uri).toSet();
    final prefix = treeUri.endsWith('/') ? treeUri : '$treeUri/';

    final trackIds = await db.trackIdsByPrefix(prefix);
    final idsToDelete = <String>[];
    for (final id in trackIds) {
      if (!existingUris.contains(id)) {
        idsToDelete.add(id);
      }
    }
    if (idsToDelete.isEmpty) return 0;
    await db.deleteTracksByIds(idsToDelete);
    final pruned = idsToDelete.length;
    if (pruned > 0) {
      afLog('local', 'pruned $pruned deleted tracks');
    }
    return pruned;
  }

  // ── Extracted helpers ─────────────────────────────────────────────────────

  // ponytail: extracted from scanFolder for readability
  Future<List<SafFile>> _listFiles(String treeUri) {
    return SafPicker.listAudioFiles(treeUri);
  }

  // ponytail: extracted from scanFolder for readability
  Future<({List<SafFile> toProcess, List<SafFile> coverOnly})>
  _separateNewFromCached(
    List<SafFile> chunk,
    Map<String, ({int? lastModified, bool hasCover})> scanInfo,
    String coverCacheDir,
  ) async {
    final toProcess = <SafFile>[];
    final coverOnly = <SafFile>[];
    for (final file in chunk) {
      final info = scanInfo[file.uri];
      if (info != null && info.lastModified == file.lastModified) {
        if (!info.hasCover) {
          // Check if we have a no-art marker (skip if track has no art)
          if (!_hasNoArtMarker(file.uri, coverCacheDir)) {
            coverOnly.add(file);
          }
        } else if (info.hasCover) {
          // DB says cover exists — verify file is actually on disk.
          final coverFile = File(
            p.join(coverCacheDir, _coverFilename(file.uri)),
          );
          if (!await coverFile.exists()) {
            // Cover evicted from disk but DB is stale — retry extraction.
            coverOnly.add(file);
          }
        }
      } else {
        toProcess.add(file);
      }
    }
    return (toProcess: toProcess, coverOnly: coverOnly);
  }

  // ponytail: extracted from scanFolder for readability
  Future<List<_ChunkResult>> _processChunk(List<SafFile> toProcess) {
    return Future.wait(
      toProcess.map(
        (f) => SafPicker.readMetadata(f.uri).then(
          (m) => _ChunkResult(f, m),
          onError: (Object e, StackTrace stack) {
            afLog(
              'local',
              'metadata read failed for ${f.name}',
              error: e,
              stackTrace: stack,
            );
            return _ChunkResult(f, null);
          },
        ),
      ),
    );
  }

  // ponytail: extracted from scanFolder for readability
  Future<({String? coverPath, double? spectralHue})> _extractCoverArtForTrack(
    SafFile file,
    String coverCacheDir,
  ) async {
    String? coverPath;
    final coverFile = File(p.join(coverCacheDir, _coverFilename(file.uri)));
    if (!await coverFile.exists()) {
      try {
        final artBytes = await SafPicker.readCoverArt(file.uri);
        if (artBytes != null && artBytes.isNotEmpty) {
          await coverFile.writeAsBytes(artBytes);
          coverPath = coverFile.path;
          _coverCacheManager?.trackAccess(coverFile.path);
        } else {
          // No embedded artwork — try folder artwork fallback
          coverPath = await _findFolderArtwork(file.uri, coverCacheDir);
          // If still no art, create marker to skip future retries
          if (coverPath == null) {
            _createNoArtMarker(file.uri, coverCacheDir);
          }
        }
      } on Exception catch (e, stack) {
        afLog(
          'local',
          'readCoverArt failed for ${file.name}',
          error: e,
          stackTrace: stack,
        );
      }
    } else {
      coverPath = coverFile.path;
      _coverCacheManager?.trackAccess(coverFile.path);
    }

    // Generate spectral hue from cover art for instant palette lookup
    double? spectralHue;
    if (coverPath != null) {
      try {
        spectralHue = await _spectralExtractor.extractHueFromArtwork(coverPath);
      } on Exception catch (e, stack) {
        afLog(
          'local',
          'spectral hue extraction failed for ${file.name}',
          error: e,
          stackTrace: stack,
        );
      }
    }
    return (coverPath: coverPath, spectralHue: spectralHue);
  }

  // ponytail: extracted from scanFolder for readability
  Future<void> _flushBatch(List<Map<String, dynamic>> batch) {
    return db.upsertTracks(batch);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Future<String> _coverCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'local_covers'));
    // create(recursive: true) is idempotent — no need for an existsSync
    // pre-check, which is also racy against a concurrent scan.
    await dir.create(recursive: true);

    // Migrate covers from old cache location to documents (one-time).
    // Android can clean getApplicationCacheDirectory() when storage is low,
    // causing artwork to disappear. Documents directory is persistent.
    await _migrateCoversFromCache(dir.path);

    return dir.path;
  }

  /// One-time migration: move cover files from the old cache directory
  /// to the new documents directory. Silently ignores errors.
  static bool _migrated = false;
  Future<void> _migrateCoversFromCache(String newDir) async {
    if (_migrated) return;
    _migrated = true;
    try {
      final oldAppDir = await getApplicationCacheDirectory();
      final oldDir = Directory(p.join(oldAppDir.path, 'local_covers'));
      if (!await oldDir.exists()) return;

      await for (final entity in oldDir.list()) {
        if (entity is File) {
          final filename = p.basename(entity.path);
          final newPath = p.join(newDir, filename);
          if (!await File(newPath).exists()) {
            await entity.rename(newPath);
          } else {
            await entity.delete();
          }
        }
      }
      // Clean up old directory if empty.
      if (await oldDir.exists()) {
        await oldDir.delete(recursive: true);
      }
    } on Exception catch (e, stack) {
      afLog(
        'local',
        'cover migration failed (non-fatal)',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Generate a stable filename for cover art cache from the file URI.
  ///
  /// Dart's `String.hashCode` is a 32-bit value, so by the birthday
  /// paradox two distinct URIs collide with ~50% probability around
  /// 65k tracks — well within "a serious music library" territory.
  /// SHA-1 truncated to 16 hex chars (64 bits) pushes the 50% collision
  /// threshold past 2 ^ 32 entries, which we will never hit.
  String _coverFilename(String uri) {
    final digest = sha1.convert(utf8.encode(uri)).toString();
    return '${digest.substring(0, 16)}.jpg';
  }

  /// Derive a title from the filename (strip extension, replace underscores).
  String _titleFromFilename(String filename) {
    final withoutExt = p.basenameWithoutExtension(filename);
    // Strip leading track numbers like "01 - " or "01. "
    final stripped = withoutExt.replaceFirst(RegExp(r'^\d{1,3}[\s._-]+'), '');
    return stripped.replaceAll('_', ' ').trim();
  }

  /// Find and cache folder artwork for a given audio file.
  ///
  /// Checks the parent folder for common artwork filenames (cover.jpg,
  /// folder.jpg, front.jpg, etc.) and caches the first match.
  /// Returns the cached cover path if found, null otherwise.
  Future<String?> _findFolderArtwork(
    String audioFileUri,
    String coverCacheDir,
  ) async {
    // Check if we already have folder artwork for this file's directory
    if (_folderArtworkCache.containsKey(audioFileUri)) {
      return _folderArtworkCache[audioFileUri];
    }

    try {
      final files = await SafPicker.listFilesInParentFolder(audioFileUri);

      // Look for common artwork filenames
      for (final file in files) {
        if (!file.isImage) continue;

        final nameWithoutExt = file.nameWithoutExt ?? '';
        if (_isArtworkFilename(nameWithoutExt)) {
          // Read the image bytes
          final bytes = await SafPicker.readCoverArt(file.uri);
          if (bytes != null && bytes.isNotEmpty) {
            // Cache using a hash of the parent folder URI
            final folderHash = sha1
                .convert(utf8.encode(audioFileUri))
                .toString();
            final cachePath = p.join(
              coverCacheDir,
              '${folderHash.substring(0, 16)}.jpg',
            );
            await File(cachePath).writeAsBytes(bytes);
            _coverCacheManager?.trackAccess(cachePath);

            // Cache for all files in this folder
            _folderArtworkCache[audioFileUri] = cachePath;
            afLog('local', 'found folder artwork: ${file.name}');
            return cachePath;
          }
        }
      }
    } on Exception catch (e, stack) {
      afLog(
        'local',
        'folder artwork search failed',
        error: e,
        stackTrace: stack,
      );
    }

    return null;
  }

  /// Check if a filename (without extension) is a common artwork filename.
  bool _isArtworkFilename(String name) {
    const coverNames = {
      'cover',
      'folder',
      'front',
      'album',
      'albumart',
      'albumartsmall',
      'thumb',
      'thumbnail',
      'art',
      'image',
    };
    return coverNames.contains(name.toLowerCase());
  }

  /// Check if a track has a no-art marker file.
  /// This prevents re-extraction for tracks known to have no embedded art.
  bool _hasNoArtMarker(String trackUri, String coverCacheDir) {
    final markerPath = p.join(
      coverCacheDir,
      '${_coverFilename(trackUri)}.noart',
    );
    return File(markerPath).existsSync();
  }

  /// Create a no-art marker file for a track.
  void _createNoArtMarker(String trackUri, String coverCacheDir) {
    final markerPath = p.join(
      coverCacheDir,
      '${_coverFilename(trackUri)}.noart',
    );
    File(markerPath).writeAsStringSync('');
  }
}

/// Holds a file together with its metadata result from a concurrent read.
class _ChunkResult {
  _ChunkResult(this.file, this.meta);
  final SafFile file;
  final SafMetadata? meta;
}
