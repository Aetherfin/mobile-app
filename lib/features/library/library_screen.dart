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

class _PillBar extends ConsumerStatefulWidget {
  const _PillBar({required this.selected, required this.onChanged});
  final SongsPill selected;
  final ValueChanged<SongsPill> onChanged;

  @override
  ConsumerState<_PillBar> createState() => _PillBarState();
}

class _PillBarState extends ConsumerState<_PillBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _fromIndex = 0;
  int _toIndex = 0;

  @override
  void initState() {
    super.initState();
    _toIndex = SongsPill.values.indexOf(widget.selected);
    _fromIndex = _toIndex;
    _ctrl = AnimationController(vsync: this, duration: AfDurations.long)
      ..value = 1.0;
  }

  @override
  void didUpdateWidget(_PillBar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      _fromIndex = _toIndex;
      _toIndex = SongsPill.values.indexOf(widget.selected);
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final count = SongsPill.values.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final segWidth = constraints.maxWidth / count;

        return ClipRRect(
          borderRadius: AfRadii.borderPill,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: AfColors.surfaceRaised),
            child: SizedBox(
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      final curved = Curves.easeOutBack.transform(_ctrl.value);
                      final damped = curved > 1.0
                          ? 1.0 + (curved - 1.0) * 0.15
                          : curved;
                      final idx = _fromIndex + (_toIndex - _fromIndex) * damped;
                      return Positioned(
                        left: AfSpacing.s4 + segWidth * idx,
                        top: 4,
                        bottom: 4,
                        width: segWidth - 8,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: spectral,
                              borderRadius: AfRadii.borderPill,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: List.generate(count, (i) {
                      final pill = SongsPill.values[i];
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onChanged(pill),
                          child: Semantics(
                            button: true,
                            label: '${pill.label} tab',
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              child: Text(
                                pill.label,
                                style: AfTypography.bodyMedium.copyWith(
                                  color: pill == widget.selected
                                      ? AfColors.textOnPrimary
                                      : AfColors.textSecondary,
                                  fontWeight: pill == widget.selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
