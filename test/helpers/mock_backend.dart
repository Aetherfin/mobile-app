import 'package:mocktail/mocktail.dart';
import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/jellyfin/models/library.dart';

class MockMusicBackend extends Mock implements MusicBackend {}

/// Register fallback values for all types used in MusicBackend stubs.
/// Call once in `setUpAll`.
void registerBackendFallbacks() {
  registerFallbackValue(
    const AfTrack(id: '', title: '', artistName: '', albumName: ''),
  );
  registerFallbackValue(
    const AfAlbum(id: '', name: '', artistName: '', trackCount: 0),
  );
  registerFallbackValue(const AfArtist(id: '', name: ''));
  registerFallbackValue(const AfPlaylist(id: '', name: ''));
  registerFallbackValue(const AfGenre('', '#888888'));
  registerFallbackValue(ServerType.jellyfin);
  registerFallbackValue(Duration.zero);
  registerFallbackValue(
    const LibraryView(id: '', name: '', collectionType: 'music'),
  );
}
