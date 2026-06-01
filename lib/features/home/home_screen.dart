import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/battery_opt.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/hero_album_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/home_skeleton.dart';
import '../library/songs_screen.dart' show SongsPill, songsPillProvider;

/// Mockup 04 — Home.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
  @override
  void initState() {
    super.initState();
    // Request battery-optimization exemption on first visit.
    // Required for reliable auto-advance when the screen is off —
    // without this, Doze can freeze the Dart isolate between tracks
    // on Samsung, Xiaomi, and other aggressive OEMs.
    // The system shows its own dialog; we only fire it if not already exempt.
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  AfSpacing.s16,
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getGreeting(),
                          style: AfTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'What are we playing today?',
                          style: AfTypography.bodySmall.copyWith(
                            color: AfColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: AfColors.surfaceLow,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AfColors.surfaceHigh.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(LucideIcons.cast, size: 20),
                        onPressed: () => context.push('/cast'),
                        tooltip: 'Output',
                        color: AfColors.textSecondary,
                      ),
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
                    : _HeroAlbumCarousel(albums: albums),
                loading: () => const HomeCarouselSkeleton(),
                error: (e, _) => AsyncErrorView.compact(
                  label: 'Couldn\u2019t load recent albums',
                  error: e,
                  height: 192,
                  onRetry: () => ref.invalidate(recentlyAddedAlbumsProvider),
                ),
              ),
            ),

            _RecentTracksSection(isLocal: isLocal),

            const _LostMemoriesSection(),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.sectionGap),
            ),

            _ArtistsSection(isLocal: isLocal),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.sectionGap),
            ),

            _GenresSection(isLocal: isLocal),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extracted section widgets
// ---------------------------------------------------------------------------

/// Top-5 recently played tracks with header.
class _RecentTracksSection extends ConsumerWidget {
  const _RecentTracksSection({required this.isLocal});
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
            AfSpacing.s16, 0, AfSpacing.s16, AfSpacing.s8,
          ),
          child: SectionHeader(
            title: 'Recently played',
            actionLabel: 'See more',
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
                  borderRadius: BorderRadius.circular(AfRadii.lg),
                  border: Border.all(
                    color: AfColors.surfaceHigh.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: top5.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: AfColors.surfaceHigh.withValues(alpha: 0.5),
                    // indent starts after the artwork + padding
                    indent: AfSpacing.s16 + 56 + AfSpacing.s12,
                    endIndent: AfSpacing.s16,
                  ),
                  itemBuilder: (context, i) {
                    final t = top5[i];
                    return TrackRow(
                      track: t,
                      density: TrackRowDensity.generous,
                      onTap: () =>
                          ref.read(playActionsProvider).playSingle(t),
                      onLongPress: () =>
                          showTrackContextMenu(context, ref, t),
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

/// Horizontal scroll of recently played-but-old tracks (lost memories).
class _LostMemoriesSection extends ConsumerWidget {
  const _LostMemoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(lostMemoriesProvider);
    return tracksAsync.when(
      data: (tracks) {
        if (tracks.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverList(
          delegate: SliverChildListDelegate([
            const SizedBox(height: AfSpacing.sectionGap),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: SectionHeader(
                title: 'Lost memories',
                actionLabel: 'Play all',
                onActionTap: () =>
                    ref.read(playActionsProvider).playQueue(tracks),
              ),
            ),
            const SizedBox(height: AfSpacing.s12),
            SizedBox(
              height: 172,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                itemCount: tracks.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: AfSpacing.s12),
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return Tile(
                    title: t.title,
                    subtitle: t.artistName,
                    variant: TileVariant.album,
                    imageUrl: t.imageUrl,
                    size: 100,
                    onTap: () => ref.read(playActionsProvider).playSingle(t),
                    onLongPress: () => showTrackContextMenu(context, ref, t),
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

/// Horizontal scroll of artists with section header.
class _ArtistsSection extends ConsumerWidget {
  const _ArtistsSection({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsAsync = isLocal
        ? ref.watch(localArtistsProvider)
        : ref.watch(allArtistsProvider);
    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: AfSpacing.sectionGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'Artists',
            actionLabel: 'See more',
            onActionTap: () {
              ref.read(songsPillProvider.notifier).state = SongsPill.artists;
              context.go('/library');
            },
          ),
        ),
        const SizedBox(height: AfSpacing.s12),
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
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              itemCount: artists.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AfSpacing.s12),
              itemBuilder: (context, i) {
                final a = artists[i];
                return Tile(
                  title: a.name,
                  subtitle: '${a.albumCount} albums',
                  variant: TileVariant.artist,
                  imageUrl: a.imageUrl,
                  size: 100,
                  onTap: () {
                    ref.read(songsPillProvider.notifier).state =
                        SongsPill.artists;
                    context.go('/library');
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// Horizontal scroll of genre chips with section header.
class _GenresSection extends ConsumerWidget {
  const _GenresSection({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = isLocal
        ? ref.watch(localGenresProvider)
        : ref.watch(allGenresProvider);
    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: AfSpacing.sectionGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'Genres',
            actionLabel: 'See more',
            onActionTap: () {
              ref.read(songsPillProvider.notifier).state = SongsPill.genres;
              context.go('/library');
            },
          ),
        ),
        const SizedBox(height: AfSpacing.s12),
        SizedBox(
          height: 96,
          child: genresAsync.when(
            data: (genres) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              itemCount: genres.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AfSpacing.s12),
              itemBuilder: (context, i) {
                final g = genres[i];
                return GenreTile(
                  name: g.name,
                  tint: _hex(g.tint),
                  imageUrl: g.imageUrl,
                  onTap: () {
                    ref.read(songsPillProvider.notifier).state =
                        SongsPill.genres;
                    context.go('/library');
                  },
                );
              },
            ),
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
        ),
      ]),
    );
  }
}

/// Swipeable carousel of hero album cards with a dot indicator.
class _HeroAlbumCarousel extends ConsumerStatefulWidget {
  const _HeroAlbumCarousel({required this.albums});
  final List<AfAlbum> albums;

  @override
  ConsumerState<_HeroAlbumCarousel> createState() => _HeroAlbumCarouselState();
}

class _HeroAlbumCarouselState extends ConsumerState<_HeroAlbumCarousel> {
  int _currentPage = 0;
  final PageController _pageController = PageController(viewportFraction: 1.0);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albums = widget.albums.take(5).toList();
    if (albums.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 192,
          child: PageView.builder(
            controller: _pageController,
            itemCount: albums.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, i) {
              final album = albums[i];
              return Consumer(
                builder: (context, ref, _) {
                  return HeroAlbumCard(
                    album: album,
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
                  );
                },
              );
            },
          ),
        ),
        if (albums.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              albums.length,
              (i) => AnimatedContainer(
                duration: AfDurations.quick,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentPage == i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentPage == i
                      ? AfColors.indigo400
                      : AfColors.surfaceMax,
                  borderRadius: AfRadii.borderPill,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Parses a hex colour string (6 or 8 digits with optional #) into a [Color].
Color _hex(String hex) {
  try {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return AfColors.indigo600;
    final value = int.parse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return Color(value);
  } catch (_) {
    return AfColors.indigo600;
  }
}
