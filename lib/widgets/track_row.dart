import 'package:flutter/material.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import 'artwork.dart';
import 'favorite_heart_button.dart';
import 'press_scale.dart';
import 'quality_chip.dart';

/// Track row density.
///
///   compact     — 44dp tall, used in the queue.
///   comfortable — 64dp tall, default for playlists/album/search.
///   generous    — 80dp tall, 56dp art. Home "Recently Played".
enum TrackRowDensity { compact, comfortable, generous }

/// Renders an [AfTrack] as a row.
///
///   `+----+ Title           [QUALITY] ♥`
///   `| 🎵 | Artist · Album · 3:42`
///   `+----+`
///
/// Active rows render a 2dp left bar in `spectral.energy` and tint the
/// background to `surface.base`.
class TrackRow extends StatelessWidget {
  final AfTrack track;
  final TrackRowDensity density;
  final bool isActive;
  final Color? activeAccent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final int? leadingNumber;
  final bool showQualityChip;
  final bool showHeart;

  const TrackRow({
    super.key,
    required this.track,
    this.density = TrackRowDensity.comfortable,
    this.isActive = false,
    this.activeAccent,
    this.onTap,
    this.onLongPress,
    this.leadingNumber,
    this.showQualityChip = true,
    this.showHeart = true,
  });

  @override
  Widget build(BuildContext context) {
    final (height, artSize) = switch (density) {
      TrackRowDensity.compact => (44.0, 36.0),
      TrackRowDensity.comfortable => (64.0, 44.0),
      TrackRowDensity.generous => (80.0, 56.0),
    };
    final accent = activeAccent ?? AfColors.indigo300;

    final titleStyle = AfTypography.bodyMedium.copyWith(
      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
      color: isActive ? accent : AfColors.textPrimary,
    );

    final subtitleStyle = AfTypography.bodySmall.copyWith(
      color: AfColors.textSecondary,
    );

    Widget leading;
    if (leadingNumber != null) {
      leading = SizedBox(
        width: artSize,
        height: artSize,
        child: Center(
          child: Text(
            '${leadingNumber!}.',
            style: AfTypography.caption.copyWith(color: AfColors.textTertiary),
          ),
        ),
      );
    } else {
      leading = Artwork(
        url: track.imageUrl,
        size: artSize,
        radius: BorderRadius.circular(AfRadii.sm),
      );
    }

    return PressScale(
      ensureHitTarget: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s4),
        decoration: BoxDecoration(
          color: isActive ? AfColors.surfaceBase : Colors.transparent,
          borderRadius: AfRadii.borderSm,
        ),
        child: Row(
          children: [
            if (isActive)
              Container(
                width: 2,
                height: artSize,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            const SizedBox(width: AfSpacing.s8),
            leading,
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (density != TrackRowDensity.compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        track.subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ),
                ],
              ),
            ),
            if (showQualityChip && track.quality != null) ...[
              const SizedBox(width: AfSpacing.s8),
              QualityChip(quality: track.quality!, compact: density == TrackRowDensity.compact),
            ],
            if (showHeart) ...[
              const SizedBox(width: AfSpacing.s4),
              // Self-contained heart that talks to the backend directly
              // and manages its own optimistic flip — see
              // FavoriteHeartButton for the rationale (`onHeartTap`
              // used to be a dead callback in every list screen).
              FavoriteHeartButton(track: track),
            ],
          ],
        ),
      ),
    );
  }
}
