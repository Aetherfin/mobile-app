import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';

enum LibrarySection { albums, artists, songs, playlists, genres, liked }

/// Sort options for library items.
enum LibrarySortOption {
  nameAsc('Name (A-Z)'),
  nameDesc('Name (Z-A)'),
  artistAsc('Artist (A-Z)'),
  artistDesc('Artist (Z-A)'),
  yearDesc('Year (Newest)'),
  yearAsc('Year (Oldest)');

  final String label;
  const LibrarySortOption(this.label);
}

/// Sections available in local mode (no server playlists, no liked — those are server concepts).
/// Smart playlists are accessible from the playlists tab.
const _localSections = [
  LibrarySection.albums,
  LibrarySection.artists,
  LibrarySection.songs,
  LibrarySection.playlists,
  LibrarySection.genres,
];

class LibraryScreen extends ConsumerStatefulWidget {
  /// When set, the screen opens directly on this tab instead of Albums.
  /// Used by deep-links from Home (genre tiles → Genres, artists → Artists).
  final LibrarySection? initialSection;

  const LibraryScreen({super.key, this.initialSection});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late LibrarySection _section;
  LibrarySortOption _sortOption = LibrarySortOption.nameAsc;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection ?? LibrarySection.albums;
  }

  /// Sort a list of albums.
  List<AfAlbum> _sortAlbums(List<AfAlbum> list) {
    final sorted = List<AfAlbum>.from(list);
    switch (_sortOption) {
      case LibrarySortOption.nameAsc:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case LibrarySortOption.nameDesc:
        sorted.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case LibrarySortOption.artistAsc:
        sorted.sort((a, b) => a.artistName.toLowerCase().compareTo(b.artistName.toLowerCase()));
        break;
      case LibrarySortOption.artistDesc:
        sorted.sort((a, b) => b.artistName.toLowerCase().compareTo(a.artistName.toLowerCase()));
        break;
      case LibrarySortOption.yearDesc:
        sorted.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
      case LibrarySortOption.yearAsc:
        sorted.sort((a, b) => (a.year ?? 0).compareTo(b.year ?? 0));
        break;
    }
    return sorted;
  }

  /// Sort a list of artists.
  List<AfArtist> _sortArtists(List<AfArtist> list) {
    final sorted = List<AfArtist>.from(list);
    switch (_sortOption) {
      case LibrarySortOption.nameAsc:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case LibrarySortOption.nameDesc:
        sorted.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case LibrarySortOption.artistAsc:
      case LibrarySortOption.artistDesc:
        // Artists are already sorted by name, no secondary sort by artist
        break;
      case LibrarySortOption.yearDesc:
      case LibrarySortOption.yearAsc:
        // Artists don't have year
        break;
    }
    return sorted;
  }

  /// Sort a list of tracks.
  List<AfTrack> _sortTracks(List<AfTrack> list) {
    final sorted = List<AfTrack>.from(list);
    switch (_sortOption) {
      case LibrarySortOption.nameAsc:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case LibrarySortOption.nameDesc:
        sorted.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case LibrarySortOption.artistAsc:
        sorted.sort((a, b) => a.artistName.toLowerCase().compareTo(b.artistName.toLowerCase()));
        break;
      case LibrarySortOption.artistDesc:
        sorted.sort((a, b) => b.artistName.toLowerCase().compareTo(a.artistName.toLowerCase()));
        break;
      case LibrarySortOption.yearDesc:
      case LibrarySortOption.yearAsc:
        // Tracks don't have year in the same way
        break;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AfColors.surfaceCanvas,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AfSpacing.s16,
                AfSpacing.s8,
                AfSpacing.s16,
                AfSpacing.s8,
              ),
              child: Row(
                children: [
                  Text('Library', style: AfTypography.titleLarge),
                  const Spacer(),
                  PopupMenuButton<LibrarySortOption>(
                    icon: const Icon(Icons.sort_rounded),
                    tooltip: 'Sort',
                    initialValue: _sortOption,
                    onSelected: (option) {
                      setState(() => _sortOption = option);
                    },
                    itemBuilder: (context) => LibrarySortOption.values
                        .map((option) => PopupMenuItem<LibrarySortOption>(
                              value: option,
                              child: Row(
                                children: [
                                  if (_sortOption == option)
                                    const Icon(Icons.check, size: 18, color: AfColors.indigo400)
                                  else
                                    const SizedBox(width: 18),
                                  const SizedBox(width: 8),
                                  Text(option.label, style: AfTypography.bodyMedium),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            _SegmentedPill(
              value: _section,
              onChanged: (v) => setState(() => _section = v),
            ),
            const SizedBox(height: AfSpacing.s16),
            Expanded(
              child: _SectionBody(
                section: _section,
                sortOption: _sortOption,
                sortAlbums: _sortAlbums,
                sortArtists: _sortArtists,
                sortTracks: _sortTracks,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedPill extends ConsumerWidget {
  final LibrarySection value;
  final ValueChanged<LibrarySection> onChanged;
  const _SegmentedPill({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final sections = mode == AppMode.local
        ? _localSections
        : LibrarySection.values;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: sections.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AfSpacing.s8),
        itemBuilder: (context, i) {
          final s = sections[i];
          final selected = s == value;
          return GestureDetector(
            onTap: () => onChanged(s),
            child: AnimatedContainer(
              duration: AfDurations.quick,
              curve: AfCurves.easeStandard,
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? AfColors.indigo600
                    : AfColors.surfaceBase,
                borderRadius: AfRadii.borderPill,
              ),
              alignment: Alignment.center,
              child: Text(
                _label(s),
                style: AfTypography.bodyMedium.copyWith(
                  color: selected
                      ? AfColors.textOnPrimary
                      : AfColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _label(LibrarySection s) => switch (s) {
        LibrarySection.albums => 'Albums',
        LibrarySection.artists => 'Artists',
        LibrarySection.songs => 'Songs',
        LibrarySection.playlists => 'Playlists',
        LibrarySection.genres => 'Genres',
        LibrarySection.liked => 'Liked',
      };
}

class _SectionBody extends ConsumerWidget {
  final LibrarySection section;
  final LibrarySortOption sortOption;
  final List<AfAlbum> Function(List<AfAlbum>)? sortAlbums;
  final List<AfArtist> Function(List<AfArtist>)? sortArtists;
  final List<AfTrack> Function(List<AfTrack>)? sortTracks;

  const _SectionBody({
    required this.section,
    required this.sortOption,
    this.sortAlbums,
    this.sortArtists,
    this.sortTracks,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = const EdgeInsets.symmetric(horizontal: AfSpacing.s16);
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    switch (section) {
      case LibrarySection.albums:
        final albumsProvider =
            isLocal ? localAlbumsProvider : allAlbumsProvider;
        final albums = ref.watch(albumsProvider);
        return albums.when(
          data: (list) {
            final sorted = sortAlbums != null ? sortAlbums!(list) : list;
            return GridView.builder(
              padding: padding.add(const EdgeInsets.only(
                  bottom: AfSpacing.bottomInsetWithMiniAndNav)),
              itemCount: sorted.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 220,
                crossAxisSpacing: AfSpacing.s16,
                mainAxisSpacing: AfSpacing.s16,
              ),
              itemBuilder: (context, i) {
                final a = sorted[i];
                return Tile(
                  title: a.name,
                  subtitle: a.artistName,
                  variant: TileVariant.album,
                  imageUrl: a.imageUrl,
                  size: double.infinity,
                  onTap: () => context.push('/album/${a.id}'),
                  onLongPress: () =>
                      showAlbumContextMenu(context, ref, a),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load albums',
            error: e,
            onRetry: () => ref.invalidate(albumsProvider),
          ),
        );
      case LibrarySection.artists:
        final artistsProvider =
            isLocal ? localArtistsProvider : allArtistsProvider;
        final artists = ref.watch(artistsProvider);
        return artists.when(
          data: (list) {
            final sorted = sortArtists != null ? sortArtists!(list) : list;
            return GridView.builder(
              padding: padding.add(const EdgeInsets.only(
                  bottom: AfSpacing.bottomInsetWithMiniAndNav)),
              itemCount: sorted.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: 180,
                crossAxisSpacing: AfSpacing.s12,
                mainAxisSpacing: AfSpacing.s12,
              ),
              itemBuilder: (context, i) {
                final a = sorted[i];
                return Tile(
                  title: a.name,
                  subtitle: a.statLine,
                  variant: TileVariant.artist,
                  imageUrl: a.imageUrl,
                  size: double.infinity,
                  onTap: () => context.push('/artist/${a.id}'),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load artists',
            error: e,
            onRetry: () => ref.invalidate(artistsProvider),
          ),
        );
      case LibrarySection.songs:
        return Consumer(builder: (context, ref, _) {
          final tracksProvider =
              isLocal ? localTracksProvider : allTracksProvider;
          final tracks = ref.watch(tracksProvider);
          return tracks.when(
            data: (list) {
              final sorted = sortTracks != null ? sortTracks!(list) : list;
              return ListView.separated(
                padding: padding.add(const EdgeInsets.only(
                    bottom: AfSpacing.bottomInsetWithMiniAndNav)),
                itemCount: sorted.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AfSpacing.s4),
                itemBuilder: (context, i) {
                  final t = sorted[i];
                  // Tap any row to play that track — previously this row
                  // had no onTap so songs were unplayable from Library.
                  return TrackRow(
                    track: t,
                    onTap: () => ref
                        .read(playActionsProvider)
                        .playQueue(sorted, startIndex: i),
                    onLongPress: () =>
                        showTrackContextMenu(context, ref, t),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AsyncErrorView(
              label: 'Couldn\u2019t load songs',
              error: e,
              onRetry: () => ref.invalidate(tracksProvider),
            ),
          );
        });
      case LibrarySection.playlists:
        final playlists = ref.watch(allPlaylistsProvider);
        final smartPlaylists = ref.watch(smartPlaylistsProvider);
        final smartCount = smartPlaylists.maybeWhen(
          data: (list) => list.length,
          orElse: () => 0,
        );
        return playlists.when(
          data: (list) => ListView.separated(
            padding: padding.add(const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav)),
            itemCount: list.length + 1, // +1 for smart playlists tile
            separatorBuilder: (context, index) =>
                const SizedBox(height: AfSpacing.s8),
            itemBuilder: (context, i) {
              // First item: Smart Playlists entry
              if (i == 0) {
                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: AfRadii.borderSm,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AfColors.semanticWarning, AfColors.semanticError],
                      ),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white),
                  ),
                  title: Text('Smart Playlists', style: AfTypography.titleSmall),
                  subtitle: Text(
                    '$smartCount playlists',
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                  tileColor: AfColors.surfaceBase,
                  shape: const RoundedRectangleBorder(
                      borderRadius: AfRadii.borderMd),
                  onTap: () => context.push('/smart-playlists'),
                );
              }
              final p = list[i - 1];
              return ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: AfRadii.borderSm,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AfColors.indigo800, AfColors.indigo950],
                    ),
                  ),
                  child: const Icon(Icons.playlist_play_rounded,
                      color: AfColors.indigo300),
                ),
                title: Text(p.name, style: AfTypography.titleSmall),
                subtitle: Text(
                  p.trackCountLabel,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                tileColor: AfColors.surfaceBase,
                shape: const RoundedRectangleBorder(
                    borderRadius: AfRadii.borderMd),
                onTap: () => context.push('/playlist/${p.id}'),
              );
            },
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load playlists',
            error: e,
            onRetry: () => ref.invalidate(allPlaylistsProvider),
          ),
        );
      case LibrarySection.genres:
        final genresProvider =
            isLocal ? localGenresProvider : allGenresProvider;
        final genresAsync = ref.watch(genresProvider);
        return genresAsync.when(
          data: (genres) => GridView.builder(
            padding: padding.add(const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav)),
            itemCount: genres.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 96,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemBuilder: (context, i) {
              final g = genres[i];
              final tint = Color(int.parse(
                  g.tint.replaceFirst('#', '0xFF')));
              return GenreTile(
                name: g.name,
                tint: tint,
                imageUrl: g.imageUrl,
                width: double.infinity,
                height: double.infinity,
                onTap: () => context.push('/genre/${Uri.encodeComponent(g.name)}'),
              );
            },
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load genres',
            error: e,
            onRetry: () => ref.invalidate(genresProvider),
          ),
        );
      case LibrarySection.liked:
        final likedAsync = ref.watch(favoriteTracksProvider);
        return likedAsync.when(
          data: (list) => list.isEmpty
              ? Center(
                  child: Text(
                    'No liked songs yet.\nTap the heart on any track.',
                    textAlign: TextAlign.center,
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: padding.add(const EdgeInsets.only(
                      bottom: AfSpacing.bottomInsetWithMiniAndNav)),
                  itemCount: list.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AfSpacing.s4),
                  itemBuilder: (context, i) {
                    final t = list[i];
                    return TrackRow(
                      track: t,
                      onTap: () => ref
                          .read(playActionsProvider)
                          .playQueue(list, startIndex: i),
                      onLongPress: () =>
                          showTrackContextMenu(context, ref, t),
                    );
                  },
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load liked songs',
            error: e,
            onRetry: () => ref.invalidate(favoriteTracksProvider),
          ),
        );
    }
  }
}
