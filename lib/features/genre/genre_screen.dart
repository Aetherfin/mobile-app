import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/opacity_app_bar.dart';
import '../../widgets/breadcrumb.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/section_header.dart';
import '../../widgets/artwork.dart';
import '../../widgets/tile.dart';
import '../../widgets/skeletons/genre_skeleton.dart';
import '../../widgets/stagger_reveal.dart';

class GenreScreen extends ConsumerStatefulWidget {
  const GenreScreen({super.key, required this.genre});
  final String genre;

  @override
  ConsumerState<GenreScreen> createState() => _GenreScreenState();
}

class _GenreScreenState extends ConsumerState<GenreScreen> {
  final _scroll = ScrollController();
  late final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () => _scrollOffset.value = _scroll.hasClients ? _scroll.offset : 0.0,
    );
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(genreAlbumsProvider(widget.genre));

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      body: albumsAsync.when(
        loading: () => const GenreSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load genre',
          error: e,
          onRetry: () => ref.invalidate(genreAlbumsProvider(widget.genre)),
        ),
        data: (albums) {
          // Derive unique artists from genre albums.
          final seen = <String>{};
          final artists = <({String name, String? imageUrl, String? id})>[];
          for (final a in albums) {
            if (seen.add(a.artistName)) {
              artists.add((
                name: a.artistName,
                imageUrl: a.imageUrl,
                id: a.artistId,
              ));
            }
          }

          return Stack(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) => Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: OpacityAppBar(
                    scrollOffset: offset,
                    threshold: 140,
                    title: widget.genre,
                    onBack: () {
                      if (context.canPop()) context.pop();
                    },
                  ),
                ),
              ),

              RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(genreAlbumsProvider(widget.genre));
                  await ref.read(genreAlbumsProvider(widget.genre).future);
                },
                color: ref.watch(
                  currentSpectralProvider.select((s) => s.primary),
                ),
                backgroundColor: AfColors.surfaceBase,
                child: CustomScrollView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  slivers: [
                    // ── Breadcrumb ──
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(
                          top:
                              MediaQuery.of(context).padding.top +
                              kToolbarHeight +
                              AfSpacing.s8,
                        ),
                        child: AfBreadcrumb(
                          items: [
                            BreadcrumbItem(
                              label: 'Home',
                              onTap: () => context.go('/home'),
                            ),
                            BreadcrumbItem(label: 'Genre: ${widget.genre}'),
                          ],
                        ),
                      ),
                    ),

                    // ── Genre header ──
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: AfSpacing.s8,
                          left: AfSpacing.gutterGenerous,
                          right: AfSpacing.gutterGenerous,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.genre,
                              style: AfTypography.display.copyWith(
                                color: AfColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AfSpacing.s4),
                            Text(
                              _buildSubtitle(albums.length, artists.length),
                              style: AfTypography.bodyMedium.copyWith(
                                color: AfColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Artists in this genre ──
                    if (artists.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AfSpacing.s24),
                      ),
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AfSpacing.gutterGenerous,
                          ),
                          child: SectionHeader(title: 'Artists'),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AfSpacing.s8),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AfSpacing.gutterGenerous,
                            ),
                            itemCount: artists.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: AfSpacing.s16),
                            itemBuilder: (context, i) {
                              final a = artists[i];
                              return PressScale(
                                onTap: a.id != null
                                    ? () => context.push('/artist/${a.id}')
                                    : null,
                                child: SizedBox(
                                  width: 88,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 72,
                                        height: 72,
                                        decoration: const BoxDecoration(
                                          color: AfColors.surfaceRaised,
                                          shape: BoxShape.circle,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: a.imageUrl != null
                                            ? Artwork(
                                                url: a.imageUrl,
                                                size: 72,
                                                radius: AfRadii.borderPill,
                                                fit: BoxFit.cover,
                                              )
                                            : const Icon(
                                                LucideIcons.user,
                                                size: 32,
                                                color: AfColors.textTertiary,
                                              ),
                                      ),
                                      const SizedBox(height: AfSpacing.s8),
                                      Text(
                                        a.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: AfTypography.bodySmall.copyWith(
                                          color: AfColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],

                    // ── Albums in this genre ──
                    if (albums.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AfSpacing.s24),
                      ),
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AfSpacing.gutterGenerous,
                          ),
                          child: SectionHeader(title: 'Albums'),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AfSpacing.s8),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent:
                                    AfLayout.albumGridMaxTileExtent,
                                mainAxisExtent: 220,
                                crossAxisSpacing: AfSpacing.s16,
                                mainAxisSpacing: AfSpacing.s16,
                              ),
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final a = albums[i];
                            return StaggerReveal(
                              children: [
                                Tile(
                                  title: a.name,
                                  subtitle: a.artistName,
                                  variant: TileVariant.album,
                                  imageUrl: a.imageUrl,
                                  size: double.infinity,
                                  onTap: () => context.push('/album/${a.id}'),
                                ),
                              ],
                            );
                          }, childCount: albums.length),
                        ),
                      ),
                    ],

                    // ── Empty state ──
                    if (albums.isEmpty)
                      SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: AfSpacing.s96),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.music2,
                                  size: 48,
                                  color: AfColors.textTertiary,
                                ),
                                const SizedBox(height: AfSpacing.s12),
                                Text(
                                  'No albums in this genre',
                                  style: AfTypography.titleSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    const SliverToBoxAdapter(
                      child: SizedBox(
                        height: AfSpacing.bottomInsetWithMiniAndNav,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _buildSubtitle(int albumCount, int artistCount) {
    final albumStr = albumCount == 0
        ? 'No albums'
        : albumCount == 1
        ? '1 album'
        : '$albumCount albums';
    if (artistCount == 0) return albumStr;
    final artistStr = artistCount == 1 ? '1 artist' : '$artistCount artists';
    return '$albumStr · $artistStr';
  }
}
