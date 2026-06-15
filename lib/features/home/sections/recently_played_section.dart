import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/play_actions.dart';
import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/favorite_heart_button.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/stagger_reveal.dart';
import '../../../widgets/skeletons/home_skeleton.dart';
import '../../../widgets/track_context_menu.dart';
import '../../../widgets/track_row.dart';

/// Recently played tracks — compact rows with spectral accent on active track.
class RecentTracksSection extends ConsumerWidget {
  const RecentTracksSection({super.key, required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(currentSpectralProvider.select((s) => s.energy));
    final spectralPrimary = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final tracksAsync = isLocal
        ? ref.watch(localTracksProvider)
        : ref.watch(recentlyPlayedTracksProvider);
    final currentTrack = ref.watch(currentTrackProvider);
    final isBuffering = ref.watch(isBufferingProvider);

    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'Recently played',
            actionLabel: 'See more',
            onActionTap: () => context.go('/library'),
            spectralPrimary: spectralPrimary,
          ),
        ),
        const SizedBox(height: AfSpacing.s12),
        tracksAsync.when(
          data: (tracks) => StaggerReveal(
            children: [
              for (final t in tracks.take(5))
                CompactTrackRow(
                  track: t,
                  isActive: t.id == currentTrack?.id,
                  isBuffering: t.id == currentTrack?.id && isBuffering,
                  accent: accent,
                  onTap: () => ref.read(playActionsProvider).playSingle(t),
                  onLongPress: () => showTrackContextMenu(context, ref, t),
                ),
            ],
          ),
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

/// Compact track row — translucent background, spectral accent on active track.
class CompactTrackRow extends ConsumerWidget {
  const CompactTrackRow({
    super.key,
    required this.track,
    required this.isActive,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
    this.isBuffering = false,
  });
  final AfTrack track;
  final bool isActive;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isBuffering;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(playingStreamProvider).valueOrNull ?? false;

    return Semantics(
      button: true,
      label: '${track.title} by ${track.artistName}',
      hint: 'Double tap to play',
      child: FocusPressScale(
        ensureHitTarget: true,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s16,
            vertical: AfSpacing.s4,
          ),
          padding: const EdgeInsets.all(AfSpacing.s12),
          decoration: BoxDecoration(
            borderRadius: AfRadii.borderMd,
            color: AfColors.glassFillSubtle,
            border: Border.all(
              color: isActive
                  ? accent.withValues(alpha: 0.3)
                  : AfColors.glassBorder,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Artwork(
                    url: track.imageUrl,
                    size: 48,
                    radius: AfRadii.borderSm,
                  ),
                  if (isActive)
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: AfRadii.borderSm,
                      ),
                      child: Center(
                        child: isBuffering
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : PlayingEqualizer(
                                color: Colors.white,
                                size: 16.0,
                                isPlaying: isPlaying,
                              ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.bodyMedium.copyWith(
                        color: isActive ? accent : AfColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: AfSpacing.s4),
                    Text(
                      track.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              FavoriteHeartButton(track: track, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
