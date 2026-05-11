import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/track_row.dart';

/// Playlist detail screen.
///
/// Mirrors the structure of [AlbumScreen] without the 1:1 hero artwork
/// (Jellyfin playlists rarely have a single dominant cover) — instead a
/// compact indigo gradient header with the playlist name + track count
/// and an action row. Tapping any row plays that track within the
/// playlist's queue.
class PlaylistScreen extends ConsumerWidget {
  final String playlistId;
  const PlaylistScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(playlistDetailProvider(playlistId));
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          // The playlist screen is always reached via context.push() so a
          // pop() back to the previous tab is always safe.
          onPressed: () => context.pop(),
        ),
        title: Text('Playlist', style: AfTypography.titleSmall),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AfSpacing.s24),
            child: Text(
              'Could not load playlist: $e',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.semanticError,
              ),
            ),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Playlist not found'));
          }
          final pl = detail.playlist;
          final tracks = detail.tracks;
          return SafeArea(
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(),
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
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            borderRadius: AfRadii.borderMd,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AfColors.indigo700,
                                AfColors.indigo950,
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.playlist_play_rounded,
                            color: AfColors.indigo300,
                            size: 40,
                          ),
                        ),
                        const SizedBox(width: AfSpacing.s16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pl.name,
                                  style: AfTypography.titleLarge,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: AfSpacing.s4),
                              Text(
                                '${tracks.length} '
                                '${tracks.length == 1 ? "track" : "tracks"}',
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
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s16),
                    child: Row(
                      children: [
                        Expanded(
                          child: PressScale(
                            onTap: tracks.isEmpty
                                ? null
                                : () => ref
                                    .read(playActionsProvider)
                                    .playQueue(tracks),
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: AfColors.indigo600,
                                borderRadius: AfRadii.borderPill,
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.play_arrow_rounded,
                                      color: AfColors.textOnPrimary),
                                  const SizedBox(width: AfSpacing.s8),
                                  Text(
                                    'Play',
                                    style: AfTypography.bodyMedium.copyWith(
                                      color: AfColors.textOnPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AfSpacing.s12),
                        Expanded(
                          child: PressScale(
                            onTap: tracks.isEmpty
                                ? null
                                : () {
                                    // Shuffle = enable shuffle then play.
                                    final svc =
                                        ref.read(playerServiceProvider);
                                    svc.setAfShuffleMode(true);
                                    ref
                                        .read(playActionsProvider)
                                        .playQueue(tracks);
                                  },
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: AfColors.surfaceBase,
                                borderRadius: AfRadii.borderPill,
                                border: Border.all(
                                    color: AfColors.surfaceHigh, width: 1),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.shuffle_rounded,
                                      color: AfColors.textPrimary),
                                  const SizedBox(width: AfSpacing.s8),
                                  Text(
                                    'Shuffle',
                                    style: AfTypography.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                    child: SizedBox(height: AfSpacing.s16)),
                SliverList.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AfSpacing.s4),
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16),
                      child: TrackRow(
                        track: t,
                        onTap: () => ref
                            .read(playActionsProvider)
                            .playQueue(tracks, startIndex: i),
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: AfSpacing.bottomInsetWithMiniAndNav,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
