import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../utils/log.dart';
import 'music_backend_providers.dart';

// ── Pagination helpers ─────────────────────────────────────────────────────

/// Holds pagination state for a paginated list.
class PaginationState<T> {
  const PaginationState({
    this.items = const [],
    this.currentPage = 0,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });
  final List<T> items;
  final int currentPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  PaginationState<T> copyWith({
    List<T>? items,
    int? currentPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
  }) => PaginationState<T>(
    items: items ?? this.items,
    currentPage: currentPage ?? this.currentPage,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: error,
  );
}

/// Manages paginated track loading via [MusicBackend.allTracks()].
class TracksNotifier extends AutoDisposeNotifier<PaginationState<AfTrack>> {
  static const _pageSize = 100;

  @override
  PaginationState<AfTrack> build() {
    Future.microtask(loadFirstPage);
    return const PaginationState<AfTrack>();
  }

  /// Fetch the first page of tracks.
  Future<void> loadFirstPage() async {
    state = state.copyWith(isLoadingMore: true, error: null);
    try {
      final backend = ref.read(musicBackendProvider);
      if (backend == null) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
        return;
      }
      logData('allTracks', source: 'live');
      final tracks = await backend.allTracks(limit: _pageSize, startIndex: 0);
      state = PaginationState<AfTrack>(
        items: tracks,
        currentPage: 0,
        hasMore: tracks.length >= _pageSize,
      );
    } on Exception catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  /// Fetch the next page of tracks (appended to existing items).
  Future<void> loadNextPage() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final backend = ref.read(musicBackendProvider);
      if (backend == null) return;
      final startIndex = (state.currentPage + 1) * _pageSize;
      final tracks = await backend.allTracks(
        limit: _pageSize,
        startIndex: startIndex,
      );
      state = PaginationState<AfTrack>(
        items: [...state.items, ...tracks],
        currentPage: state.currentPage + 1,
        hasMore: tracks.length >= _pageSize,
      );
    } on Exception catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }
}

/// Provider for paginated track list (replaces direct [allTracksProvider]
/// usage in screens that support infinite scroll).
final tracksPaginationProvider =
    NotifierProvider.autoDispose<TracksNotifier, PaginationState<AfTrack>>(
      TracksNotifier.new,
    );

final recentlyAddedAlbumsProvider = FutureProvider.autoDispose<List<AfAlbum>>((
  ref,
) async {
  ref.keepAlive();
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    logData('recentlyAddedAlbums', source: 'demo', extra: '(signed out)');
    return const <AfAlbum>[];
  }
  final res = await backend.recentlyAddedAlbums();
  logData('recentlyAddedAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

final recentlyPlayedTracksProvider = FutureProvider.autoDispose<List<AfTrack>>((
  ref,
) async {
  ref.keepAlive();
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    logData('recentlyPlayedTracks', source: 'demo', extra: '(signed out)');
    return const <AfTrack>[];
  }
  final res = await backend.recentlyPlayed();
  logData('recentlyPlayedTracks', source: 'live', extra: 'count=${res.length}');
  return res;
});

final allArtistsProvider = FutureProvider.autoDispose<List<AfArtist>>((
  ref,
) async {
  ref.keepAlive();
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    logData('allArtists', source: 'demo', extra: '(signed out)');
    return const <AfArtist>[];
  }
  final res = await backend.artists();
  logData('allArtists', source: 'live', extra: 'count=${res.length}');
  return res;
});

final allPlaylistsProvider = FutureProvider.autoDispose<List<AfPlaylist>>((
  ref,
) async {
  ref.keepAlive();
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    logData('allPlaylists', source: 'demo', extra: '(signed out)');
    return const <AfPlaylist>[];
  }
  final res = await backend.playlists();
  logData('allPlaylists', source: 'live', extra: 'count=${res.length}');
  return res;
});

final savedTrackIdsProvider = StateProvider<Set<String>>((ref) => <String>{});

final allAlbumsProvider = FutureProvider.autoDispose<List<AfAlbum>>((
  ref,
) async {
  ref.keepAlive();
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    logData('allAlbums', source: 'demo', extra: '(signed out)');
    return const <AfAlbum>[];
  }
  final res = await backend.allAlbums();
  logData('allAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

final allTracksProvider = FutureProvider.autoDispose<List<AfTrack>>((
  ref,
) async {
  ref.keepAlive();
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    logData('allTracks', source: 'demo', extra: '(signed out)');
    return const <AfTrack>[];
  }
  final res = await backend.allTracks();
  logData('allTracks', source: 'live', extra: 'count=${res.length}');
  return res;
});

final favoriteAlbumsProvider = FutureProvider.autoDispose<List<AfAlbum>>((
  ref,
) async {
  ref.keepAlive();
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    logData('favoriteAlbums', source: 'demo', extra: '(signed out)');
    return const <AfAlbum>[];
  }
  final res = await backend.favoriteAlbums();
  logData('favoriteAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

final favoriteTracksProvider = FutureProvider.autoDispose<List<AfTrack>>((
  ref,
) async {
  ref.keepAlive();
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    logData('favoriteTracks', source: 'demo', extra: '(signed out)');
    return const <AfTrack>[];
  }
  final res = await backend.favoriteTracks();
  logData('favoriteTracks', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// Set of track IDs currently favorited, derived from [favoriteTracksProvider].
final favoriteIdsProvider = Provider<Set<String>>((ref) {
  final tracks = ref.watch(favoriteTracksProvider);
  return tracks.whenOrNull(data: (list) => list.map((t) => t.id).toSet()) ??
      <String>{};
});

final playlistTrackIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) return <String>{};

  final playlists = await ref.watch(allPlaylistsProvider.future);
  final ids = <String>{};

  const batchSize = 10;
  for (var i = 0; i < playlists.length; i += batchSize) {
    final end = (i + batchSize < playlists.length)
        ? i + batchSize
        : playlists.length;
    final batch = playlists.sublist(i, end);
    final results = await Future.wait(
      batch.map(
        (pl) => backend
            .playlist(pl.id)
            .then(
              (detail) {
                if (detail != null) {
                  return detail.tracks.map((t) => t.id).toSet();
                }
                afLog('data', 'playlist track fetch returned null id=${pl.id}');
                return <String>{};
              },
              onError: (Object e, StackTrace? s) {
                afLog(
                  'error',
                  'failed to fetch playlist tracks id=${pl.id}',
                  error: e,
                  stackTrace: s,
                );
                return <String>{};
              },
            ),
      ),
    );
    for (final trackIds in results) {
      ids.addAll(trackIds);
    }
  }

  return ids;
});

final allGenresProvider = FutureProvider.autoDispose<List<AfGenre>>((
  ref,
) async {
  ref.keepAlive();
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    logData('allGenres', source: 'none', extra: '(signed out)');
    return const <AfGenre>[];
  }

  final res = await backend.genres();
  logData('allGenres', source: 'live', extra: 'count=${res.length}');

  if (res.every((g) => g.imageUrl != null)) return res;

  final enriched = <AfGenre>[];
  final needsEnrichment = <AfGenre>[];
  for (final g in res) {
    if (g.imageUrl != null) {
      enriched.add(g);
    } else {
      needsEnrichment.add(g);
    }
  }

  if (needsEnrichment.isNotEmpty) {
    final enrichments = await Future.wait(
      needsEnrichment.map((g) async {
        try {
          final albums = await backend.albumsByGenre(g.name, limit: 1);
          final imageUrl = albums.isNotEmpty ? albums.first.imageUrl : null;
          return AfGenre(g.name, g.tint, imageUrl: imageUrl);
        } catch (e, stack) {
          afLog(
            'error',
            'Genre enrichment failed for ${g.name}',
            error: e,
            stackTrace: stack,
          );
          return g;
        }
      }),
      eagerError: false,
    );
    enriched.addAll(enrichments);
  }

  return enriched;
});
