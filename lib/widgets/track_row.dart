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
/// Active rows render a 2dp left bar in `accentPrimary` and tint the
/// background to `surfaceBase`.
class TrackRow extends StatelessWidget {
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
    this.steelBackground = false,
    this.isBuffering = false,
  });

  final AfTrack track;
  final TrackRowDensity density;
  final bool isActive;
  final Color? activeAccent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final int? leadingNumber;
  final bool showQualityChip;
  final bool showHeart;
  final bool steelBackground;
  final bool isBuffering;

  @override
  Widget build(BuildContext context) {
    final (height, artSize) = switch (density) {
      TrackRowDensity.compact => (44.0, 36.0),
      TrackRowDensity.comfortable => (64.0, 44.0),
      TrackRowDensity.generous => (80.0, 56.0),
    };
    final accent = activeAccent ?? AfColors.accentPrimary;

    final titleStyle = AfTypography.bodyMedium.copyWith(
      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
      color: isActive ? accent : AfColors.textPrimary,
    );

    final subtitleStyle = AfTypography.bodySmall.copyWith(
      color: AfColors.textSecondary,
    );

    Widget leading;
    if (leadingNumber != null && !isActive) {
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
      leading = Stack(
        alignment: Alignment.center,
        children: [
          Artwork(url: track.imageUrl, size: artSize, radius: AfRadii.borderSm),
          if (isActive && isBuffering)
            Container(
              width: artSize,
              height: artSize,
              decoration: BoxDecoration(
                color: AfColors.surfaceCanvas.withValues(alpha: 0.5),
                borderRadius: AfRadii.borderSm,
              ),
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AfColors.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return PressScale(
      ensureHitTarget: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Semantics(
        button: true,
        label:
            '${track.title} by ${track.artistName}'
            '${isActive ? ", now playing" : ""}',
        hint: 'Double tap to play',
        child: Container(
          height: height + (steelBackground ? 8 : 0),
          padding: EdgeInsets.symmetric(
            horizontal: steelBackground ? AfSpacing.s12 : AfSpacing.s4,
          ),
          decoration: BoxDecoration(
            color: steelBackground
                ? (isActive
                      ? AfColors.surfaceHigh.withValues(alpha: 0.6)
                      : AfColors.surfaceHigh.withValues(alpha: 0.3))
                : (isActive ? AfColors.surfaceBase : Colors.transparent),
            borderRadius: steelBackground ? AfRadii.borderLg : AfRadii.borderSm,
            border: steelBackground
                ? Border.all(
                    color: isActive
                        ? accent.withValues(alpha: 0.6)
                        : AfColors.surfaceHigh.withValues(alpha: 0.5),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              if (isActive && !steelBackground)
                Container(
                  width: 2,
                  height: artSize,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: AfRadii.borderXs,
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
                        padding: const EdgeInsets.only(top: AfSpacing.s2),
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
                QualityChip(
                  quality: track.quality!,
                  compact: density == TrackRowDensity.compact,
                ),
              ],
              if (showHeart) ...[
                const SizedBox(width: AfSpacing.s4),
                FavoriteHeartButton(track: track),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
