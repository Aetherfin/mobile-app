import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_metadata_providers.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/opacity_app_bar.dart';
import '../../widgets/breadcrumb.dart';
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
                      // -- Discography --
                      ...buildArtistDiscographySlivers(albums),
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
