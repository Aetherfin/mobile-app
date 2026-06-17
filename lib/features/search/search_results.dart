import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/skeletons/search_skeleton.dart';
import '../../widgets/skeleton.dart';
import '../../utils/color_parse.dart';
import 'search_filters.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Search Results
//
// Extracted from search_screen.dart. Contains all display widgets for the
// search screen: live results, result sections (tracks/albums/artists/playlists),
// idle-state grids, and the idle-state view.
// ─────────────────────────────────────────────────────────────────────────────

/// Parse a hex color string from the server, falling back to the provided
/// color on error.
Color parseSearchTint(String hex, Color fallback) =>
    parseHexColor(hex, fallback: fallback);

/// Live results panel.
///
/// Uses when() (not maybeWhen) so loading state shows a skeleton instead
/// of stale data. Riverpod autoDispose.family cancels the in-flight request
/// when the query key changes, preventing stale-result races.
class LiveSearchResults extends ConsumerWidget {
  const LiveSearchResults({
    required this.query,
    required this.filter,
    super.key,
  });
  final String query;
  final SearchFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchProvider(query));
    return async.when(
      loading: () => const SearchSkeleton(),
      error: (e, _) => AsyncErrorView(
        label: 'Search failed',
        error: e,
        onRetry: () => ref.invalidate(searchProvider(query)),
      ),
      data: (res) {
        // Scope the buckets to the active filter so the list view
        // only renders the requested category. SearchFilter.all keeps
        // the original top-N preview layout.
        final tracks =
            filter == SearchFilter.all || filter == SearchFilter.tracks
            ? res.tracks
            : const <AfTrack>[];
        final albums =
            filter == SearchFilter.all || filter == SearchFilter.albums
            ? res.albums
            : const <AfAlbum>[];
        final artists =
            filter == SearchFilter.all || filter == SearchFilter.artists
            ? res.artists
            : const <AfArtist>[];
        final playlists =
            filter == SearchFilter.all || filter == SearchFilter.playlists
            ? res.playlists
            : const <AfPlaylist>[];
        final empty =
            tracks.isEmpty &&
            albums.isEmpty &&
            artists.isEmpty &&
            playlists.isEmpty;
        if (empty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
                vertical: AfSpacing.s24,
              ),
              child: EmptyState(
                icon: LucideIcons.searchX,
                title: filter == SearchFilter.all
                    ? 'No results for "$query"'
                    : 'No ${filter.label.toLowerCase()} found for "$query"',
                body: 'Try a different search term',
              ),
            ),
          );
        }
        return SearchResults(
          tracks: tracks,
          albums: albums,
          artists: artists,
          playlists: playlists,
          // When a single-type filter is active, drop the preview caps.
          unbounded: filter != SearchFilter.all,
        );
      },
    );
  }
}

/// Rendered search result sections (tracks, albums, artists, playlists).
class SearchResults extends ConsumerWidget {
  const SearchResults({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.playlists,
    this.unbounded = false,
    super.key,
  });
  final List<AfTrack> tracks;
  final List<AfAlbum> albums;
  final List<AfArtist> artists;
  final List<AfPlaylist> playlists;

  /// When true, render every result of each type (no preview cap).
  /// Set when a single-type filter chip is active.
  final bool unbounded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(currentTrackProvider.select((t) => t?.id));
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, muted: s.muted),
      ),
    );

    // Compute lazy item counts — cap at 20 tracks / 10 others when bounded.
    final trackCount = unbounded ? tracks.length : math.min(tracks.length, 20);
    final albumCount = unbounded ? albums.length : math.min(albums.length, 10);
    final artistCount = unbounded
        ? artists.length
        : math.min(artists.length, 10);
    final playlistCount = unbounded
        ? playlists.length
        : math.min(playlists.length, 10);

    return AfScrollbar(
      child: CustomScrollView(
        slivers: [
          // ── Tracks ──
          if (trackCount > 0) ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AfSpacing.s16,
                0,
                AfSpacing.s16,
                AfSpacing.s8,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(title: 'Tracks', uppercase: true),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              sliver: SliverList.builder(
                itemCount: trackCount,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                  child: Semantics(
                    button: true,
                    label:
                        'Song: ${tracks[i].title} by ${tracks[i].artistName}',
                    child: TrackRow(
                      track: tracks[i],
                      isActive: tracks[i].id == activeId,
                      isBuffering: tracks[i].id == activeId && isBuffering,
                      activeAccent: activeAccent,
                      onTap: () => ref
                          .read(playActionsProvider)
                          .playQueue(tracks, startIndex: i),
                      onLongPress: () =>
                          showTrackContextMenu(context, ref, tracks[i]),
                    ),
                  ),
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: AfSpacing.s16),
              sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],

          // ── Albums ──
          if (albumCount > 0) ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AfSpacing.s16,
                0,
                AfSpacing.s16,
                AfSpacing.s8,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(title: 'Albums', uppercase: true),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              sliver: SliverList.builder(
                itemCount: albumCount,
                itemBuilder: (context, i) {
                  final a = albums[i];
                  return Semantics(
                    button: true,
                    label: 'Album: ${a.name} by ${a.artistName}',
                    child: PressScale(
                      onTap: () => context.push('/album/${a.id}'),
                      child: ListTile(
                        leading: SizedBox(
                          width: 44,
                          height: 44,
                          child: Artwork(url: a.imageUrl, size: 44),
                        ),
                        title: Text(a.name, style: AfTypography.bodyMedium),
                        subtitle: Text(
                          a.artistName,
                          style: AfTypography.bodySmall.copyWith(
                            color: AfColors.textTertiary,
                          ),
                        ),
                        tileColor: Colors.transparent,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: AfSpacing.s16),
              sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],

          // ── Artists ──
          if (artistCount > 0) ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AfSpacing.s16,
                0,
                AfSpacing.s16,
                AfSpacing.s8,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(title: 'Artists', uppercase: true),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              sliver: SliverList.builder(
                itemCount: artistCount,
                itemBuilder: (context, i) {
                  final a = artists[i];
                  return Semantics(
                    button: true,
                    label: 'Artist: ${a.name}',
                    child: PressScale(
                      onTap: () => context.push('/artist/${a.id}'),
                      child: ListTile(
                        leading: Artwork(
                          url: a.imageUrl,
                          size: 44,
                          radius: AfRadii.borderPill,
                        ),
                        title: Text(a.name, style: AfTypography.bodyMedium),
                        subtitle: Text(
                          a.statLine,
                          style: AfTypography.bodySmall.copyWith(
                            color: AfColors.textTertiary,
                          ),
                        ),
                        tileColor: Colors.transparent,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: AfSpacing.s16),
              sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],

          // ── Playlists ──
          if (playlistCount > 0) ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AfSpacing.s16,
                0,
                AfSpacing.s16,
                AfSpacing.s8,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(title: 'Playlists', uppercase: true),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              sliver: SliverList.builder(
                itemCount: playlistCount,
                itemBuilder: (context, i) {
                  final p = playlists[i];
                  return Semantics(
                    button: true,
                    label: 'Playlist: ${p.name}',
                    child: PressScale(
                      onTap: () => context.push('/playlist/${p.id}'),
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: AfRadii.borderSm,
                            gradient: LinearGradient(
                              colors: [spectral.muted, AfColors.surfaceLow],
                            ),
                          ),
                          child: Icon(
                            LucideIcons.listMusic,
                            color: spectral.primary,
                          ),
                        ),
                        title: Text(p.name, style: AfTypography.bodyMedium),
                        subtitle: Text(
                          p.trackCountLabel,
                          style: AfTypography.bodySmall.copyWith(
                            color: AfColors.textTertiary,
                          ),
                        ),
                        tileColor: Colors.transparent,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // Bottom inset.
          const SliverPadding(
            padding: EdgeInsets.only(
              bottom: AfSpacing.bottomInsetWithMiniAndNav,
            ),
            sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
        ],
      ),
    );
  }
}

/// Idle (empty query) panel — shows recent searches + pill selector
/// (Artists | Genres | Albums) with a browsable grid.
class SearchIdleState extends ConsumerStatefulWidget {
  const SearchIdleState({required this.onRecent, super.key});
  final void Function(String query) onRecent;

  @override
  ConsumerState<SearchIdleState> createState() => _SearchIdleStateState();
}

class _SearchIdleStateState extends ConsumerState<SearchIdleState> {
  IdleFilter _filter = IdleFilter.artists;

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(searchHistoryProvider);
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    return AfScrollbar(
      child: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          if (recent.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AfSpacing.s16,
                0,
                AfSpacing.s16,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(title: 'Recent', uppercase: true),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(searchHistoryProvider.notifier).clear(),
                      style: TextButton.styleFrom(
                        foregroundColor: AfColors.textTertiary,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AfSpacing.s16,
                0,
                AfSpacing.s16,
                AfSpacing.s16,
              ),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: AfSpacing.s8,
                  runSpacing: AfSpacing.s8,
                  children: [
                    for (final q in recent)
                      InputChip(
                        label: Text(q),
                        backgroundColor: AfColors.surfaceRaised,
                        side: const BorderSide(color: AfColors.surfaceHigh),
                        labelStyle: AfTypography.bodySmall.copyWith(
                          color: AfColors.textPrimary,
                        ),
                        deleteIcon: const Icon(LucideIcons.x, size: 16),
                        deleteIconColor: AfColors.textTertiary,
                        onPressed: () => widget.onRecent(q),
                        onDeleted: () =>
                            ref.read(searchHistoryProvider.notifier).remove(q),
                      ),
                  ],
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            sliver: SliverToBoxAdapter(
              child: IdleFilterPills(
                selected: _filter,
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
          ..._buildGrid(isLocal),
          const SliverToBoxAdapter(
            child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGrid(bool isLocal) {
    switch (_filter) {
      case IdleFilter.artists:
        return [ArtistIdleGrid(isLocal: isLocal)];
      case IdleFilter.genres:
        return [GenreIdleGrid(isLocal: isLocal)];
      case IdleFilter.albums:
        return [AlbumIdleGrid(isLocal: isLocal)];
    }
  }
}

class ArtistIdleGrid extends ConsumerWidget {
  const ArtistIdleGrid({required this.isLocal, super.key});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localArtistsProvider : allArtistsProvider;
    final async = ref.watch(provider);
    return async.when(
      loading: () => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: AfLayout.artistGridMaxTileExtent,
            mainAxisExtent: 180,
            crossAxisSpacing: AfSpacing.s12,
            mainAxisSpacing: AfSpacing.s12,
          ),
          itemCount: 6,
          itemBuilder: (_, _) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              SizedBox(height: AfSpacing.s8),
              FractionallySizedBox(
                widthFactor: 0.7,
                child: SkeletonBar(height: 14),
              ),
              SizedBox(height: AfSpacing.s4),
              FractionallySizedBox(
                widthFactor: 0.5,
                child: SkeletonBar(height: 12),
              ),
            ],
          ),
        ),
      ),
      error: (_, _) => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: Text(
            'Couldn\'t load suggestions',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (list) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: AfLayout.artistGridMaxTileExtent,
            mainAxisExtent: 180,
            crossAxisSpacing: AfSpacing.s12,
            mainAxisSpacing: AfSpacing.s12,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final a = list[i];
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
      ),
    );
  }
}

class GenreIdleGrid extends ConsumerWidget {
  const GenreIdleGrid({required this.isLocal, super.key});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.secondary),
    );
    final provider = isLocal ? localGenresProvider : allGenresProvider;
    final async = ref.watch(provider);
    return async.when(
      loading: () => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: AfLayout.genreGridMaxTileExtent,
            mainAxisExtent: 96,
            crossAxisSpacing: AfSpacing.s12,
            mainAxisSpacing: AfSpacing.s12,
          ),
          itemCount: 4,
          itemBuilder: (_, _) => const SkeletonBlock(
            width: double.infinity,
            height: 96,
            borderRadius: AfRadii.borderMd,
          ),
        ),
      ),
      error: (_, _) => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: Text(
            'Couldn\'t load suggestions',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (list) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: AfLayout.genreGridMaxTileExtent,
            mainAxisExtent: 96,
            crossAxisSpacing: AfSpacing.s12,
            mainAxisSpacing: AfSpacing.s12,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final g = list[i];
            final tint = parseSearchTint(g.tint, spectral);
            return GenreTile(
              name: g.name,
              tint: tint,
              imageUrl: g.imageUrl,
              width: double.infinity,
              height: double.infinity,
              onTap: () =>
                  context.push('/genre/${Uri.encodeComponent(g.name)}'),
            );
          },
        ),
      ),
    );
  }
}

class AlbumIdleGrid extends ConsumerWidget {
  const AlbumIdleGrid({required this.isLocal, super.key});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localAlbumsProvider : allAlbumsProvider;
    final async = ref.watch(provider);
    return async.when(
      loading: () => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: AfLayout.albumGridMaxTileExtent,
            mainAxisExtent: 220,
            crossAxisSpacing: AfSpacing.s16,
            mainAxisSpacing: AfSpacing.s16,
          ),
          itemCount: 4,
          itemBuilder: (_, _) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              SizedBox(height: AfSpacing.s8),
              FractionallySizedBox(
                widthFactor: 0.7,
                child: SkeletonBar(height: 14),
              ),
              SizedBox(height: AfSpacing.s4),
              FractionallySizedBox(
                widthFactor: 0.5,
                child: SkeletonBar(height: 12),
              ),
            ],
          ),
        ),
      ),
      error: (_, _) => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: Text(
            'Couldn\'t load suggestions',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (list) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: AfLayout.albumGridMaxTileExtent,
            mainAxisExtent: 220,
            crossAxisSpacing: AfSpacing.s16,
            mainAxisSpacing: AfSpacing.s16,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final a = list[i];
            return Tile(
              title: a.name,
              subtitle: a.artistName,
              variant: TileVariant.album,
              imageUrl: a.imageUrl,
              size: double.infinity,
              onTap: () => context.push('/album/${a.id}'),
            );
          },
        ),
      ),
    );
  }
}
