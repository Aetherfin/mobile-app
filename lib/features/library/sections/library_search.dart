import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/audio/play_actions.dart';
import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/af_scrollbar.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/track_context_menu.dart';
import '../../../widgets/track_row.dart';
import 'genres_tab.dart';

/// Command Palette — full-screen overlay search.
class LibrarySearch extends ConsumerStatefulWidget {
  const LibrarySearch({super.key});

  @override
  ConsumerState<LibrarySearch> createState() => _LibrarySearchState();
}

class _LibrarySearchState extends ConsumerState<LibrarySearch> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AfColors.surfaceCanvas,
            // ponytail: top-only corner, no matching AfRadii token
            borderRadius: BorderRadius.vertical(top: AfRadii.rXl),
          ),
          child: Column(
            children: [
              // ── Handle + Close ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  0,
                ),
                child: Row(
                  children: [
                    // Handle bar
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AfColors.surfaceMax,
                            borderRadius: AfRadii.borderPill,
                          ),
                        ),
                      ),
                    ),
                    // Close button
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(
                        LucideIcons.x,
                        color: AfColors.textTertiary,
                        size: 20,
                      ),
                      onPressed: () {
                        if (context.canPop()) context.pop();
                      },
                    ),
                  ],
                ),
              ),

              // ── Search Input ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  AfSpacing.s12,
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: AfTypography.bodyLarge.copyWith(
                    color: AfColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Search library',
                    hintText: 'Search songs, artists, albums\u2026',
                    hintStyle: AfTypography.bodyLarge.copyWith(
                      color: AfColors.textTertiary,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: AfSpacing.s4),
                      child: Icon(
                        LucideIcons.search,
                        color: AfColors.textTertiary,
                        size: 20,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: AfSpacing.minHitTarget,
                      minHeight: AfSpacing.minHitTarget,
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(
                              LucideIcons.x,
                              color: AfColors.textTertiary,
                              size: 18,
                            ),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AfColors.surfaceBase,
                    border: const OutlineInputBorder(
                      borderRadius: AfRadii.borderPill,
                      borderSide: BorderSide(color: AfColors.surfaceHigh),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: AfRadii.borderPill,
                      borderSide: BorderSide(color: AfColors.surfaceHigh),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AfRadii.borderPill,
                      borderSide: BorderSide(color: spectral),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s16,
                      vertical: AfSpacing.s12,
                    ),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      setState(() => _query = v.trim().toLowerCase());
                    });
                  },
                ),
              ),

              // ── Results ──
              Expanded(
                child: _query.isEmpty
                    ? _RecentAndSuggestions(isLocal: isLocal)
                    : _LiveResults(query: _query, isLocal: isLocal),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Recent searches + suggestions when query is empty.
class _RecentAndSuggestions extends ConsumerWidget {
  const _RecentAndSuggestions({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(
      isLocal ? localAlbumsProvider : allAlbumsProvider,
    );
    final genresAsync = ref.watch(
      isLocal ? localGenresProvider : allGenresProvider,
    );

    return AfScrollbar(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          // Quick suggestions
          Text(
            'QUICK PICKS',
            style: AfTypography.label.copyWith(color: AfColors.textSecondary),
          ),
          const SizedBox(height: AfSpacing.s12),
          albumsAsync.when(
            data: (list) {
              final recent = list.take(6).toList();
              if (recent.isEmpty) return const SizedBox.shrink();
              return Column(
                children: recent.map((a) {
                  return FocusPressScale(
                    onTap: () {
                      if (context.canPop()) context.pop();
                      context.push('/album/${a.id}');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                      child: Row(
                        children: [
                          Artwork(
                            url: a.imageUrl,
                            size: 44,
                            radius: AfRadii.borderSm,
                          ),
                          const SizedBox(width: AfSpacing.s12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AfTypography.bodyMedium.copyWith(
                                    color: AfColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  a.artistName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AfTypography.bodySmall.copyWith(
                                    color: AfColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            LucideIcons.arrowUpLeft,
                            color: AfColors.textDisabled,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AfSpacing.s32),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),

          const SizedBox(height: AfSpacing.s24),

          // Genre chips
          Text(
            'GENRES',
            style: AfTypography.label.copyWith(color: AfColors.textSecondary),
          ),
          const SizedBox(height: AfSpacing.s12),
          genresAsync.when(
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: AfSpacing.s8,
                runSpacing: AfSpacing.s8,
                children: list.take(8).map((g) {
                  final tint = parseGenreTint(g.tint);
                  return FocusPressScale(
                    onTap: () {
                      if (context.canPop()) context.pop();
                      context.push('/genre/${g.name}');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s16,
                        vertical: AfSpacing.s8,
                      ),
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.25),
                        borderRadius: AfRadii.borderPill,
                      ),
                      child: Text(
                        g.name,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textOnPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Live search results across all sections.
class _LiveResults extends ConsumerWidget {
  const _LiveResults({required this.query, required this.isLocal});
  final String query;
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(currentTrackProvider)?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final accent = ref.watch(currentSpectralProvider.select((s) => s.energy));

    final albumsAsync = ref.watch(
      isLocal ? localAlbumsProvider : allAlbumsProvider,
    );
    final artistsAsync = ref.watch(
      isLocal ? localArtistsProvider : allArtistsProvider,
    );

    return AfScrollbar(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          // Albums
          albumsAsync.when(
            data: (list) {
              final filtered = list
                  .where(
                    (a) =>
                        a.name.toLowerCase().contains(query) ||
                        a.artistName.toLowerCase().contains(query),
                  )
                  .take(4)
                  .toList();
              if (filtered.isEmpty) return const SizedBox.shrink();
              return _ResultSection(
                title: 'Albums',
                child: Column(
                  children: filtered.map((a) {
                    return FocusPressScale(
                      onTap: () {
                        if (context.canPop()) context.pop();
                        context.push('/album/${a.id}');
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                        child: Row(
                          children: [
                            Artwork(
                              url: a.imageUrl,
                              size: 44,
                              radius: AfRadii.borderSm,
                            ),
                            const SizedBox(width: AfSpacing.s12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AfTypography.bodyMedium.copyWith(
                                      color: AfColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    a.artistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AfTypography.bodySmall.copyWith(
                                      color: AfColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Artists
          artistsAsync.when(
            data: (list) {
              final filtered = list
                  .where((a) => a.name.toLowerCase().contains(query))
                  .take(4)
                  .toList();
              if (filtered.isEmpty) return const SizedBox.shrink();
              return _ResultSection(
                title: 'Artists',
                child: Column(
                  children: filtered.map((a) {
                    return FocusPressScale(
                      onTap: () {
                        if (context.canPop()) context.pop();
                        context.push('/artist/${a.id}');
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                        child: Row(
                          children: [
                            Artwork(
                              url: a.imageUrl,
                              size: 44,
                              radius: AfRadii.borderPill,
                            ),
                            const SizedBox(width: AfSpacing.s12),
                            Expanded(
                              child: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AfTypography.bodyMedium.copyWith(
                                  color: AfColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Songs
          Builder(
            builder: (context) {
              if (isLocal) {
                final tracks = ref.watch(localTracksProvider);
                return tracks.when(
                  data: (list) {
                    final filtered = list
                        .where(
                          (t) =>
                              t.title.toLowerCase().contains(query) ||
                              t.artistName.toLowerCase().contains(query),
                        )
                        .take(10)
                        .toList();
                    if (filtered.isEmpty) return const SizedBox.shrink();
                    return _buildTrackResults(
                      filtered,
                      activeId,
                      isBuffering,
                      accent,
                      ref,
                      context,
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                );
              } else {
                final state = ref.watch(tracksPaginationProvider);
                final filtered = state.items
                    .where(
                      (t) =>
                          t.title.toLowerCase().contains(query) ||
                          t.artistName.toLowerCase().contains(query),
                    )
                    .take(10)
                    .toList();
                if (filtered.isEmpty) return const SizedBox.shrink();
                return _buildTrackResults(
                  filtered,
                  activeId,
                  isBuffering,
                  accent,
                  ref,
                  context,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  static Widget _buildTrackResults(
    List<AfTrack> filtered,
    String? activeId,
    bool isBuffering,
    Color accent,
    WidgetRef ref,
    BuildContext context,
  ) {
    return _ResultSection(
      title: 'Songs',
      child: Column(
        children: filtered.map((t) {
          return TrackRow(
            track: t,
            isActive: t.id == activeId,
            isBuffering: t.id == activeId && isBuffering,
            activeAccent: accent,
            onTap: () {
              if (context.canPop()) context.pop();
              ref.read(playActionsProvider).playSmartQueue(t, filtered);
            },
            onLongPress: () => showTrackContextMenu(context, ref, t),
          );
        }).toList(),
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AfTypography.label.copyWith(color: AfColors.textSecondary),
          ),
          const SizedBox(height: AfSpacing.s8),
          child,
        ],
      ),
    );
  }
}
