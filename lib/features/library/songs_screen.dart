import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/artwork.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/library_skeleton.dart';

enum SongsPill { songs, artists, albums, genres }

extension on SongsPill {
  String get label => switch (this) {
    SongsPill.songs => 'SONGS',
    SongsPill.artists => 'ARTISTS',
    SongsPill.albums => 'ALBUMS',
    SongsPill.genres => 'GENRES',
  };

  String get indexTag => switch (this) {
    SongsPill.songs => '⁰¹',
    SongsPill.artists => '⁰²',
    SongsPill.albums => '⁰³',
    SongsPill.genres => '⁰⁴',
  };
}

final songsPillProvider = StateProvider<SongsPill?>((ref) => null);

class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  final _searchController = TextEditingController();
  SongsPill _pill = SongsPill.songs;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final pill = ref.read(songsPillProvider);
    if (pill != null && mounted) {
      _pill = pill;
      ref.read(songsPillProvider.notifier).state = null;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SongsPill?>(songsPillProvider, (prev, next) {
      if (next != null && next != _pill && mounted) {
        setState(() {
          _pill = next;
          ref.read(songsPillProvider.notifier).state = null;
        });
      }
    });

    final isLocal = ref.watch(appModeProvider) == AppMode.local;
    final tracksCountAsync = isLocal
        ? ref.watch(localTracksProvider)
        : ref.watch(allTracksProvider);

    final statsLabel = tracksCountAsync.maybeWhen(
      data: (list) => 'SYS.IDX // ${list.length} ITEMS',
      orElse: () => 'SYS.IDX // — ITEMS',
    );

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Catalogue Editorial Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              AfSpacing.s16,
              AfSpacing.s16,
              AfSpacing.s12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CATALOGUE',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AfColors.indigo400,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'COLLECTION',
                            style: AfTypography.titleLarge.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AfColors.surfaceBase,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AfColors.surfaceHigh,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        statsLabel,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AfColors.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Architectural Search Box
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'SEARCH ARCHIVE...',
                    hintStyle: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AfColors.textTertiary,
                      letterSpacing: 1.0,
                    ),
                    prefixIcon: const Icon(
                      LucideIcons.search,
                      color: AfColors.indigo400,
                      size: 18,
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              LucideIcons.x,
                              color: AfColors.textTertiary,
                              size: 16,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AfColors.surfaceLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AfColors.surfaceHigh, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AfColors.surfaceHigh, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AfColors.indigo400, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s16,
                      vertical: AfSpacing.s12,
                    ),
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
              ],
            ),
          ),
          
          // Index-styled tab selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: _UnderlinedIndexBar(
              selected: _pill,
              onChanged: (v) => setState(() => _pill = v),
            ),
          ),
          const SizedBox(height: AfSpacing.s12),
          
          Expanded(
            child: _PillContent(pill: _pill, query: _query),
          ),
        ],
      ),
    );
  }
}

/// Underlined minimalist tab bar with superscripts
class _UnderlinedIndexBar extends StatelessWidget {
  const _UnderlinedIndexBar({required this.selected, required this.onChanged});
  final SongsPill selected;
  final ValueChanged<SongsPill> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AfColors.surfaceHigh,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: SongsPill.values.map((pill) {
          final isSelected = pill == selected;
          return GestureDetector(
            onTap: () => onChanged(pill),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? AfColors.indigo400 : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pill.label,
                    style: TextStyle(
                      fontFamily: isSelected ? 'monospace' : null,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      color: isSelected ? AfColors.textPrimary : AfColors.textTertiary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    pill.indexTag,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AfColors.indigo400 : AfColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PillContent extends ConsumerWidget {
  const _PillContent({required this.pill, required this.query});
  final SongsPill pill;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    switch (pill) {
      case SongsPill.songs:
        return _SongsList(isLocal: isLocal, query: query);
      case SongsPill.artists:
        return _ArtistsGrid(isLocal: isLocal, query: query);
      case SongsPill.albums:
        return _AlbumsGrid(isLocal: isLocal, query: query);
      case SongsPill.genres:
        return _GenresGrid(isLocal: isLocal, query: query);
    }
  }
}

/// Songs list - with custom sequence counts and sleek borders
class _SongsList extends ConsumerWidget {
  const _SongsList({required this.isLocal, required this.query});
  final bool isLocal;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(currentTrackProvider)?.id;

    if (isLocal) {
      final tracks = ref.watch(localTracksProvider);
      return tracks.when(
        data: (list) => _buildList(_filterTracks(list, query), activeId, ref),
        loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.songs),
        error: (e, _) => AsyncErrorView(
          label: 'Couldn\u2019t load songs',
          error: e,
          onRetry: () => ref.invalidate(localTracksProvider),
        ),
      );
    }

    final tracksState = ref.watch(tracksPaginationProvider);
    if (tracksState.error != null && tracksState.items.isEmpty) {
      return AsyncErrorView(
        label: 'Couldn\u2019t load songs',
        error: Exception(tracksState.error),
        onRetry: () =>
            ref.read(tracksPaginationProvider.notifier).loadFirstPage(),
      );
    }
    if (tracksState.items.isEmpty && tracksState.isLoadingMore) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filterTracks(tracksState.items, query);
    return _buildList(filtered, activeId, ref);
  }

  List<AfTrack> _filterTracks(List<AfTrack> tracks, String query) {
    if (query.isEmpty) return tracks;
    final q = query.toLowerCase();
    return tracks.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.artistName.toLowerCase().contains(q);
    }).toList();
  }

  Widget _buildList(List<AfTrack> tracks, String? activeId, WidgetRef ref) {
    if (tracks.isEmpty) {
      return Center(
        child: Text(
          'No songs found',
          style: AfTypography.bodyMedium.copyWith(color: AfColors.textTertiary),
        ),
      );
    }

    return RepaintBoundary(
      child: AfScrollbar(
        child: ListView.builder(
          padding: const EdgeInsets.only(
            left: AfSpacing.s16,
            right: AfSpacing.s16,
            bottom: AfSpacing.bottomInsetWithMiniAndNav,
          ),
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            final displayIdx = (i + 1).toString().padLeft(3, '0');
            final isPlaying = t.id == activeId;

            return Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AfColors.surfaceBase,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Three-digit serial index
                  SizedBox(
                    width: 32,
                    child: Text(
                      displayIdx,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isPlaying ? AfColors.indigo400 : AfColors.textDisabled,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TrackRow(
                      track: t,
                      isActive: isPlaying,
                      isBuffering: isPlaying && ref.watch(isBufferingProvider),
                      activeAccent: ref.watch(currentSpectralProvider).energy,
                      onTap: () =>
                          ref.read(playActionsProvider).playSmartQueue(t, tracks),
                      onLongPress: () => showTrackContextMenu(context, ref, t),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Artists Grid with offset rings and custom layout
class _ArtistsGrid extends ConsumerWidget {
  const _ArtistsGrid({required this.isLocal, required this.query});
  final bool isLocal;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localArtistsProvider : allArtistsProvider;
    final async = ref.watch(provider);
    return async.when(
      data: (list) {
        final filtered = _filter(list, query);
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              'No artists found',
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          );
        }
        return RepaintBoundary(
          child: GridView.builder(
            padding: const EdgeInsets.only(
              left: AfSpacing.s16,
              right: AfSpacing.s16,
              bottom: AfSpacing.bottomInsetWithMiniAndNav,
            ),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: 155,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s16,
            ),
            itemBuilder: (context, i) {
              final a = filtered[i];
              return GestureDetector(
                onTap: () => context.push('/artist/${a.id}'),
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Asymmetric outline ring offset
                        Positioned(
                          top: 3,
                          left: 3,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AfColors.indigo400.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AfColors.surfaceBase,
                            border: Border.all(
                              color: AfColors.surfaceHigh,
                              width: 1.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Artwork(
                            url: a.imageUrl,
                            size: 80,
                            radius: BorderRadius.circular(40),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      a.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AfTypography.caption.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${a.albumCount} ALBS',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 8,
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
      loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.artists),
      error: (e, _) => AsyncErrorView(
        label: 'Couldn\u2019t load artists',
        error: e,
        onRetry: () => ref.invalidate(provider),
      ),
    );
  }

  List<AfArtist> _filter(List<AfArtist> artists, String query) {
    if (query.isEmpty) return artists;
    final q = query.toLowerCase();
    return artists.where((a) => a.name.toLowerCase().contains(q)).toList();
  }
}

/// Asymmetric Albums Grid featuring dynamic layout pattern
class _AlbumsGrid extends ConsumerWidget {
  const _AlbumsGrid({required this.isLocal, required this.query});
  final bool isLocal;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localAlbumsProvider : allAlbumsProvider;
    final async = ref.watch(provider);
    return async.when(
      data: (list) {
        final filtered = _filter(list, query);
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              'No albums found',
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          );
        }
        return RepaintBoundary(
          child: GridView.builder(
            padding: const EdgeInsets.only(
              left: AfSpacing.s16,
              right: AfSpacing.s16,
              bottom: AfSpacing.bottomInsetWithMiniAndNav,
            ),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 220,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s16,
            ),
            itemBuilder: (context, i) {
              final a = filtered[i];
              // Give alternate cards different border styles for visual rhythm
              final isEven = i % 2 == 0;
              final radius = isEven
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    )
                  : const BorderRadius.only(
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    );

              return GestureDetector(
                onTap: () => context.push('/album/${a.id}'),
                onLongPress: () => showAlbumContextMenu(context, ref, a),
                child: Container(
                  decoration: BoxDecoration(
                    color: AfColors.surfaceLow,
                    borderRadius: radius,
                    border: Border.all(
                      color: AfColors.surfaceHigh,
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Artwork(
                                url: a.imageUrl,
                                size: double.infinity,
                                radius: BorderRadius.zero,
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  a.year != null ? '${a.year}' : 'ALBUM',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 8,
                                    color: AfColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AfTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              a.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AfTypography.caption.copyWith(
                                color: AfColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.albums),
      error: (e, _) => AsyncErrorView(
        label: 'Couldn\u2019t load albums',
        error: e,
        onRetry: () => ref.invalidate(provider),
      ),
    );
  }

  List<AfAlbum> _filter(List<AfAlbum> albums, String query) {
    if (query.isEmpty) return albums;
    final q = query.toLowerCase();
    return albums.where((a) {
      return a.name.toLowerCase().contains(q) ||
          a.artistName.toLowerCase().contains(q);
    }).toList();
  }
}

/// Bento-inspired list for Genres Section
class _GenresGrid extends ConsumerWidget {
  const _GenresGrid({required this.isLocal, required this.query});
  final bool isLocal;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localGenresProvider : allGenresProvider;
    final async = ref.watch(provider);
    return async.when(
      data: (list) {
        final filtered = _filter(list, query);
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              'No genres found',
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          );
        }
        return RepaintBoundary(
          child: GridView.builder(
            padding: const EdgeInsets.only(
              left: AfSpacing.s16,
              right: AfSpacing.s16,
              bottom: AfSpacing.bottomInsetWithMiniAndNav,
            ),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 110,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemBuilder: (context, i) {
              final g = filtered[i];
              // Parse tint safely
              final tint = Color(int.parse(g.tint.replaceFirst('#', '0xFF')));
              
              return GestureDetector(
                onTap: () => context.push('/genre/${g.name}'),
                child: Container(
                  decoration: BoxDecoration(
                    color: AfColors.surfaceLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AfColors.surfaceHigh,
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Subdued rotated artwork on the side
                      Positioned(
                        bottom: -16,
                        right: -16,
                        width: 70,
                        height: 70,
                        child: Opacity(
                          opacity: 0.65,
                          child: Transform.rotate(
                            angle: -0.2,
                            child: Artwork(
                              url: g.imageUrl,
                              size: 70,
                            ),
                          ),
                        ),
                      ),
                      
                      // Bold left label
                      Positioned(
                        top: 14,
                        left: 14,
                        right: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g.name.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AfTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: AfColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 16,
                              height: 1.5,
                              color: tint,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.genres),
      error: (e, _) => AsyncErrorView(
        label: 'Couldn\u2019t load genres',
        error: e,
        onRetry: () => ref.invalidate(provider),
      ),
    );
  }

  List<AfGenre> _filter(List<AfGenre> genres, String query) {
    if (query.isEmpty) return genres;
    final q = query.toLowerCase();
    return genres.where((g) => g.name.toLowerCase().contains(q)).toList();
  }
}
