import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/play_actions.dart';
import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/track_context_menu.dart';
import '../../../widgets/track_row.dart';

/// Horizontal scroll of recently played-but-old tracks (lost memories).
class LostMemoriesSection extends ConsumerWidget {
  const LostMemoriesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectralPrimary = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
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
                spectralPrimary: spectralPrimary,
              ),
            ),
            const SizedBox(height: AfSpacing.s12),
            SizedBox(
              height: 172,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                itemCount: tracks.length,
                // itemExtent enables layout caching for large lists.
                // Includes the trailing separator gap (12px) per item.
                itemExtent: _LostMemoryTile._tileSize + AfSpacing.s12,
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return _LostMemoryTile(
                    track: t,
                    onTap: () => ref.read(playActionsProvider).playSingle(t),
                    onLongPress: () => showTrackContextMenu(context, ref, t),
                  );
                },
              ),
            ),
          ]),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SkeletonBlock(
            width: double.infinity,
            height: 180,
            borderRadius: AfRadii.borderMd,
          ),
        ),
      ),
      error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

/// Lost memory tile with vignette edges.
class _LostMemoryTile extends ConsumerWidget {
  const _LostMemoryTile({
    required this.track,
    required this.onTap,
    required this.onLongPress,
  });
  final AfTrack track;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const double _tileSize = 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrack = ref.watch(currentTrackProvider);
    final isActive = track.id == currentTrack?.id;
    final isPlaying = ref.watch(playingStreamProvider).value ?? false;
    final isBuffering = ref.watch(isBufferingProvider);
    final energyColor = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );

    return Semantics(
      button: true,
      label: '${track.title} by ${track.artistName}',
      hint: 'Double tap to play',
      child: FocusPressScale(
        ensureHitTarget: false,
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: _tileSize,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Album art with vignette edges
              ClipRRect(
                borderRadius: AfRadii.borderSm,
                child: SizedBox(
                  width: _tileSize,
                  height: _tileSize,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Artwork(
                        url: track.imageUrl,
                        size: 100,
                        radius: BorderRadius.zero,
                        fit: BoxFit.cover,
                      ),
                      // Vignette edges
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: AfRadii.borderSm,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                AfColors.surfaceCanvas.withValues(alpha: 0.6),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          color: Colors.black.withValues(alpha: 0.5),
                          child: Center(
                            child: isBuffering
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : PlayingEqualizer(
                                    color: Colors.white,
                                    size: 20.0,
                                    isPlaying: isPlaying,
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AfSpacing.s4),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AfTypography.bodySmall.copyWith(
                  color: isActive ? energyColor : AfColors.textPrimary,
                ),
              ),
              const SizedBox(height: AfSpacing.s2),
              Text(
                track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AfTypography.caption.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
