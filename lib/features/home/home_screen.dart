import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/audio/play_actions.dart';
import '../../core/battery_opt.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/artwork.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/skeletons/home_skeleton.dart';
import '../library/songs_screen.dart' show SongsPill, songsPillProvider;

/// Aetherfin Reworked Home Screen — Magazine/Editorial Neo-Brutalist Hybrid.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestBatteryExemptionIfNeeded();
    });
  }

  Future<void> _requestBatteryExemptionIfNeeded() async {
    final alreadyIgnoring = await BatteryOpt.isIgnoring();
    if (!alreadyIgnoring && mounted) {
      await BatteryOpt.requestIgnore();
    }
  }

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
    final isLocal = ref.watch(appModeProvider) == AppMode.local;
    final albumsAsync = ref.watch(recentlyAddedAlbumsProvider);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AfColors.indigo300,
        backgroundColor: AfColors.surfaceBase,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            // Architectural Header
            SliverToBoxAdapter(
              child: _HomeHeader(
                greeting: _getGreeting(),
                isLocal: isLocal,
              ),
            ),

            // Magazine Cover Carousel
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AfSpacing.s12),
                child: albumsAsync.when(
                  data: (albums) => albums.isEmpty
                      ? const SizedBox.shrink()
                      : _MagazineCarousel(albums: albums),
                  loading: () => const HomeCarouselSkeleton(),
                  error: (e, _) => AsyncErrorView.compact(
                    label: 'Couldn\u2019t load recent albums',
                    error: e,
                    height: 192,
                    onRetry: () => ref.invalidate(recentlyAddedAlbumsProvider),
                  ),
                ),
              ),
            ),

            // Recently Played with outline indices
            _ReworkedRecentTracksSection(isLocal: isLocal),

            // Lost Memories (Vinyl record style)
            const _ReworkedLostMemoriesSection(),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.sectionGap),
            ),

            // Architectural Artists
            _ReworkedArtistsSection(isLocal: isLocal),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.sectionGap),
            ),

            // Bento Genres Grid
            _ReworkedGenresSection(isLocal: isLocal),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asymmetric modern header layout
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.greeting, required this.isLocal});
  final String greeting;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        AfSpacing.s16,
        AfSpacing.s16,
        AfSpacing.s24,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting & design tag
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      timeStr,
                      style: AfTypography.label.copyWith(
                        color: AfColors.indigo400,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AfColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'DISCOVER ARCHIVE',
                      style: AfTypography.label.copyWith(
                        color: AfColors.textTertiary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  greeting,
                  style: AfTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          
          // Bento Control Capsule
          Container(
            decoration: BoxDecoration(
              color: AfColors.surfaceBase,
              borderRadius: BorderRadius.circular(AfRadii.lg),
              border: Border.all(
                color: AfColors.surfaceHigh,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AfColors.surfaceLow,
                    borderRadius: BorderRadius.circular(AfRadii.md),
                  ),
                  child: Text(
                    isLocal ? 'LOCAL' : 'SERVER',
                    style: AfTypography.caption.copyWith(
                      color: AfColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(LucideIcons.cast, size: 18),
                  onPressed: () => context.push('/cast'),
                  tooltip: 'Output',
                  style: IconButton.styleFrom(
                    backgroundColor: AfColors.surfaceRaised,
                    foregroundColor: AfColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AfRadii.md),
                    ),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A 3D-transform Magazine Stack Carousel
class _MagazineCarousel extends ConsumerStatefulWidget {
  const _MagazineCarousel({required this.albums});
  final List<AfAlbum> albums;

  @override
  ConsumerState<_MagazineCarousel> createState() => _MagazineCarouselState();
}

class _MagazineCarouselState extends ConsumerState<_MagazineCarousel> {
  final PageController _pageController = PageController(viewportFraction: 0.82);
  double _page = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (mounted) {
        setState(() {
          _page = _pageController.page ?? 0.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.albums.take(5).toList();
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _pageController,
            itemCount: list.length,
            itemBuilder: (context, index) {
              final album = list[index];
              final delta = index - _page;

              // Matrix4 transforms for 3D stack overlap style
              final rotate = delta.clamp(-1.0, 1.0) * 0.12;
              final scale = 1.0 - (delta.abs().clamp(0.0, 1.0) * 0.08);
              final translateX = delta * -24.0;

              return Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001) // perspective
                  ..multiply(Matrix4.translationValues(translateX, 0.0, 0.0))
                  ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0))
                  ..rotateY(rotate),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: (1.0 - delta.abs() * 0.4).clamp(0.0, 1.0),
                  child: _MagazineAlbumCard(
                    album: album,
                    index: index,
                    onTap: () => context.push('/album/${album.id}'),
                    onPlay: () async {
                      final tracks = ref.read(playActionsProvider);
                      final detail = await ref.read(
                        albumDetailProvider(album.id).future,
                      );
                      if (detail != null) {
                        await tracks.playAlbum(detail.tracks);
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            list.length,
            (i) => AnimatedContainer(
              duration: AfDurations.quick,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _page.round() == i ? 20 : 6,
              height: 4,
              decoration: BoxDecoration(
                color: _page.round() == i
                    ? AfColors.indigo400
                    : AfColors.surfaceHigh,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Magazine styled album card with index and minimal design
class _MagazineAlbumCard extends StatelessWidget {
  const _MagazineAlbumCard({
    required this.album,
    required this.index,
    this.onTap,
    this.onPlay,
  });

  final AfAlbum album;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          color: AfColors.surfaceBase,
          border: Border.all(color: AfColors.surfaceHigh, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Background image blur or solid
            Positioned.fill(
              child: Artwork(
                url: album.imageUrl,
                size: double.infinity,
                fit: BoxFit.cover,
                radius: BorderRadius.zero,
              ),
            ),

            // Minimalist Magazine Overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AfColors.surfaceCanvas.withValues(alpha: 0.95),
                      AfColors.surfaceCanvas.withValues(alpha: 0.4),
                      AfColors.surfaceCanvas.withValues(alpha: 0.2),
                    ],
                  ),
                ),
              ),
            ),

            // Top meta info
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AfColors.surfaceCanvas.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'EDITION 0${index + 1}',
                      style: AfTypography.caption.copyWith(
                        color: AfColors.indigo300,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Transparent playing badge
                  Icon(
                    LucideIcons.disc,
                    color: AfColors.textPrimary.withValues(alpha: 0.5),
                    size: 18,
                  ),
                ],
              ),
            ),

            // Bottom editorial contents
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AfTypography.titleMedium.copyWith(
                            color: AfColors.textPrimary,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          album.artistName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AfTypography.caption.copyWith(
                            color: AfColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Small play circle
                  GestureDetector(
                    onTap: onPlay,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AfColors.textPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AfColors.surfaceCanvas,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recently Played tracks list with large outline indicators
class _ReworkedRecentTracksSection extends ConsumerWidget {
  const _ReworkedRecentTracksSection({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = isLocal
        ? ref.watch(localTracksProvider)
        : ref.watch(recentlyPlayedTracksProvider);

    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AfSpacing.s16,
            AfSpacing.s16,
            AfSpacing.s16,
            AfSpacing.s8,
          ),
          child: SectionHeader(
            title: 'RECENT ARCHIVES',
            actionLabel: 'OPEN ALL',
            onActionTap: () => context.go('/library'),
          ),
        ),
        tracksAsync.when(
          data: (tracks) {
            final top5 = tracks.take(5).toList();
            if (top5.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: Container(
                decoration: BoxDecoration(
                  color: AfColors.surfaceLow,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  border: Border.all(
                    color: AfColors.surfaceHigh,
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: top5.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: AfColors.surfaceHigh.withValues(alpha: 0.3),
                    indent: 64,
                    endIndent: 16,
                  ),
                  itemBuilder: (context, i) {
                    final t = top5[i];
                    final indexStr = '0${i + 1}';

                    return InkWell(
                      onTap: () => ref.read(playActionsProvider).playSingle(t),
                      onLongPress: () => showTrackContextMenu(context, ref, t),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            // Big Outline Index Number
                            SizedBox(
                              width: 36,
                              child: Text(
                                indexStr,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AfColors.indigo400.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Small artwork
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Artwork(
                                url: t.imageUrl,
                                size: 40,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Title & artist info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AfTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    t.artistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AfTypography.caption.copyWith(
                                      color: AfColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Action button
                            Icon(
                              LucideIcons.moreHorizontal,
                              color: AfColors.textTertiary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
          loading: () => const HomeRecentSkeleton(),
          error: (e, _) => AsyncErrorView.compact(
            label: 'Couldn\'t load recently played',
            error: e,
            height: 80,
            onRetry: () => ref.invalidate(
              isLocal ? localTracksProvider : recentlyPlayedTracksProvider,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Horizontal scroll of recently played-but-old tracks (lost memories) with Vinyl style
class _ReworkedLostMemoriesSection extends ConsumerWidget {
  const _ReworkedLostMemoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(lostMemoriesProvider);

    return tracksAsync.when(
      data: (tracks) {
        if (tracks.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        final list = tracks.take(10).toList();
        return SliverList(
          delegate: SliverChildListDelegate([
            const SizedBox(height: AfSpacing.sectionGap),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: SectionHeader(
                title: 'RETRO STACK',
                actionLabel: 'SPIN ALL',
                onActionTap: () =>
                    ref.read(playActionsProvider).playQueue(list),
              ),
            ),
            const SizedBox(height: AfSpacing.s16),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                itemCount: list.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 16),
                itemBuilder: (context, i) {
                  final t = list[i];
                  return GestureDetector(
                    onTap: () => ref.read(playActionsProvider).playSingle(t),
                    onLongPress: () => showTrackContextMenu(context, ref, t),
                    child: SizedBox(
                      width: 150,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Vinyl Record slipping out of right side
                          Positioned(
                            top: 4,
                            right: 4,
                            bottom: 4,
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF0F1013),
                                  border: Border.all(
                                    color: Colors.black,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 4,
                                      offset: const Offset(1, 1),
                                    )
                                  ],
                                ),
                                child: Center(
                                  // Vinyl label
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: const BoxDecoration(
                                      color: AfColors.indigo900,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AfColors.surfaceCanvas,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Album Cover Art on Left
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 110,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                    offset: const Offset(-2, 2),
                                  )
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Artwork(
                                url: t.imageUrl,
                                size: double.infinity,
                              ),
                            ),
                          ),

                          // Floating small description at bottom left
                          Positioned(
                            left: 0,
                            right: 44,
                            bottom: 4,
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.7),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AfColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    t.artistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 8,
                                      color: AfColors.textTertiary,
                                    ),
                                  ),
                                ],
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
          ]),
        );
      },
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

/// Horizontal scroll of artists with offset floating rings
class _ReworkedArtistsSection extends ConsumerWidget {
  const _ReworkedArtistsSection({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsAsync = isLocal
        ? ref.watch(localArtistsProvider)
        : ref.watch(allArtistsProvider);

    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'CREATORS & ARTISTS',
            actionLabel: 'EXPLORE',
            onActionTap: () {
              ref.read(songsPillProvider.notifier).state = SongsPill.artists;
              context.go('/library');
            },
          ),
        ),
        const SizedBox(height: AfSpacing.s16),
        artistsAsync.when(
          loading: () => const HomeArtistsSkeleton(),
          error: (e, _) => AsyncErrorView.compact(
            label: 'Couldn\'t load artists',
            error: e,
            height: 172,
            onRetry: () => ref.invalidate(
              isLocal ? localArtistsProvider : allArtistsProvider,
            ),
          ),
          data: (artists) => SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              itemCount: artists.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: 20),
              itemBuilder: (context, i) {
                final a = artists[i];
                return GestureDetector(
                  onTap: () {
                    ref.read(songsPillProvider.notifier).state =
                        SongsPill.artists;
                    context.go('/library');
                  },
                  child: SizedBox(
                    width: 100,
                    child: Column(
                      children: [
                        // Avatar with offset floating ring
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Offset outline ring behind
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AfColors.indigo400.withValues(
                                      alpha: 0.4,
                                    ),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            // Main avatar image
                            Container(
                              width: 90,
                              height: 90,
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
                                size: 90,
                                radius: BorderRadius.circular(45),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
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
                          '${a.albumCount} ALBUMS',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            color: AfColors.textTertiary,
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
      ]),
    );
  }
}

/// Bento Grid for Genres Section
class _ReworkedGenresSection extends ConsumerWidget {
  const _ReworkedGenresSection({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = isLocal
        ? ref.watch(localGenresProvider)
        : ref.watch(allGenresProvider);

    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'SOUNDSCAPES',
            actionLabel: 'BROWSE ALL',
            onActionTap: () {
              ref.read(songsPillProvider.notifier).state = SongsPill.genres;
              context.go('/library');
            },
          ),
        ),
        const SizedBox(height: AfSpacing.s16),
        genresAsync.when(
          data: (genres) {
            final list = genres.take(4).toList();
            if (list.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = (constraints.maxWidth - 12) / 2;
                  return Column(
                    children: [
                      Row(
                        children: [
                          _BentoGenreCard(
                            genre: list[0],
                            width: cardWidth,
                            height: 110,
                            isLocal: isLocal,
                            ref: ref,
                          ),
                          const SizedBox(width: 12),
                          if (list.length > 1)
                            _BentoGenreCard(
                              genre: list[1],
                              width: cardWidth,
                              height: 140, // Asymmetric heights!
                              isLocal: isLocal,
                              ref: ref,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (list.length > 2)
                            _BentoGenreCard(
                              genre: list[2],
                              width: cardWidth,
                              height: 140, // Asymmetric heights!
                              isLocal: isLocal,
                              ref: ref,
                            ),
                          const SizedBox(width: 12),
                          if (list.length > 3)
                            _BentoGenreCard(
                              genre: list[3],
                              width: cardWidth,
                              height: 110,
                              isLocal: isLocal,
                              ref: ref,
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, _) => AsyncErrorView.compact(
            label: 'Couldn\'t load genres',
            error: e,
            height: 96,
            onRetry: () => ref.invalidate(
              isLocal ? localGenresProvider : allGenresProvider,
            ),
          ),
        ),
      ]),
    );
  }
}

/// A bento grid genre block with vertical/large text overlay
class _BentoGenreCard extends StatelessWidget {
  const _BentoGenreCard({
    required this.genre,
    required this.width,
    required this.height,
    required this.isLocal,
    required this.ref,
  });

  final AfGenre genre;
  final double width;
  final double height;
  final bool isLocal;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ref.read(songsPillProvider.notifier).state = SongsPill.genres;
        context.go('/library');
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AfColors.surfaceLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AfColors.surfaceHigh,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Artwork on lower right corner
            Positioned(
              bottom: -16,
              right: -16,
              width: width * 0.6,
              height: height * 0.7,
              child: Opacity(
                opacity: 0.65,
                child: Transform.rotate(
                  angle: -0.2,
                  child: Artwork(
                    url: genre.imageUrl,
                    size: width * 0.6,
                  ),
                ),
              ),
            ),
            
            // Large architectural label
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    genre.name.toUpperCase(),
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
                    width: 12,
                    height: 2,
                    color: AfColors.indigo400,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
