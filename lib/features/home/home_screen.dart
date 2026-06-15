import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/battery_opt.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../state/youtube_music_providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/gradient_header.dart';
import '../../widgets/mesh_gradient_background.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/skeletons/home_skeleton.dart';
import 'sections/hero_carousel.dart';
import 'sections/recently_played_section.dart';
import 'sections/lost_memories_section.dart';
import 'sections/artists_section.dart';
import 'sections/genres_section.dart';
import 'sections/youtube_section.dart';

/// Home screen — Dark Moody edition.
///
/// Large serif "Listen" header with amber gradient text, hero album
/// carousel, recently played tracks with spectral accent, lost memories,
/// artists with warm glow rings, and genre glass cards.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _ytScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ytScrollController.addListener(_onYtScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestBatteryExemptionIfNeeded();
      _autoLoadContinuationIfNeeded();
    });
  }

  @override
  void dispose() {
    _ytScrollController.dispose();
    super.dispose();
  }

  void _onYtScroll() {
    if (_ytScrollController.position.pixels >=
        _ytScrollController.position.maxScrollExtent - 200) {
      ref.read(youtubeHomeProvider.notifier).loadMore();
    }
  }

  /// Auto-fetch continuation if initial content is too short for scroll.
  void _autoLoadContinuationIfNeeded() {
    final homeAsync = ref.read(youtubeHomeProvider);
    homeAsync.whenData((home) {
      if (home.continuation != null && home.sections.length < 5) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            ref.read(youtubeHomeProvider.notifier).loadMore();
          }
        });
      }
    });
  }

  Future<void> _requestBatteryExemptionIfNeeded() async {
    final alreadyIgnoring = await BatteryOpt.isIgnoring();
    if (!alreadyIgnoring && mounted) {
      await BatteryOpt.requestIgnore();
    }
  }

  /// Pull-to-refresh handler. Invalidates every provider the Home
  /// screen reads, then awaits each one's next value so the spinner
  /// stays visible until the refetch actually completes.
  Future<void> _onRefresh() async {
    final isLocal = ref.read(appModeProvider) == AppMode.local;
    ref.invalidate(recentlyAddedAlbumsProvider);
    ref.invalidate(lostMemoriesProvider);
    if (isLocal) {
      ref.invalidate(localTracksProvider);
      ref.invalidate(localArtistsProvider);
      ref.invalidate(localGenresProvider);
    } else {
      ref.invalidate(recentlyPlayedTracksProvider);
      ref.invalidate(allArtistsProvider);
      ref.invalidate(allGenresProvider);
    }
    await Future.wait<Object?>([
      ref.read(recentlyAddedAlbumsProvider.future),
      ref.read(lostMemoriesProvider.future),
      ref.read(
        (isLocal ? localTracksProvider : recentlyPlayedTracksProvider).future,
      ),
      ref.read((isLocal ? localArtistsProvider : allArtistsProvider).future),
      ref.read((isLocal ? localGenresProvider : allGenresProvider).future),
    ]).catchError((_) => const <Object?>[]);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;
    final isYouTube = mode == AppMode.youtubeMusic;
    final albumsAsync = ref.watch(recentlyAddedAlbumsProvider);

    // YouTube Music: home with trending content from region.
    if (isYouTube) {
      return YouTubeHomeView(scrollController: _ytScrollController);
    }

    return MeshGradientBackground(
      child: FocusTraversalGroup(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AfLayout.maxContentWidth,
                ),
                child: RefreshIndicator(
                  onRefresh: _onRefresh,
                  color: ref.watch(
                    currentSpectralProvider.select((s) => s.primary),
                  ),
                  backgroundColor: AfColors.surfaceBase,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    slivers: [
                      // Header — "Listen" with amber gradient + cast button
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AfSpacing.s16,
                            AfSpacing.s16,
                            AfSpacing.s16,
                            AfSpacing.s32,
                          ),
                          child: Row(
                            children: [
                              const GradientHeader(text: 'Listen'),
                              const Spacer(),
                              _GlassCastButton(
                                onTap: () => context.push('/cast'),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Hero album carousel.
                      SliverToBoxAdapter(
                        child: albumsAsync.when(
                          data: (albums) => albums.isEmpty
                              ? const SizedBox.shrink()
                              : HeroAlbumCarousel(albums: albums),
                          loading: () => const HomeCarouselSkeleton(),
                          error: (e, _) => AsyncErrorView.compact(
                            label: 'Couldn\u2019t load recent albums',
                            error: e,
                            height: 240,
                            onRetry: () =>
                                ref.invalidate(recentlyAddedAlbumsProvider),
                          ),
                        ),
                      ),

                      RecentTracksSection(isLocal: isLocal),

                      const LostMemoriesSection(),

                      const SliverToBoxAdapter(
                        child: SizedBox(height: AfSpacing.sectionGap),
                      ),

                      ArtistsSection(isLocal: isLocal),

                      const SliverToBoxAdapter(
                        child: SizedBox(height: AfSpacing.sectionGap),
                      ),

                      GenresSection(isLocal: isLocal),

                      const SliverToBoxAdapter(
                        child: SizedBox(
                          height: AfSpacing.bottomInsetWithMiniAndNav,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Local helpers
// ---------------------------------------------------------------------------

/// Glass pill button for the cast icon in the header.
class _GlassCastButton extends StatelessWidget {
  const _GlassCastButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Audio output',
      child: PressScale(
        ensureHitTarget: true,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: AfRadii.borderPill,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(AfSpacing.s12),
              decoration: BoxDecoration(
                color: AfColors.glassFill,
                borderRadius: AfRadii.borderPill,
                border: Border.all(color: AfColors.glassBorderStrong, width: 1),
              ),
              child: const Icon(
                LucideIcons.cast,
                size: 18,
                color: AfColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
