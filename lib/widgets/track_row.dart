import 'package:flutter/material.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import 'artwork.dart';
import 'favorite_heart_button.dart';
import 'press_scale.dart';
import 'quality_chip.dart';

/// Animated audio visualizer bars, bounciness based on player playing state.
class PlayingEqualizer extends StatefulWidget {
  const PlayingEqualizer({
    super.key,
    this.color,
    this.size = 16.0,
    this.isPlaying = true,
  });
  final Color? color;
  final double size;
  final bool isPlaying;

  @override
  State<PlayingEqualizer> createState() => _PlayingEqualizerState();
}

class _PlayingEqualizerState extends State<PlayingEqualizer>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    final durations = [600, 800, 700, 900];
    _controllers = List.generate(durations.length, (i) {
      final c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: durations[i]),
      );
      if (widget.isPlaying) {
        c.repeat(reverse: true);
      }
      return c;
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(
        begin: 0.15,
        end: 1.0,
      ).animate(CurvedAnimation(parent: controller, curve: AfCurves.easeInOut));
    }).toList();
  }

  @override
  void didUpdateWidget(covariant PlayingEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      for (final c in _controllers) {
        if (widget.isPlaying) {
          c.repeat(reverse: true);
        } else {
          c.stop();
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AfColors.accentPrimary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_animations.length, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (context, child) {
              final val = widget.isPlaying ? _animations[i].value : 0.15;
              return Container(
                width: widget.size / (_animations.length * 1.8),
                height: widget.size * val,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: AfRadii.borderXs, // 1→4dp, closest token
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

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
    this.isPlaying = false,
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
  final bool isPlaying;
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
    if (leadingNumber != null) {
      leading = SizedBox(
        width: artSize,
        height: artSize,
        child: Center(
          child: isActive
              ? (isBuffering
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : PlayingEqualizer(
                        color: accent,
                        size: 16.0,
                        isPlaying: isPlaying,
                      ))
              : Text(
                  '${leadingNumber!}.',
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
        ),
      );
    } else {
      leading = Stack(
        alignment: Alignment.center,
        children: [
          Artwork(url: track.imageUrl, size: artSize, radius: AfRadii.borderSm),
          if (isActive)
            Container(
              width: artSize,
              height: artSize,
              decoration: BoxDecoration(
                color: AfColors.surfaceCanvas.withValues(alpha: 0.5),
                borderRadius: AfRadii.borderSm,
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
        ],
      );
    }

    return FocusPressScale(
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
                : (isActive ? AfColors.surfaceBase : AfColors.transparent),
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
                ExcludeSemantics(child: FavoriteHeartButton(track: track)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
