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
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/library_skeleton.dart';

enum SongsPill { songs, artists, albums, genres }

extension on SongsPill {
  String get label => switch (this) {
    SongsPill.songs => 'Songs',
    SongsPill.artists => 'Artists',
    SongsPill.albums => 'Albums',
    SongsPill.genres => 'Genres',
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

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              AfSpacing.s8,
              AfSpacing.s16,
              AfSpacing.s12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Library', style: AfTypography.titleLarge),
                const SizedBox(height: AfSpacing.s12),
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums\u2026',
                    prefixIcon: const Icon(
                      LucideIcons.search,
                      color: AfColors.textTertiary,
                      size: 22,
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              LucideIcons.x,
                              color: AfColors.textTertiary,
                              size: 18,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AfColors.surfaceRaised,
                    border: const OutlineInputBorder(
                      borderRadius: AfRadii.borderPill,
                      borderSide: BorderSide(color: AfColors.surfaceHigh),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: AfRadii.borderPill,
                      borderSide: BorderSide(color: AfColors.surfaceHigh),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: AfRadii.borderPill,
                      borderSide: BorderSide(color: AfColors.indigo400),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: _PillBar(
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

class _PillBar extends StatefulWidget {
  const _PillBar({required this.selected, required this.onChanged});
  final SongsPill selected;
  final ValueChanged<SongsPill> onChanged;

  @override
  State<_PillBar> createState() => _PillBarState();
}

class _PillBarState extends State<_PillBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _fromIndex = 0;
  int _toIndex = 0;

  @override
  void initState() {
    super.initState();
    _toIndex = SongsPill.values.indexOf(widget.selected);
    _fromIndex = _toIndex;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..value = 1.0;
  }

  @override
  void didUpdateWidget(_PillBar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      _fromIndex = _toIndex;
      _toIndex = SongsPill.values.indexOf(widget.selected);
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = SongsPill.values.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final segWidth = constraints.maxWidth / count;

        return ClipRRect(
          borderRadius: AfRadii.borderPill,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: AfColors.surfaceRaised),
            child: SizedBox(
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      final curved = Curves.easeOutBack.transform(_ctrl.value);
                      final damped = curved > 1.0
                          ? 1.0 + (curved - 1.0) * 0.15
                          : curved;
                      final idx = _fromIndex + (_toIndex - _fromIndex) * damped;
                      return Positioned(
                        left: 4 + segWidth * idx,
                        top: 4,
                        bottom: 4,
                        width: segWidth - 8,
                        child: const IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0x266366F1), // indigo500 @ 15%
                              borderRadius: AfRadii.borderPill,
                              border: Border.fromBorderSide(
                                BorderSide(
                                  color: Color(0x40818CF8), // indigo400 @ 25%
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: List.generate(count, (i) {
                      final pill = SongsPill.values[i];
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onChanged(pill),
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            child: Text(
                              pill.label,
                              style: AfTypography.bodyMedium.copyWith(
                                color: pill == widget.selected
                                    ? AfColors.textOnPrimary
                                    : AfColors.textSecondary,
                                fontWeight: pill == widget.selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

/// ─────────────────────────────────────────────────────────────────────────────
///
/// Songs list — local mode (SQL) or server mode (paginated).
///
/// ─────────────────────────────────────────────────────────────────────────────
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
    const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s8);

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
          padding: padding.add(
            const EdgeInsets.only(bottom: AfSpacing.bottomInsetWithMiniAndNav),
          ),
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TrackRow(
                track: t,
                isActive: t.id == activeId,
                isBuffering: t.id == activeId && ref.watch(isBufferingProvider),
                activeAccent: ref.watch(currentSpectralProvider).energy,
                onTap: () =>
                    ref.read(playActionsProvider).playSmartQueue(t, tracks),
                onLongPress: () => showTrackContextMenu(context, ref, t),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
///
/// Artists grid — local or server.
///
/// ─────────────────────────────────────────────────────────────────────────────
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
        const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s16);
        return RepaintBoundary(
          child: GridView.builder(
            padding: padding.add(
              const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav,
              ),
            ),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: 180,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemBuilder: (context, i) {
              final a = filtered[i];
              return Tile(
                title: a.name,
                subtitle: a.statLine,
                variant: TileVariant.artist,
                imageUrl: a.imageUrl,
                size: double.infinity,
                onTap: () => context.push('/artist/${a.id}'),
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

/// ─────────────────────────────────────────────────────────────────────────────
///
/// Albums grid — local or server.
///
/// ─────────────────────────────────────────────────────────────────────────────
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
        const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s16);
        return RepaintBoundary(
          child: GridView.builder(
            padding: padding.add(
              const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav,
              ),
            ),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 220,
              crossAxisSpacing: AfSpacing.s16,
              mainAxisSpacing: AfSpacing.s16,
            ),
            itemBuilder: (context, i) {
              final a = filtered[i];
              return Tile(
                title: a.name,
                subtitle: a.artistName,
                variant: TileVariant.album,
                imageUrl: a.imageUrl,
                size: double.infinity,
                onTap: () => context.push('/album/${a.id}'),
                onLongPress: () => showAlbumContextMenu(context, ref, a),
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

/// ─────────────────────────────────────────────────────────────────────────────
///
/// Genres grid — local or server.
///
/// ─────────────────────────────────────────────────────────────────────────────
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
        const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s16);
        return RepaintBoundary(
          child: GridView.builder(
            padding: padding.add(
              const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav,
              ),
            ),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 96,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemBuilder: (context, i) {
              final g = filtered[i];
              final tint = Color(int.parse(g.tint.replaceFirst('#', '0xFF')));
              return GenreTile(
                name: g.name,
                tint: tint,
                imageUrl: g.imageUrl,
                width: double.infinity,
                height: double.infinity,
                onTap: () => context.push('/genre/${g.name}'),
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
