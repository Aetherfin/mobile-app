import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../utils/log.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';

void _logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

final albumDetailProvider = FutureProvider.autoDispose
    .family<({AfAlbum album, List<AfTrack> tracks})?, String>((ref, id) async {
      if (id.startsWith('local:album:')) {
        final lib = ref.read(localLibraryProvider);
        final rest = id.substring('local:album:'.length);
        final sep = rest.lastIndexOf(':');
        if (sep < 0) return null;
        final albumName = rest.substring(0, sep);
        final artistName = rest.substring(sep + 1);
        final tracks = await lib.tracksByAlbum(albumName, artistName);
        if (tracks.isNotEmpty) {
          final album = AfAlbum(
            id: id,
            name: albumName,
            artistName: artistName,
            trackCount: tracks.length,
            imageUrl: tracks.first.imageUrl,
          );
          return (album: album, tracks: tracks);
        }
        return null;
      }

      final backend = ref.watch(musicBackendProvider);
      if (backend != null) {
        final res = await backend.album(id);
        _logData(
          'albumDetail',
          source: 'live',
          extra: 'id=$id tracks=${res?.tracks.length ?? 0}',
        );
        return res;
      }

      _logData('albumDetail', source: 'none', extra: 'id=$id (no backend)');
      return null;
    });

final trackDetailsProvider = FutureProvider.autoDispose
    .family<AfTrackDetails?, String>((ref, id) async {
      if (id.startsWith('local:') || id.startsWith('content://')) {
        final lib = ref.read(localLibraryProvider);
        final res = await lib.trackDetails(id);
        _logData(
          'trackDetails',
          source: 'local',
          extra: 'id=$id container=${res?.container} size=${res?.sizeBytes}',
        );
        return res;
      }

      final backend = ref.watch(musicBackendProvider);
      if (backend != null) {
        final res = await backend.trackDetails(id);
        _logData(
          'trackDetails',
          source: 'live',
          extra: 'id=$id container=${res?.container} size=${res?.sizeBytes}',
        );
        return res;
      }

      _logData('trackDetails', source: 'none', extra: 'id=$id (no backend)');
      return null;
    });

final artistDetailProvider = FutureProvider.autoDispose
    .family<AfArtist?, String>((ref, id) async {
      if (id.startsWith('local:artist:')) {
        final name = id.substring('local:artist:'.length);
        return AfArtist(id: id, name: name, albumCount: 0);
      }

      final backend = ref.watch(musicBackendProvider);
      if (backend != null) {
        final res = await backend.artist(id);
        _logData(
          'artistDetail',
          source: 'live',
          extra: 'id=$id found=${res != null}',
        );
        return res;
      }

      _logData('artistDetail', source: 'none', extra: 'id=$id (no backend)');
      return null;
    });

final artistAlbumsProvider = FutureProvider.autoDispose
    .family<List<AfAlbum>, String>((ref, artistId) async {
      if (artistId.startsWith('local:artist:')) {
        final name = artistId.substring('local:artist:'.length);
        final allAlbums = await ref.read(localLibraryProvider).albums();
        return allAlbums.where((a) => a.artistName == name).toList();
      }

      final backend = ref.watch(musicBackendProvider);
      if (backend == null) {
        _logData(
          'artistAlbums',
          source: 'none',
          extra: 'artistId=$artistId (no backend)',
        );
        return const <AfAlbum>[];
      }

      final res = await backend.artistAlbums(artistId);
      _logData(
        'artistAlbums',
        source: 'live',
        extra: 'artistId=$artistId count=${res.length}',
      );
      return res;
    });

final artistTopTracksProvider = FutureProvider.autoDispose
    .family<List<AfTrack>, String>((ref, artistId) async {
      if (artistId.startsWith('local:artist:')) {
        final name = artistId.substring('local:artist:'.length);
        final tracks = await ref
            .read(localLibraryProvider)
            .tracksByArtist(name);
        return tracks.take(10).toList();
      }

      final backend = ref.watch(musicBackendProvider);
      if (backend == null) {
        _logData(
          'artistTopTracks',
          source: 'none',
          extra: 'artistId=$artistId (no backend)',
        );
        return const <AfTrack>[];
      }

      final res = await backend.artistTopTracks(artistId, limit: 100);
      _logData(
        'artistTopTracks',
        source: 'live',
        extra: 'artistId=$artistId count=${res.length}',
      );
      return res;
    });
