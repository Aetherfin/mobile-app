import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/audio/play_actions.dart';
import '../../../core/backend/music_backend.dart';
import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/lastfm_stats_providers.dart';
import '../../../state/providers.dart';
import '../../../utils/display_error.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/af_dialog.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/section_header.dart';
import 'lastfm_section.dart';

/// Complete "Listening Stats" section: header + optional CTA + dashboard.
class ListeningStatsSection extends StatelessWidget {
  const ListeningStatsSection({super.key, required this.isLastFmConnected});

  final bool isLastFmConnected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AfSpacing.s16,
            AfSpacing.s24,
            AfSpacing.s16,
            0,
          ),
          child: SectionHeader(title: 'Listening Stats', uppercase: true),
        ),
        if (!isLastFmConnected)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: LastFmConnectionCTA(),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: StatsDashboard(isLastFmConnected: isLastFmConnected),
        ),
      ],
    );
  }
}

/// Dashboard with period selector, tab selector, and top lists.
/// Uses Variant E glass morphism style with spectral accents.
class StatsDashboard extends ConsumerWidget {
  const StatsDashboard({super.key, required this.isLastFmConnected});

  final bool isLastFmConnected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePeriod = ref.watch(statsPeriodProvider);
    final activeTab = ref.watch(statsTabProvider);
    final spectral = ref.watch(currentSpectralProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tabs + Period filter — single row
        Row(
          children: [
            // Tab slider takes most space
            Expanded(child: _StatsPillBar(selected: activeTab)),
            // Period chips on the right as compact filter buttons
            if (isLastFmConnected) ...[
              const SizedBox(width: AfSpacing.s8),
              _PeriodChip(
                label: '7D',
                value: '7day',
                activeValue: activePeriod,
              ),
              const SizedBox(width: AfSpacing.s4),
              _PeriodChip(
                label: '30D',
                value: '1month',
                activeValue: activePeriod,
              ),
              const SizedBox(width: AfSpacing.s4),
              _PeriodChip(
                label: 'All',
                value: 'overall',
                activeValue: activePeriod,
              ),
            ],
          ],
        ),
        const SizedBox(height: AfSpacing.s16),

        // List render
        _renderActiveList(context, ref, activeTab, spectral.primary),
      ],
    );
  }

  Widget _renderActiveList(
    BuildContext context,
    WidgetRef ref,
    String activeTab,
    Color spectralPrimary,
  ) {
    switch (activeTab) {
      case 'songs':
        final songsAsync = ref.watch(topTracksProvider);
        return songsAsync.when(
          loading: () => _loadingIndicator(spectralPrimary),
          error: (err, _) => _errorText(err),
          data: (tracks) => _GlassTopSongsList(tracks: tracks),
        );
      case 'artists':
        final artistsAsync = ref.watch(topArtistsProvider);
        return artistsAsync.when(
          loading: () => _loadingIndicator(spectralPrimary),
          error: (err, _) => _errorText(err),
          data: (artists) => _GlassTopArtistsList(artists: artists),
        );
      case 'albums':
        final albumsAsync = ref.watch(topAlbumsProvider);
        return albumsAsync.when(
          loading: () => _loadingIndicator(spectralPrimary),
          error: (err, _) => _errorText(err),
          data: (albums) => _GlassTopAlbumsList(albums: albums),
        );
      default:
        return const SizedBox();
    }
  }

  Widget _loadingIndicator(Color spectralPrimary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AfSpacing.s32),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: spectralPrimary,
          ),
        ),
      ),
    );
  }

  Widget _errorText(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AfSpacing.s16),
        child: Text(
          'Failed to load statistics: $error',
          style: AfTypography.bodySmall.copyWith(color: AfColors.semanticError),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Glass Morphism Widgets (Variant E style) ──────────────────────────────

/// Compact period filter chip for inline use next to the tab bar.
class _PeriodChip extends ConsumerWidget {
  const _PeriodChip({
    required this.label,
    required this.value,
    required this.activeValue,
  });

  final String label;
  final String value;
  final String activeValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value == activeValue;
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return PressScale(
      onTap: () => ref.read(statsPeriodProvider.notifier).set(value),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s8,
          vertical: AfSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: active ? spectral : AfColors.glassFill,
          borderRadius: AfRadii.borderPill,
          border: Border.all(
            color: active ? spectral : AfColors.glassBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AfTypography.caption.copyWith(
            color: active ? AfColors.textOnPrimary : AfColors.textTertiary,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Pill bar with animated sliding indicator for stats tabs.
class _StatsPillBar extends ConsumerStatefulWidget {
  const _StatsPillBar({required this.selected});
  final String selected;

  @override
  ConsumerState<_StatsPillBar> createState() => _StatsPillBarState();
}

class _StatsPillBarState extends ConsumerState<_StatsPillBar>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['songs', 'artists', 'albums'];
  static const _labels = ['Songs', 'Artists', 'Albums'];

  late final AnimationController _ctrl;
  int _fromIndex = 0;
  int _toIndex = 0;

  @override
  void initState() {
    super.initState();
    _toIndex = _tabs.indexOf(widget.selected);
    _fromIndex = _toIndex;
    _ctrl = AnimationController(vsync: this, duration: AfDurations.long)
      ..value = 1.0;
  }

  @override
  void didUpdateWidget(_StatsPillBar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      _fromIndex = _toIndex;
      _toIndex = _tabs.indexOf(widget.selected);
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
    final count = _tabs.length;

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
                      final curved = AfCurves.easeOutBack.transform(
                        _ctrl.value,
                      );
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
                      final isActive = _tabs[i] == widget.selected;
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              ref.read(statsTabProvider.notifier).set(_tabs[i]),
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            child: Text(
                              _labels[i],
                              style: AfTypography.bodyMedium.copyWith(
                                color: isActive
                                    ? AfColors.textOnPrimary
                                    : AfColors.textSecondary,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
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

/// Glass top songs list with spectral accents.
class _GlassTopSongsList extends ConsumerWidget {
  const _GlassTopSongsList({required this.tracks});

  final List<({String artist, String title, int playCount, String? imageUrl})>
  tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    if (tracks.isEmpty) {
      return _emptyState(
        'No history logged yet. Listen to tracks to collect metrics.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AfSpacing.s8),
      itemBuilder: (context, i) {
        final t = tracks[i];
        return Container(
          padding: const EdgeInsets.all(AfSpacing.s12),
          decoration: BoxDecoration(
            color: AfColors.glassFill,
            borderRadius: AfRadii.borderMd,
            border: Border.all(color: AfColors.glassBorder, width: 1),
          ),
          child: Row(
            children: [
              // Rank + Artwork
              SizedBox(
                width: 48,
                child: Row(
                  children: [
                    Text(
                      '${i + 1}',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    t.imageUrl != null
                        ? Artwork(
                            url: t.imageUrl,
                            size: 32,
                            radius: AfRadii.borderSm,
                          )
                        : Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: spectral.withValues(alpha: 0.15),
                              borderRadius: AfRadii.borderSm,
                            ),
                            child: const Icon(
                              LucideIcons.music,
                              size: 16,
                              color: AfColors.textTertiary,
                            ),
                          ),
                  ],
                ),
              ),
              const SizedBox(width: AfSpacing.s12),

              // Title + Artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      t.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.caption.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),

              // Play count
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s8,
                  vertical: AfSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: spectral.withValues(alpha: 0.15),
                  borderRadius: AfRadii.borderPill,
                ),
                child: Text(
                  '${t.playCount}',
                  style: AfTypography.caption.copyWith(
                    color: spectral,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Glass top artists list with spectral accents.
class _GlassTopArtistsList extends ConsumerWidget {
  const _GlassTopArtistsList({required this.artists});

  final List<({String artist, int playCount})> artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    if (artists.isEmpty) {
      return _emptyState('No history logged yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: artists.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AfSpacing.s8),
      itemBuilder: (context, i) {
        final a = artists[i];
        return Container(
          padding: const EdgeInsets.all(AfSpacing.s12),
          decoration: BoxDecoration(
            color: AfColors.glassFill,
            borderRadius: AfRadii.borderMd,
            border: Border.all(color: AfColors.glassBorder, width: 1),
          ),
          child: Row(
            children: [
              // Rank + Icon
              SizedBox(
                width: 40,
                child: Row(
                  children: [
                    Text(
                      '${i + 1}',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: spectral.withValues(alpha: 0.15),
                        borderRadius: AfRadii.borderSm,
                      ),
                      child: const Icon(
                        LucideIcons.user,
                        size: 16,
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AfSpacing.s12),

              // Artist name
              Expanded(
                child: Text(
                  a.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AfTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Play count
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s8,
                  vertical: AfSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: spectral.withValues(alpha: 0.15),
                  borderRadius: AfRadii.borderPill,
                ),
                child: Text(
                  '${a.playCount}',
                  style: AfTypography.caption.copyWith(
                    color: spectral,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Glass top albums list with spectral accents.
class _GlassTopAlbumsList extends ConsumerWidget {
  const _GlassTopAlbumsList({required this.albums});

  final List<({String artist, String album, int playCount, String? imageUrl})>
  albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    if (albums.isEmpty) {
      return _emptyState('No history logged yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: albums.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AfSpacing.s8),
      itemBuilder: (context, i) {
        final alb = albums[i];
        return Container(
          padding: const EdgeInsets.all(AfSpacing.s12),
          decoration: BoxDecoration(
            color: AfColors.glassFill,
            borderRadius: AfRadii.borderMd,
            border: Border.all(color: AfColors.glassBorder, width: 1),
          ),
          child: Row(
            children: [
              // Rank + Artwork
              SizedBox(
                width: 48,
                child: Row(
                  children: [
                    Text(
                      '${i + 1}',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    alb.imageUrl != null
                        ? Artwork(
                            url: alb.imageUrl,
                            size: 32,
                            radius: AfRadii.borderSm,
                          )
                        : Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: spectral.withValues(alpha: 0.15),
                              borderRadius: AfRadii.borderSm,
                            ),
                            child: const Icon(
                              LucideIcons.disc,
                              size: 16,
                              color: AfColors.textTertiary,
                            ),
                          ),
                  ],
                ),
              ),
              const SizedBox(width: AfSpacing.s12),

              // Album + Artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alb.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      alb.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.caption.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),

              // Play count
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s8,
                  vertical: AfSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: spectral.withValues(alpha: 0.15),
                  borderRadius: AfRadii.borderPill,
                ),
                child: Text(
                  '${alb.playCount}',
                  style: AfTypography.caption.copyWith(
                    color: spectral,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Empty state placeholder for unpopulated lists.
Widget _emptyState(String text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AfSpacing.s24,
        horizontal: AfSpacing.s16,
      ),
      child: Text(
        text,
        style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// Period selector button (7 Days, 30 Days, All Time).
class PeriodButton extends ConsumerWidget {
  const PeriodButton({
    super.key,
    required this.label,
    required this.value,
    required this.activeValue,
  });

  final String label;
  final String value;
  final String activeValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value == activeValue;
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.secondary),
    );
    return PressScale(
      onTap: () => ref.read(statsPeriodProvider.notifier).set(value),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s12,
          vertical: AfSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: active ? spectral : AfColors.surfaceBase,
          borderRadius: AfRadii.borderSm,
        ),
        child: Text(
          label,
          style: AfTypography.bodySmall.copyWith(
            color: active ? AfColors.textOnPrimary : AfColors.textSecondary,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Tab selector button (Songs, Artists, Albums).
class TabButton extends ConsumerWidget {
  const TabButton({
    super.key,
    required this.label,
    required this.value,
    required this.activeValue,
  });

  final String label;
  final String value;
  final String activeValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value == activeValue;
    return Expanded(
      child: PressScale(
        onTap: () => ref.read(statsTabProvider.notifier).set(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AfSpacing.s8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AfColors.surfaceHigh : Colors.transparent,
            borderRadius: AfRadii.borderMd,
          ),
          child: Text(
            label,
            style: AfTypography.bodySmall.copyWith(
              color: active ? AfColors.textPrimary : AfColors.textTertiary,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// List of top tracks from Last.fm stats.
class TopSongsList extends ConsumerWidget {
  const TopSongsList({super.key, required this.tracks});

  final List<({String artist, String title, int playCount, String? imageUrl})>
  tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    if (tracks.isEmpty) {
      return emptyStateWidget(
        'No history logged yet. Listen to tracks to collect metrics.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AfSpacing.s8),
      itemBuilder: (context, i) {
        final t = tracks[i];
        return ListTile(
          dense: true,
          tileColor: AfColors.surfaceBase,
          shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderSm),
          leading: SizedBox(
            width: 48,
            child: Row(
              children: [
                Text(
                  '${i + 1}',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                const Spacer(),
                t.imageUrl != null
                    ? Artwork(
                        url: t.imageUrl,
                        size: 28,
                        radius: AfRadii.borderSm,
                      )
                    : Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: AfColors.surfaceHigh,
                          borderRadius: AfRadii.borderSm,
                        ),
                        child: const Icon(
                          LucideIcons.music,
                          size: 14,
                          color: AfColors.textTertiary,
                        ),
                      ),
              ],
            ),
          ),
          title: Text(
            t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            t.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.caption.copyWith(color: AfColors.textTertiary),
          ),
          trailing: Text(
            '${t.playCount} plays',
            style: AfTypography.caption.copyWith(color: spectral),
          ),
          onTap: () => playTrackFromStats(context, ref, t.artist, t.title),
        );
      },
    );
  }
}

/// List of top artists from Last.fm stats.
class TopArtistsList extends ConsumerWidget {
  const TopArtistsList({super.key, required this.artists});

  final List<({String artist, int playCount})> artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    if (artists.isEmpty) {
      return emptyStateWidget('No history logged yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: artists.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AfSpacing.s8),
      itemBuilder: (context, i) {
        final a = artists[i];
        return ListTile(
          dense: true,
          tileColor: AfColors.surfaceBase,
          shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderSm),
          leading: SizedBox(
            width: 32,
            child: Row(
              children: [
                Text(
                  '${i + 1}',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                const Spacer(),
                const Icon(
                  LucideIcons.user,
                  size: 16,
                  color: AfColors.textTertiary,
                ),
              ],
            ),
          ),
          title: Text(
            a.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
          ),
          trailing: Text(
            '${a.playCount} plays',
            style: AfTypography.caption.copyWith(color: spectral),
          ),
          onTap: () => navigateToArtistFromStats(context, ref, a.artist),
        );
      },
    );
  }
}

/// List of top albums from Last.fm stats.
class TopAlbumsList extends ConsumerWidget {
  const TopAlbumsList({super.key, required this.albums});

  final List<({String artist, String album, int playCount, String? imageUrl})>
  albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    if (albums.isEmpty) {
      return emptyStateWidget('No history logged yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: albums.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AfSpacing.s8),
      itemBuilder: (context, i) {
        final alb = albums[i];
        return ListTile(
          dense: true,
          tileColor: AfColors.surfaceBase,
          shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderSm),
          leading: SizedBox(
            width: 48,
            child: Row(
              children: [
                Text(
                  '${i + 1}',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                const Spacer(),
                alb.imageUrl != null
                    ? Artwork(
                        url: alb.imageUrl,
                        size: 28,
                        radius: AfRadii.borderSm,
                      )
                    : Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: AfColors.surfaceHigh,
                          borderRadius: AfRadii.borderSm,
                        ),
                        child: const Icon(
                          LucideIcons.disc,
                          size: 14,
                          color: AfColors.textTertiary,
                        ),
                      ),
              ],
            ),
          ),
          title: Text(
            alb.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            alb.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.caption.copyWith(color: AfColors.textTertiary),
          ),
          trailing: Text(
            '${alb.playCount} plays',
            style: AfTypography.caption.copyWith(color: spectral),
          ),
          onTap: () =>
              navigateToAlbumFromStats(context, ref, alb.artist, alb.album),
        );
      },
    );
  }
}

/// Empty state placeholder for unpopulated lists.
Widget emptyStateWidget(String text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AfSpacing.s24,
        horizontal: AfSpacing.s16,
      ),
      child: Text(
        text,
        style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

// ── Search/Resolution Helpers ────────────────────────────────────────────────

Future<void> playTrackFromStats(
  BuildContext context,
  WidgetRef ref,
  String artist,
  String title,
) async {
  final spectral = ref.read(currentSpectralProvider);
  void Function()? dismiss;
  // ignore: unawaited_futures – overlay inserted synchronously, dismiss via callback
  showBlurDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx, dismissFn) {
      dismiss = dismissFn;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spectral.primary,
            ),
          ),
          const SizedBox(width: AfSpacing.s16),
          Text(
            'Locating track in library...',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          ),
        ],
      );
    },
  );
  // Ensure the overlay is laid out before async work begins.
  await Future<void>.delayed(Duration.zero);

  try {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) throw Exception('No connected library.');

    AfTrack? resolved;
    if (backend.serverType == ServerType.local) {
      final db = ref.read(localLibraryProvider).db;
      resolved = await db.searchTrackByArtistAndTitle(artist, title);
    } else {
      final results = await backend.search('$artist $title');
      for (final t in results.tracks) {
        if (t.title.toLowerCase() == title.toLowerCase() &&
            t.artistName.toLowerCase() == artist.toLowerCase()) {
          resolved = t;
          break;
        }
      }
      if (resolved == null) {
        for (final t in results.tracks) {
          if (t.title.toLowerCase().contains(title.toLowerCase()) &&
              t.artistName.toLowerCase().contains(artist.toLowerCase())) {
            resolved = t;
            break;
          }
        }
      }
    }

    dismiss?.call();

    if (resolved != null) {
      await ref.read(playActionsProvider).playQueue([resolved], startIndex: 0);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$title" by $artist is not in your library.'),
          ),
        );
      }
    }
  } on Exception catch (e) {
    dismiss?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve track: ${displayError(e)}')),
      );
    }
  }
}

Future<void> navigateToArtistFromStats(
  BuildContext context,
  WidgetRef ref,
  String artistName,
) async {
  final spectral = ref.read(currentSpectralProvider);
  void Function()? dismiss;
  // ignore: unawaited_futures – overlay inserted synchronously, dismiss via callback
  showBlurDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx, dismissFn) {
      dismiss = dismissFn;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spectral.primary,
            ),
          ),
          const SizedBox(width: AfSpacing.s16),
          Text(
            'Locating artist...',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          ),
        ],
      );
    },
  );
  await Future<void>.delayed(Duration.zero);

  try {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) throw Exception('No connected library.');

    String? artistId;
    if (backend.serverType == ServerType.local) {
      final db = ref.read(localLibraryProvider).db;
      final resolved = await db.artistByName(artistName);
      artistId = resolved?.id;
    } else {
      final results = await backend.search(artistName);
      for (final art in results.artists) {
        if (art.name.toLowerCase() == artistName.toLowerCase()) {
          artistId = art.id;
          break;
        }
      }
    }

    dismiss?.call();

    if (artistId != null) {
      if (context.mounted) unawaited(context.push('/artist/$artistId'));
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Artist "$artistName" not found in library.')),
        );
      }
    }
  } on Exception catch (e) {
    dismiss?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve artist: ${displayError(e)}')),
      );
    }
  }
}

Future<void> navigateToAlbumFromStats(
  BuildContext context,
  WidgetRef ref,
  String artistName,
  String albumName,
) async {
  final spectral = ref.read(currentSpectralProvider);
  void Function()? dismiss;
  // ignore: unawaited_futures – overlay inserted synchronously, dismiss via callback
  showBlurDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx, dismissFn) {
      dismiss = dismissFn;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spectral.primary,
            ),
          ),
          const SizedBox(width: AfSpacing.s16),
          Text(
            'Locating album...',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          ),
        ],
      );
    },
  );
  await Future<void>.delayed(Duration.zero);

  try {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) throw Exception('No connected library.');

    String? albumId;
    if (backend.serverType == ServerType.local) {
      final db = ref.read(localLibraryProvider).db;
      final resolved = await db.albumByKey(albumName, artistName);
      albumId = resolved?.id;
    } else {
      final results = await backend.search('$artistName $albumName');
      for (final alb in results.albums) {
        if (alb.name.toLowerCase() == albumName.toLowerCase() &&
            alb.artistName.toLowerCase() == artistName.toLowerCase()) {
          albumId = alb.id;
          break;
        }
      }
    }

    dismiss?.call();

    if (albumId != null) {
      if (context.mounted) unawaited(context.push('/album/$albumId'));
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Album "$albumName" by $artistName not found in library.',
            ),
          ),
        );
      }
    }
  } on Exception catch (e) {
    dismiss?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve album: ${displayError(e)}')),
      );
    }
  }
}
