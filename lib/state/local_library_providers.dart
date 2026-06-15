import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../core/local/app_database.dart';
import '../core/local/local_library.dart';

/// Shared database connection owned by the provider scope. Both
/// [LocalLibrary] and [SmartPlaylistDb] receive the same instance so
/// they share a single SQLite connection instead of each opening an
/// independent one.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final localLibraryProvider = Provider<LocalLibrary>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalLibrary(database: db);
});

final localAlbumsProvider = FutureProvider.autoDispose<List<AfAlbum>>((ref) {
  ref.keepAlive();
  final lib = ref.watch(localLibraryProvider);
  return lib.albums();
});

final localArtistsProvider = FutureProvider.autoDispose<List<AfArtist>>((ref) {
  ref.keepAlive();
  final lib = ref.watch(localLibraryProvider);
  return lib.artists();
});

final localTracksProvider = FutureProvider.autoDispose<List<AfTrack>>((ref) {
  ref.keepAlive();
  final lib = ref.watch(localLibraryProvider);
  return lib.tracks();
});

final localGenresProvider = FutureProvider.autoDispose<List<AfGenre>>((ref) {
  ref.keepAlive();
  final lib = ref.watch(localLibraryProvider);
  return lib.genres();
});
