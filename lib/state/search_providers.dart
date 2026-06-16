import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state_holder.dart';

import '../core/jellyfin/models/items.dart';
import '../core/lyrics/lyrics_resolver.dart';
import '../core/lyrics/lrc_parser.dart';
import '../utils/log.dart';
import 'app_mode_providers.dart';
import 'detail_providers.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'player_providers.dart';

void _logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

typedef SearchResults = ({
  List<AfTrack> tracks,
  List<AfAlbum> albums,
  List<AfArtist> artists,
  List<AfPlaylist> playlists,
});

/// In-memory cache for resolved lyrics: trackId → LyricsResult.
/// This provider persists across rebuilds (not autoDispose) so that
/// lyrics resolved for one track are available when navigating back.
final lyricsCacheProvider =
    NotifierProvider<
      StateHolder<Map<String, LyricsResult>>,
      Map<String, LyricsResult>
    >(() => StateHolder<Map<String, LyricsResult>>((ref) => {}));

final sharedLyricsResolverProvider = Provider<LyricsResolver>((ref) {
  final backend = ref.watch(musicBackendProvider);
  return LyricsResolver(backend: backend!);
});

final searchProvider = FutureProvider.autoDispose.family<SearchResults, String>(
  (ref, raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      return (
        tracks: const <AfTrack>[],
        albums: const <AfAlbum>[],
        artists: const <AfArtist>[],
        playlists: const <AfPlaylist>[],
      );
    }

    final mode = ref.watch(appModeProvider);
    if (mode == null) {
      return (
        tracks: const <AfTrack>[],
        albums: const <AfAlbum>[],
        artists: const <AfArtist>[],
        playlists: const <AfPlaylist>[],
      );
    }
    if (mode == AppMode.local) {
      final lib = ref.read(localLibraryProvider);
      final tracks = await lib.search(query);
      _logData(
        'search',
        source: 'local',
        extra: 'query="$query" tracks=${tracks.length}',
      );
      return (
        tracks: tracks,
        albums: const <AfAlbum>[],
        artists: const <AfArtist>[],
        playlists: const <AfPlaylist>[],
      );
    }

    final backend = ref.watch(musicBackendProvider);
    if (backend == null) {
      _logData('search', source: 'none', extra: 'query="$query" (no backend)');
      return (
        tracks: const <AfTrack>[],
        albums: const <AfAlbum>[],
        artists: const <AfArtist>[],
        playlists: const <AfPlaylist>[],
      );
    }

    final res = await backend.search(query);
    _logData(
      'search',
      source: 'live',
      extra:
          'query="$query" tracks=${res.tracks.length} '
          'albums=${res.albums.length} artists=${res.artists.length} '
          'playlists=${res.playlists.length}',
    );
    return (
      tracks: res.tracks,
      albums: res.albums,
      artists: res.artists,
      playlists: res.playlists,
    );
  },
);

final lyricsProvider = FutureProvider.autoDispose.family<LyricsResult?, String>(
  (ref, trackId) async {
    // Check provider-level cache first
    final cache = ref.read(lyricsCacheProvider);
    final cached = cache[trackId];
    if (cached != null) return cached;

    // Resolve track metadata for NetEase/LRCLib lookups.
    Future<AfTrack?> resolveTrack(String trackId) async {
      final current = ref.read(currentTrackProvider);
      if (current != null && current.id == trackId) return current;
      try {
        final details = await ref.read(trackDetailsProvider(trackId).future);
        return details?.track;
      } on Exception catch (e) {
        afLog('lyrics', 'Track details fetch failed', error: e);
        return null;
      }
    }

    final backend = ref.watch(musicBackendProvider);
    if (backend == null) {
      afLog('lyrics', 'No backend available for $trackId');
      return null;
    }

    // Resolve track for the resolver.
    final track = await resolveTrack(trackId);
    if (track == null) {
      afLog('lyrics', 'Missing track metadata for $trackId');
      return null;
    }

    // Delegate to shared LyricsResolver — single source of truth for the
    // cascading lyrics flow: embedded → NetEase → LRCLib.
    final resolver = ref.read(sharedLyricsResolverProvider);
    final result = await resolver.resolve(trackId: trackId, track: track);

    // Populate provider-level cache
    if (result != null) {
      ref
          .read(lyricsCacheProvider.notifier)
          .update((prev) => {...prev, trackId: result});
    }

    return result;
  },
);
