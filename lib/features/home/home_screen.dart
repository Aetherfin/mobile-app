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
  final ScrollController _scrollController = ScrollController();
  DateTime? _lastRefreshAt;

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
    _scrollController.dispose();
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
        Future.delayed(AfDurations.expressive, () {
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
  /// Throttled to once per 60 seconds.
  Future<void> _onRefresh() async {
    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < const Duration(seconds: 60)) {
      return;
    }
    _lastRefreshAt = now;
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

    // ponytail: select only the two fields used in this build — avoids
    // rebuilding the full home tree when other spectral fields change.
    final (primary, secondary) = ref.watch(
      currentSpectralProvider.select((s) => (s.primary, s.secondary)),
    );

    return FocusTraversalGroup(
      child: SafeArea(
        // ponytail: LayoutBuilder removed — constraints param was never read.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AfLayout.maxContentWidth,
            ),
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: primary,
              backgroundColor: AfColors.surfaceBase,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                slivers: [
                  // Collapsing "Listen" header with spectral gradient.
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _CollapseHeaderDelegate(
                      spectral: (primary: primary, secondary: secondary),
                      onCastTap: () => context.push('/cast'),
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Local helpers
// ---------------------------------------------------------------------------

/// Collapsing header delegate for the "Listen" title on the home screen.
///
/// Transitions from a large spectral-gradient title (expanded) to a compact
/// solid-color title (collapsed) as the user scrolls. The cast button stays
/// pinned on the right throughout.
class _CollapseHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CollapseHeaderDelegate({required this.spectral, required this.onCastTap});

  final ({Color primary, Color secondary}) spectral;
  final VoidCallback onCastTap;

  static const _expandedHeight = 80.0;
  static const _collapsedHeight = 56.0;
  static const _collapseThreshold = 100.0;

  @override
  double get minExtent => _collapsedHeight;
  @override
  double get maxExtent => _expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final t = (shrinkOffset / _collapseThreshold).clamp(0.0, 1.0);
    final bgColor = Color.lerp(Colors.transparent, AfColors.surfaceBase, t)!;

    return Container(
      color: bgColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AfSpacing.s16,
            AfSpacing.s8 * (1 - t),
            AfSpacing.s16,
            AfSpacing.s8,
          ),
          child: Row(
            children: [
              if (t < 1.0)
                Expanded(
                  child: Opacity(
                    opacity: 1.0 - t,
                    child: Transform.scale(
                      scale: 1.0 - t * 0.15,
                      alignment: Alignment.centerLeft,
                      child: ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [spectral.primary, spectral.secondary],
                        ).createShader(bounds),
                        child: Text(
                          'Listen',
                          style: AfTypography.display.copyWith(
                            color: AfColors.textOnPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (t >= 1.0)
                Expanded(
                  child: Text(
                    'Listen',
                    style: AfTypography.titleMedium.copyWith(
                      color: AfColors.textPrimary,
                    ),
                  ),
                ),
              _GlassCastButton(onTap: onCastTap),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CollapseHeaderDelegate oldDelegate) {
    return spectral.primary != oldDelegate.spectral.primary ||
        spectral.secondary != oldDelegate.spectral.secondary ||
        onCastTap != oldDelegate.onCastTap;
  }
}

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
