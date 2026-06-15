import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/youtube/innertube_client.dart';
import '../../core/youtube/youtube_music_client.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_metadata_providers.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/opacity_app_bar.dart';
import '../../widgets/breadcrumb.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/skeletons/artist_skeleton.dart';
import 'artist_screen_widgets.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key, required this.artistId});
  final String artistId;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
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
    final artistAsync = ref.watch(artistDetailProvider(widget.artistId));
    final albumsAsync = ref.watch(artistAlbumsProvider(widget.artistId));
    final topTracksAsync = ref.watch(artistTopTracksProvider(widget.artistId));
    final activeId = ref.watch(currentTrackProvider)?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );
    final wikiAsync = ref.watch(artistWikiProvider(widget.artistId));

    return FocusTraversalGroup(
      child: Scaffold(
        backgroundColor: AfColors.surfaceCanvas,
        body: artistAsync.when(
          loading: () => const ArtistSkeleton(),
          error: (e, _) => AsyncErrorView(
            label: 'Could not load artist',
            error: e,
            onRetry: () =>
                ref.invalidate(artistDetailProvider(widget.artistId)),
          ),
          data: (artist) {
            if (artist == null) {
              return const Center(child: Text('Artist not found'));
            }

            final topTracks = topTracksAsync.valueOrNull ?? [];
            final albums = albumsAsync.valueOrNull ?? [];

            // YouTube Music: get dynamic sections from the client
            final backend = ref.watch(musicBackendProvider);
            final ytSections = backend is YouTubeMusicClient
                ? backend.artistSections
                    .where((s) => s.items.isNotEmpty)
                    .toList()
                : <({String title, List<InnerTubeItem> items, String? moreId})>[];
            final width = MediaQuery.of(context).size.width;
            final heroHeight = width; // 1:1

            // Use artist image or first album artwork as hero
            final heroUrl =
                artist.imageUrl ??
                (albums.isNotEmpty ? albums.first.imageUrl : null);

            return Stack(
              children: [
                // Hero artwork — parallax via Transform.translate + scroll-linked scale
                ValueListenableBuilder<double>(
                  valueListenable: _scrollOffset,
                  builder: (context, offset, _) {
                    final scaleProgress = (offset / heroHeight).clamp(0.0, 1.0);
                    final scale = 1.0 - (scaleProgress * 0.08);

                    return Positioned(
                      top: -offset * 0.5,
                      left: 0,
                      right: 0,
                      child: SizedBox(
                        height: heroHeight,
                        child: Transform.scale(
                          scale: scale,
                          child: ShaderMask(
                            shaderCallback: (rect) {
                              return const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0.6, 1.0],
                                colors: [
                                  AfColors.textOnPrimary,
                                  Colors.transparent,
                                ],
                              ).createShader(rect);
                            },
                            blendMode: BlendMode.dstIn,
                            child: Artwork(
                              url: heroUrl,
                              size: width,
                              height: heroHeight,
                              radius: AfRadii.borderMd,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                AfScrollbar(
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: SizedBox(height: heroHeight)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: AfSpacing.s16,
                            bottom: AfSpacing.s8,
                          ),
                          child: AfBreadcrumb(
                            items: [
                              BreadcrumbItem(
                                label: 'Home',
                                onTap: () => context.go('/home'),
                              ),
                              BreadcrumbItem(label: 'Artist: ${artist.name}'),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AfSpacing.gutterGenerous,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                artist.name,
                                style: AfTypography.display.copyWith(
                                  color: AfColors.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AfSpacing.s4),
                              Text(
                                artist.statLine,
                                style: AfTypography.bodySmall.copyWith(
                                  color: AfColors.textTertiary,
                                ),
                              ),
                              const SizedBox(height: AfSpacing.s16),
                              ArtistActionRow(
                                onPlay: topTracks.isNotEmpty
                                    ? () => ref
                                          .read(playActionsProvider)
                                          .playQueue(topTracks, startIndex: 0)
                                    : null,
                                onRadio: () => startArtistRadio(
                                  context,
                                  ref,
                                  artist.name,
                                  widget.artistId,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (topTracks.isNotEmpty)
                        ...buildArtistTopSongsSlivers(
                          topTracks: topTracks,
                          activeId: activeId,
                          isBuffering: isBuffering,
                          activeAccent: activeAccent,
                          onTap: (i) => ref
                              .read(playActionsProvider)
                              .playQueue(topTracks, startIndex: i),
                          onLongPress: (track) =>
                              showTrackContextMenu(context, ref, track),
                        ),
                      wikiAsync.maybeWhen(
                        data: (wiki) {
                          if (wiki == null ||
                              wiki.bio == null ||
                              wiki.bio!.isEmpty) {
                            return const SliverToBoxAdapter(child: SizedBox());
                          }
                          return SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AfSpacing.gutterGenerous,
                                vertical: AfSpacing.s24,
                              ),
                              child: ArtistBiographyPanel(
                                bio: wiki.bio!,
                                listeners: wiki.listeners,
                                playCount: wiki.playCount,
                              ),
                            ),
                          );
                        },
                        orElse: () =>
                            const SliverToBoxAdapter(child: SizedBox()),
                      ),
                      // -- Dynamic Sections (YT Music) --
                      if (ytSections.isNotEmpty)
                        ...ytSections.map((section) {
                          final items = section.items;
                          return SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(top: AfSpacing.s24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AfSpacing.gutterGenerous,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          section.title,
                                          style: AfTypography.titleMedium.copyWith(
                                            color: AfColors.textPrimary,
                                          ),
                                        ),
                                        if (section.moreId != null)
                                          GestureDetector(
                                            onTap: () => context.push(
                                              '/album/${section.moreId}',
                                            ),
                                            child: Text(
                                              'More',
                                              style: AfTypography.bodyMedium.copyWith(
                                                color: activeAccent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AfSpacing.s8),
                                  SizedBox(
                                    height: 220,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AfSpacing.gutterGenerous,
                                      ),
                                      itemCount: items.length.clamp(0, 10),
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: AfSpacing.s12),
                                      itemBuilder: (context, i) {
                                        final item = items[i];
                                        return PressScale(
                                          onTap: () {
                                            if (item.type == InnerTubeItemType.album ||
                                                item.type == InnerTubeItemType.playlist) {
                                              context.push('/album/${item.id}');
                                            } else if (item.type == InnerTubeItemType.artist) {
                                              context.push('/artist/${item.id}');
                                            }
                                          },
                                          child: SizedBox(
                                            width: 152,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Artwork(
                                                  url: item.thumbnailUrl,
                                                  size: 152,
                                                  radius: AfRadii.borderMd,
                                                ),
                                                const SizedBox(height: AfSpacing.s8),
                                                Text(
                                                  item.title,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: AfTypography.titleSmall.copyWith(
                                                    color: AfColors.textPrimary,
                                                  ),
                                                ),
                                                if (item.subtitle.isNotEmpty &&
                                                    item.type != InnerTubeItemType.artist)
                                                  Padding(
                                                    padding: const EdgeInsets.only(
                                                      top: AfSpacing.s2,
                                                    ),
                                                    child: Text(
                                                      item.subtitle,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: AfTypography.bodySmall.copyWith(
                                                        color: AfColors.textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList()
                      else ...[
                        // -- Discography (non-YT Music fallback) --
                        ...buildArtistDiscographySlivers(albums),
                      ],
                      const SliverToBoxAdapter(
                        child: SizedBox(
                          height: AfSpacing.bottomInsetWithMiniAndNav,
                        ),
                      ),
                    ],
                  ),
                ),

                // App bar
                ValueListenableBuilder<double>(
                  valueListenable: _scrollOffset,
                  builder: (context, offset, _) => Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: OpacityAppBar(
                      scrollOffset: offset,
                      threshold: heroHeight - kToolbarHeight,
                      title: artist.name,
                      onBack: () => context.pop(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
