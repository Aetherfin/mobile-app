import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_metadata_providers.dart';
import '../../state/providers.dart';
import '../../widgets/album_more_sheet.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/opacity_app_bar.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/breadcrumb.dart';
import '../../widgets/skeletons/album_skeleton.dart';
import '../../widgets/stagger_reveal.dart';
import 'album_screen_widgets.dart';

/// Mockup 07 — Album detail.
///
///   Full-bleed 1:1 hero artwork at the top with a bottom fade ShaderMask
///   to surface.canvas. Parallax: artwork translates up at 0.5× scroll
///   speed (ScrollController-driven, not AnimationController-driven).
///   Below: title, artist, metadata line, action row, track list.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.albumId});
  final String albumId;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
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
    final detailAsync = ref.watch(albumDetailProvider(widget.albumId));
    final activeTrack = ref.watch(currentTrackProvider);
    final activeId = activeTrack?.id;
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    final detail = detailAsync.value;
    final wikiAsync = detail != null
        ? ref.watch(
            albumWikiProvider((
              artistName: detail.album.artistName,
              albumName: detail.album.name,
            )),
          )
        : const AsyncValue<
            ({String? wiki, String? listeners, String? playCount})?
          >.loading();

    return FocusTraversalGroup(
      child: Scaffold(
        backgroundColor: AfColors.surfaceCanvas,
        body: detailAsync.when(
          loading: () => const AlbumSkeleton(),
          error: (e, _) => AsyncErrorView(
            label: 'Could not load album',
            error: e,
            onRetry: () => ref.invalidate(albumDetailProvider(widget.albumId)),
          ),
          data: (detail) {
            if (detail == null) {
              return const Center(child: Text('Album not found'));
            }
            final album = detail.album;
            final tracks = detail.tracks;
            final width = MediaQuery.sizeOf(context).width;
            final heroHeight = width; // 1:1

            return Stack(
              children: [
                // Hero artwork — parallax via Transform.translate + scale, scroll-linked.
                buildAlbumHeroArtwork(
                  scrollOffset: _scrollOffset,
                  heroHeight: heroHeight,
                  width: width,
                  imageUrl: album.imageUrl,
                ),

                SafeArea(
                  child: AfScrollbar(
                    controller: _scroll,
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(albumDetailProvider(widget.albumId));
                        await ref.read(
                          albumDetailProvider(widget.albumId).future,
                        );
                      },
                      color: spectral,
                      backgroundColor: AfColors.surfaceBase,
                      child: CustomScrollView(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        slivers: [
                          SliverToBoxAdapter(
                            child: SizedBox(height: heroHeight),
                          ),
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
                                  if (album.artistId != null)
                                    BreadcrumbItem(
                                      label: 'Artist: ${album.artistName}',
                                      onTap: () => context.push(
                                        '/artist/${album.artistId}',
                                      ),
                                    ),
                                  BreadcrumbItem(label: 'Album: ${album.name}'),
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
                                    album.name,
                                    style: AfTypography.display.copyWith(
                                      color: AfColors.textPrimary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: AfSpacing.s4),
                                  GestureDetector(
                                    onTap: album.artistId != null
                                        ? () => context.push(
                                            '/artist/${album.artistId}',
                                          )
                                        : null,
                                    child: Semantics(
                                      button: true,
                                      label: 'Artist: ${album.artistName}',
                                      child: Text(
                                        album.artistName,
                                        style: AfTypography.titleMedium
                                            .copyWith(color: spectral),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AfSpacing.s4),
                                  Text(
                                    album.metadataLine,
                                    style: AfTypography.bodySmall.copyWith(
                                      color: AfColors.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: AfSpacing.s16),
                                  AlbumActionRow(
                                    album: album,
                                    tracks: tracks,
                                    onPlay: () => ref
                                        .read(playActionsProvider)
                                        .playAlbum(tracks),
                                    onMore: () => showAlbumMoreSheet(
                                      context,
                                      ref,
                                      album,
                                      tracks,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: AfSpacing.s24),
                          ),
                          SliverToBoxAdapter(
                            child: StaggerReveal(
                              children: [
                                for (var i = 0; i < tracks.length; i++) ...[
                                  if (i > 0)
                                    const SizedBox(height: AfSpacing.s4),
                                  AlbumTrackRowItem(
                                    track: tracks[i],
                                    index: i,
                                    activeId: activeId,
                                    tracks: tracks,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          wikiAsync.maybeWhen(
                            data: (wiki) {
                              if (wiki == null ||
                                  wiki.wiki == null ||
                                  wiki.wiki!.isEmpty) {
                                return const SliverToBoxAdapter(
                                  child: SizedBox(),
                                );
                              }
                              return SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AfSpacing.gutterGenerous,
                                    vertical: AfSpacing.s24,
                                  ),
                                  child: AlbumWikiPanel(
                                    wiki: wiki.wiki!,
                                    listeners: wiki.listeners,
                                    playCount: wiki.playCount,
                                  ),
                                ),
                              );
                            },
                            orElse: () =>
                                const SliverToBoxAdapter(child: SizedBox()),
                          ),
                          const SliverToBoxAdapter(
                            child: SizedBox(
                              height: AfSpacing.bottomInsetWithMiniAndNav,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // App bar — rendered on top of scroll content.
                ValueListenableBuilder<double>(
                  valueListenable: _scrollOffset,
                  builder: (context, offset, _) => Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: OpacityAppBar(
                      scrollOffset: offset,
                      threshold: heroHeight - kToolbarHeight,
                      title: album.name,
                      onBack: () {
                        if (context.canPop()) context.pop();
                      },
                      onMore: () =>
                          showAlbumMoreSheet(context, ref, album, tracks),
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
