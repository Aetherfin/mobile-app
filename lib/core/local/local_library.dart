import '../jellyfin/models/items.dart';
import 'app_database.dart';
import 'local_db.dart';
import 'metadata_scanner.dart';
import 'saf_picker.dart';

/// High-level interface for the local music library.
///
/// Wraps [LocalDb] and [MetadataScanner] to provide a clean API for
/// providers and UI code. Analogous to [MusicBackend] but for local files.
class LocalLibrary {
  LocalLibrary({AppDatabase? database})
    : _db = LocalDb(db: database ?? AppDatabase()) {
    _scanner = MetadataScanner(_db);
  }
  final LocalDb _db;
  late final MetadataScanner _scanner;

  /// Expose the underlying DB for direct queries (e.g. smart playlists).
  LocalDb get db => _db;

  // ── Folder management ───────────────────────────────────────────────────

  /// Pick a folder via SAF and persist it. Returns the tree URI or null.
  Future<String?> pickAndAddFolder() async {
    final uri = await SafPicker.pickFolder();
    if (uri == null) return null;
    // Use the last path segment as display name
    final displayPath = Uri.parse(uri).pathSegments.lastOrNull ?? uri;
    await _db.addFolder(uri, displayPath);
    return uri;
  }

  /// Add a folder that was already picked (e.g. restored from DB).
  Future<void> addFolder(String uri, String displayPath) async {
    await _db.addFolder(uri, displayPath);
  }

  /// Remove a folder and all its tracks from the library.
  Future<void> removeFolder(String uri) async {
    await _db.removeFolder(uri);
  }

  /// Get all registered folders.
  Future<List<({String uri, String displayPath})>> getFolders() async {
    final rows = await _db.getFolders();
    return rows
        .map(
          (r) => (
            uri: r['uri'] as String,
            displayPath: r['display_path'] as String,
          ),
        )
        .toList();
  }

  // ── Scanning ────────────────────────────────────────────────────────────

  /// Scan all registered folders. Reports progress via callback.
  Future<int> scanAll({
    void Function(int completed, int total)? onProgress,
  }) async {
    final folders = await _db.getFolders();
    int totalInserted = 0;
    for (final folder in folders) {
      final uri = folder['uri'] as String;
      // Remove tracks that no longer exist on disk before scanning.
      await _scanner.pruneDeletedFiles(uri);
      totalInserted += await _scanner.scanFolder(uri, onProgress: onProgress);
    }
    return totalInserted;
  }

  /// Scan a single folder.
  Future<int> scanFolder(
    String treeUri, {
    void Function(int completed, int total)? onProgress,
  }) async {
    return _scanner.scanFolder(treeUri, onProgress: onProgress);
  }

  // ── Library queries ─────────────────────────────────────────────────────

  Future<List<AfAlbum>> albums() => _db.allAlbums();

  Future<List<AfArtist>> artists() => _db.allArtists();

  Future<List<AfTrack>> tracks({int limit = 500}) =>
      _db.allTracks(limit: limit);

  Future<List<AfGenre>> genres() => _db.allGenres();

  Future<List<AfTrack>> tracksByAlbum(String albumName, String artistName) =>
      _db.tracksByAlbum(albumName, artistName);

  Future<List<AfTrack>> tracksByArtist(String artistName, {int? limit}) =>
      _db.tracksByArtist(artistName, limit: limit);

  Future<List<AfTrack>> tracksByGenre(String genre, {int limit = 500}) =>
      _db.tracksByGenre(genre, limit: limit);

  Future<List<AfTrack>> search(String query) => _db.searchTracks(query);

  Future<int> trackCount() => _db.trackCount();

  /// Full per-track detail for a local file — container, file size,
  /// bitrate, sample rate, path, genre. Used by the "Show details"
  /// sheet in local mode.
  Future<AfTrackDetails?> trackDetails(String id) => _db.trackDetailsById(id);

  // ── Lifecycle ───────────────────────────────────────────────────────────
  // AppDatabase lifecycle is managed by appDatabaseProvider — individual
  // consumers (LocalLibrary, SmartPlaylistDb) should NOT close it.

  Future<void> close() async {}
}
