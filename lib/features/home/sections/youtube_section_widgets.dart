import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/play_actions.dart';
import '../../../core/jellyfin/models/items.dart';
import '../../../core/youtube/innertube_client.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/track_context_menu.dart';
import '../../../widgets/track_row.dart';

/// Grid layout for YouTube song-only sections.
class YouTubeSongGrid extends ConsumerWidget {
  const YouTubeSongGrid({super.key, required this.items});
  final List<InnerTubeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const double rowHeight = 72.0;
    final rows = math.min(4, items.length);
    if (rows == 0) return const SizedBox.shrink();
    final double gridHeight =
        rowHeight * rows + (rows > 1 ? (rows - 1) * 8.0 : 0.0);

    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = ref.watch(playingStreamProvider).value ?? false;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );

    return SizedBox(
      height: gridHeight,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 16,
          crossAxisSpacing: 8,
          childAspectRatio: rowHeight / 310.0,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final track = AfTrack(
            id: item.id,
            title: item.title,
            artistName: item.subtitle,
            artistId: item.artistId,
            albumName: '',
            imageUrl: item.thumbnailUrl,
          );
          final isActive = item.id == currentTrack?.id;

          return FocusPressScale(
            key: ValueKey(item.id),
            ensureHitTarget: true,
            onTap: () => ref.read(playActionsProvider).playSingle(track),
            onLongPress: () => showTrackContextMenu(context, ref, track),
            child: Semantics(
              button: true,
              label: '${item.title} by ${item.subtitle}',
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: AfRadii.borderMd,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: item.thumbnailUrl.isNotEmpty
                                ? Artwork(
                                    url: item.thumbnailUrl,
                                    size: 56,
                                    radius: AfRadii.borderMd,
                                  )
                                : Container(
                                    color: AfColors.surfaceHigh,
                                    child: const Icon(
                                      LucideIcons.music,
                                      size: 24,
                                    ),
                                  ),
                          ),
                          if (isActive)
                            Positioned.fill(
                              child: Container(
                                color: AfColors.surfaceCanvas.withValues(
                                  alpha: 0.5,
                                ),
                                child: Center(
                                  child: isBuffering
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AfColors.textOnPrimary,
                                          ),
                                        )
                                      : PlayingEqualizer(
                                          color: AfColors.textOnPrimary,
                                          size: 16.0,
                                          isPlaying: isPlaying,
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AfSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AfTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w500,
                            color: isActive
                                ? activeAccent
                                : AfColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AfSpacing.s4),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AfTypography.bodySmall.copyWith(
                            color: AfColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      LucideIcons.moreVertical,
                      size: 18,
                      color: AfColors.textSecondary,
                    ),
                    tooltip: 'More options',
                    onPressed: () => showTrackContextMenu(context, ref, track),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal list of YouTube home tiles (albums, artists, playlists).
class YouTubeHomeTileList extends ConsumerWidget {
  const YouTubeHomeTileList({super.key, required this.items});
  final List<InnerTubeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 216,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AfSpacing.s12),
        itemBuilder: (context, index) {
          final item = items[index];
          return YouTubeHomeTile(
            item: item,
            onTap: () {
              switch (item.type) {
                case InnerTubeItemType.song:
                  final track = AfTrack(
                    id: item.id,
                    title: item.title,
                    artistName: item.subtitle,
                    artistId: item.artistId,
                    albumName: '',
                    imageUrl: item.thumbnailUrl,
                  );
                  ref.read(playActionsProvider).playSingle(track);
                  break;
                case InnerTubeItemType.album:
                  context.push('/album/${item.id}');
                  break;
                case InnerTubeItemType.artist:
                  context.push('/artist/${item.id}');
                  break;
                case InnerTubeItemType.playlist:
                  context.push('/playlist/${item.id}');
                  break;
              }
            },
            onLongPress: () {
              if (item.type == InnerTubeItemType.song) {
                final track = AfTrack(
                  id: item.id,
                  title: item.title,
                  artistName: item.subtitle,
                  artistId: item.artistId,
                  albumName: '',
                  imageUrl: item.thumbnailUrl,
                );
                showTrackContextMenu(context, ref, track);
              }
            },
          );
        },
      ),
    );
  }
}

/// Single tile in a YouTube home section.
class YouTubeHomeTile extends ConsumerWidget {
  const YouTubeHomeTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });
  final InnerTubeItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = ref.watch(playingStreamProvider).value ?? false;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );

    final isArtist = item.type == InnerTubeItemType.artist;
    final isSong = item.type == InnerTubeItemType.song;
    final isActive = isSong && item.id == currentTrack?.id;

    return FocusPressScale(
      ensureHitTarget: false,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Semantics(
        button: true,
        label: '${item.title} by ${item.subtitle}',
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: isArtist
                      ? AfRadii.borderPill
                      : AfRadii.borderMd,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: item.thumbnailUrl.isNotEmpty
                            ? Artwork(
                                url: item.thumbnailUrl,
                                size: 140,
                                radius: isArtist
                                    ? AfRadii.borderPill
                                    : AfRadii.borderMd,
                              )
                            : Container(
                                color: AfColors.surfaceHigh,
                                child: Icon(
                                  isArtist
                                      ? LucideIcons.user
                                      : LucideIcons.music,
                                  color: AfColors.textTertiary,
                                  size: 32,
                                ),
                              ),
                      ),
                      if (isActive)
                        Positioned.fill(
                          child: Container(
                            color: AfColors.surfaceCanvas.withValues(
                              alpha: 0.5,
                            ),
                            child: Center(
                              child: isBuffering
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AfColors.textOnPrimary,
                                      ),
                                    )
                                  : PlayingEqualizer(
                                      color: AfColors.textOnPrimary,
                                      size: 24.0,
                                      isPlaying: isPlaying,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AfSpacing.s8),
              Text(
                item.title,
                style: AfTypography.bodySmall.copyWith(
                  color: isActive ? activeAccent : AfColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AfSpacing.s2),
              if (item.subtitle.isNotEmpty)
                Text(
                  item.subtitle,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
