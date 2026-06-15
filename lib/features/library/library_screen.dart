import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tile.dart';
import '../../widgets/bottom_sheet.dart';
import '../../widgets/spring_chip.dart';
import 'sections/albums_tab.dart';
import 'sections/artists_tab.dart';
import 'sections/genres_tab.dart';
import 'sections/library_search.dart';
import 'sections/songs_tab.dart';

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

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  SongsPill _pill = SongsPill.songs;
  final _scroll = ScrollController();
  late final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () => _scrollOffset.value = _scroll.hasClients ? _scroll.offset : 0.0,
    );
    final pill = ref.read(songsPillProvider);
    if (pill != null && mounted) {
      _pill = pill;
      ref.read(songsPillProvider.notifier).state = null;
    }
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _openSearch(BuildContext context) {
    showBlurBottomSheet(context: context, child: const LibrarySearch());
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

    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );

    return FocusTraversalGroup(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AfLayout.maxContentWidth,
                ),
                child: AfScrollbar(
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      // ── Header row: gradient title + search icon ──
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AfSpacing.s16,
                            AfSpacing.s16,
                            AfSpacing.s16,
                            AfSpacing.s12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: ShaderMask(
                                  shaderCallback: (bounds) => LinearGradient(
                                    colors: [
                                      spectral.primary,
                                      spectral.secondary,
                                    ],
                                  ).createShader(bounds),
                                  child: Text(
                                    'Library',
                                    style: AfTypography.display.copyWith(
                                      color: AfColors.textOnPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              PressScale(
                                onTap: () => _openSearch(context),
                                child: Semantics(
                                  button: true,
                                  label: 'Search library',
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AfColors.glassFill,
                                      borderRadius: AfRadii.borderPill,
                                      border: Border.all(
                                        color: AfColors.glassBorderStrong,
                                        width: 1,
                                      ),
                                    ),
                                    child: const Icon(
                                      LucideIcons.search,
                                      color: AfColors.textSecondary,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Recently Added ──
                      SliverToBoxAdapter(
                        child: _RecentlyAddedSection(isLocal: isLocal),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AfSpacing.s12),
                      ),

                      // ── Pill Bar (pinned on scroll) ──
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _PillBarDelegate(
                          selected: _pill,
                          onChanged: (v) => setState(() => _pill = v),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AfSpacing.s12),
                      ),

                      // ── Section Content ──
                      switch (_pill) {
                        SongsPill.songs => SongsTab(isLocal: isLocal),
                        SongsPill.artists => ArtistsTab(isLocal: isLocal),
                        SongsPill.albums => AlbumsTab(isLocal: isLocal),
                        SongsPill.genres => GenresTab(isLocal: isLocal),
                      },
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Pill Bar SliverPersistentHeader Delegate ──

class _PillBarDelegate extends SliverPersistentHeaderDelegate {
  _PillBarDelegate({required this.selected, required this.onChanged});
  final SongsPill selected;
  final ValueChanged<SongsPill> onChanged;

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: _PillBar(selected: selected, onChanged: onChanged),
    );
  }

  @override
  bool shouldRebuild(covariant _PillBarDelegate old) =>
      old.selected != selected;
}

// ── Recently Added Section ──

class _RecentlyAddedSection extends ConsumerWidget {
  const _RecentlyAddedSection({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localAlbumsProvider : allAlbumsProvider;
    final albums = ref.watch(provider);

    return albums.when(
      data: (list) {
        final recent = list.take(10).toList();
        if (recent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: SectionHeader(title: 'Recently Added', uppercase: true),
            ),
            const SizedBox(height: AfSpacing.s12),
            Builder(
              builder: (context) {
                // Tile = artwork + s8 + title (line-height 22) + s2 + subtitle (16).
                // Scale the text area with the user's text scaler (clamped to
                // 0.85-1.3 by the root MediaQuery) so this never overflows
                // across devices or accessibility settings.
                final mq = MediaQuery.of(context);
                final screenH = mq.size.height;
                final textScale = mq.textScaler.scale(1.0);
                final artworkSize = screenH * 0.175;
                final textArea = (22 + AfSpacing.s2 + 16) * textScale + 4;
                final rowHeight = artworkSize + AfSpacing.s8 + textArea;
                return SizedBox(
                  height: rowHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s16,
                    ),
                    itemCount: recent.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AfSpacing.s12),
                    itemBuilder: (context, i) {
                      final a = recent[i];
                      return Tile(
                        title: a.name,
                        subtitle: a.artistName,
                        imageUrl: a.imageUrl,
                        variant: TileVariant.album,
                        size: artworkSize,
                        onTap: () => context.push('/album/${a.id}'),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        );
      },
      loading: () => Builder(
        builder: (context) {
          final mq = MediaQuery.of(context);
          final screenH = mq.size.height;
          final textScale = mq.textScaler.scale(1.0);
          final artworkSize = screenH * 0.175;
          final textArea = (22 + AfSpacing.s2 + 16) * textScale + 4;
          final rowHeight = artworkSize + AfSpacing.s8 + textArea;
          return SizedBox(
            height: rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: Row(
                children: [
                  SkeletonBlock(
                    width: artworkSize,
                    height: artworkSize,
                    borderRadius: AfRadii.borderMd,
                  ),
                  const SizedBox(width: AfSpacing.s12),
                  SkeletonBlock(
                    width: artworkSize,
                    height: artworkSize,
                    borderRadius: AfRadii.borderMd,
                  ),
                  const SizedBox(width: AfSpacing.s12),
                  SkeletonBlock(
                    width: artworkSize,
                    height: artworkSize,
                    borderRadius: AfRadii.borderMd,
                  ),
                ],
              ),
            ),
          );
        },
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ── Pill Bar (animated with easeOutBack) ──

class _PillBar extends ConsumerWidget {
  const _PillBar({required this.selected, required this.onChanged});
  final SongsPill selected;
  final ValueChanged<SongsPill> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return SizedBox(
      height: 44,
      child: Row(
        children: List.generate(SongsPill.values.length, (i) {
          final pill = SongsPill.values[i];
          return Expanded(
            child: Semantics(
              button: true,
              label: '${pill.label} tab',
              child: SpringChip(
                label: pill.label,
                isSelected: pill == selected,
                onTap: () => onChanged(pill),
                selectedColor: spectral,
                unselectedColor: AfColors.surfaceRaised,
              ),
            ),
          );
        }),
      ),
    );
  }
}
