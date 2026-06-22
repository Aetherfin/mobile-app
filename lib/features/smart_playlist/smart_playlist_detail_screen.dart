import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/skeletons/track_row_skeleton.dart';
import '../../widgets/track_context_menu.dart';
import '../../utils/navigation.dart';
import '../../widgets/track_row.dart';

/// Shows the resolved tracks for a smart playlist — Dark Moody style.
class SmartPlaylistDetailScreen extends ConsumerWidget {
  const SmartPlaylistDetailScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(smartPlaylistTracksProvider(playlistId));
    final playlistAsync = ref.watch(smartPlaylistsProvider);
    final activeTrack = ref.watch(currentTrackProvider);
    final activeId = activeTrack?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );
    final playing = ref.watch(playingStreamProvider).value ?? false;
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final playlist = playlistAsync.maybeWhen(
      data: (list) => list.where((p) => p.id == playlistId).firstOrNull,
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: AfColors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () => context.safePop(),
        ),
        title: Text(
          playlist?.name ?? 'Smart Playlist',
          style: AfTypography.display,
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.pencil, size: 20),
            onPressed: () => context.push('/smart-playlist/$playlistId/edit'),
            tooltip: 'Edit rules',
          ),
        ],
      ),
      body: tracksAsync.when(
        data: (tracks) {
          if (tracks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: AfLayout.iconContainerMd,
                    height: AfLayout.iconContainerMd,
                    decoration: BoxDecoration(
                      color: AfColors.textTertiary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.music,
                      size: 36,
                      color: AfColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s16),
                  Text(
                    'No tracks match these rules',
                    style: AfTypography.titleSmall,
                  ),
                  const SizedBox(height: AfSpacing.s4),
                  Text(
                    'Try editing the rules to broaden the criteria',
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              // Header card with play controls
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16,
                    vertical: AfSpacing.s12,
                  ),
                  decoration: const BoxDecoration(
                    color: AfColors.surfaceBase,
                    borderRadius: AfRadii.borderLg,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: spectral.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.sparkles,
                          size: 18,
                          color: spectral,
                        ),
                      ),
                      const SizedBox(width: AfSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${tracks.length} tracks',
                              style: AfTypography.bodyMedium,
                            ),
                            if (playlist != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AfSpacing.s2,
                                ),
                                child: Text(
                                  playlist.ruleSummary,
                                  style: AfTypography.bodySmall.copyWith(
                                    color: AfColors.textTertiary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AfSpacing.s8),
                      IconButton(
                        onPressed: () async {
                          await ref.read(playActionsProvider).playQueue(tracks);
                          await ref
                              .read(playerServiceProvider)
                              .setAfShuffleMode(true);
                        },
                        icon: const Icon(LucideIcons.shuffle, size: 20),
                        color: AfColors.textSecondary,
                        tooltip: 'Shuffle',
                      ),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.read(playActionsProvider).playQueue(tracks),
                        icon: const Icon(LucideIcons.play, size: 18),
                        label: const Text('Play'),
                        style: FilledButton.styleFrom(
                          backgroundColor: spectral,
                          foregroundColor: AfColors.surfaceCanvas,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AfSpacing.s16,
                            vertical: AfSpacing.s8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Track list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16)
                      .add(
                        const EdgeInsets.only(
                          bottom: AfSpacing.bottomInsetWithMiniAndNav,
                        ),
                      ),
                  itemCount: tracks.length,
                  itemExtent: 68.0,
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return Column(
                      key: ValueKey(t.id),
                      children: [
                        TrackRow(
                          track: t,
                          isActive: t.id == activeId,
                          isPlaying: t.id == activeId && playing,
                          isBuffering: t.id == activeId && isBuffering,
                          activeAccent: activeAccent,
                          onTap: () => ref
                              .read(playActionsProvider)
                              .playQueue(tracks, startIndex: i),
                          onLongPress: () =>
                              showTrackContextMenu(context, ref, t),
                        ),
                        const SizedBox(height: AfSpacing.s4),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const SingleChildScrollView(
          padding: AfSpacing.pageHorizontal,
          child: Column(
            children: [
              SizedBox(height: AfSpacing.s16),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
            ],
          ),
        ),
        error: (e, _) => AsyncErrorView(
          label: 'Could not resolve smart playlist',
          error: e,
          onRetry: () =>
              ref.invalidate(smartPlaylistTracksProvider(playlistId)),
        ),
      ),
    );
  }
}
