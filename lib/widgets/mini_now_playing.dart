import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'artwork.dart';
import 'press_scale.dart';

/// Compact mini player bar — floats above bottom nav.
///
/// Solid spectral-tinted pill. Slides up to expand, slides down to collapse.
/// Artwork is static; only the progress ring ticks on position updates.
class MiniNowPlaying extends ConsumerWidget {
  const MiniNowPlaying({super.key, required this.isVisible});

  /// Controls expand (true) / collapse (false) animation.
  final bool isVisible;

  static const double height = AfSpacing.bottomNavHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);

    return AnimatedSlide(
      offset: isVisible ? Offset.zero : const Offset(0, 1.2),
      duration: AfDurations.standard,
      curve: AfCurves.easeEmphasized,
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: AfDurations.quick,
        child: track == null
            ? const SizedBox(height: height)
            : _MiniPlayerContent(track: track),
      ),
    );
  }
}

/// The actual mini player content — only builds when track is non-null.
class _MiniPlayerContent extends ConsumerWidget {
  const _MiniPlayerContent({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final isBuffering = ref.watch(isBufferingProvider);
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, shadow: s.shadow),
      ),
    );

    return PressScale(
      onTap: () => context.push('/now-playing'),
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -200) {
            context.push('/now-playing');
          } else if (v > 200) {
            ref.read(playerServiceProvider).stopAndClear();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s8),
          child: Container(
            height: MiniNowPlaying.height,
            decoration: BoxDecoration(
              color: spectral.shadow,
              borderRadius: AfRadii.borderXl,
              border: Border.all(
                color: spectral.primary.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: AfSpacing.s4),
                _ArtworkRing(track: track, accent: spectral.primary),
                const SizedBox(width: AfSpacing.s8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AfSpacing.s2),
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
                _MiniTransport(
                  isPlaying: isPlaying,
                  isBuffering: isBuffering,
                  accent: spectral.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Artwork wrapped in a circular progress ring.
///
/// Artwork is a static child — does NOT watch positionStreamProvider.
/// Only the [_ProgressRing] in a [RepaintBoundary] ticks.
class _ArtworkRing extends StatelessWidget {
  const _ArtworkRing({required this.track, required this.accent});
  final AfTrack track;
  final Color accent;

  static const double _artworkSize = 48;
  static const double _ringStroke = 2.5;
  static const double _totalSize = _artworkSize + _ringStroke * 2 + 2;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _totalSize,
      height: _totalSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(_ringStroke + 1),
            child: Artwork(
              url: track.imageUrl,
              size: _artworkSize,
              radius: BorderRadius.circular(
                AfSpacing.s24,
              ), // 24dp — no exact AfRadii match
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(child: _ProgressRing(accent: accent)),
          ),
        ],
      ),
    );
  }
}

/// Minimal progress ring — only widget that watches position ticks.
class _ProgressRing extends ConsumerWidget {
  const _ProgressRing({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionStreamProvider);
    final duration = ref.watch(durationStreamProvider);
    final progress = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return ExcludeSemantics(
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.toDouble(),
          backgroundColor: AfColors.surfaceHigh,
          activeColor: accent,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.backgroundColor,
    required this.activeColor,
  });

  static const double _strokeWidth = 2.5;

  final double progress;
  final Color backgroundColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    if (progress > 0) {
      final activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// Mini transport controls — prev / play-pause / next.
class _MiniTransport extends ConsumerWidget {
  const _MiniTransport({
    required this.isPlaying,
    required this.isBuffering,
    required this.accent,
  });
  final bool isPlaying;
  final bool isBuffering;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Previous track',
          button: true,
          child: PressScale(
            ensureHitTarget: false,
            onTap: () => ref.read(playerServiceProvider).skipToPrevious(),
            child: const SizedBox(
              width: AfSpacing.minHitTarget,
              height: AfSpacing.minHitTarget,
              child: Center(
                child: Icon(
                  LucideIcons.skipBack,
                  size: AfIconSizes.sm,
                  color: AfColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
        Semantics(
          label: isPlaying ? 'Pause' : 'Play',
          button: true,
          child: PressScale(
            ensureHitTarget: false,
            onTap: () {
              final svc = ref.read(playerServiceProvider);
              isPlaying ? svc.pause() : svc.play();
            },
            child: SizedBox(
              width: AfSpacing.minHitTarget,
              height: AfSpacing.minHitTarget,
              child: Center(
                child: isBuffering
                    ? const SizedBox(
                        width: AfSpacing.s20,
                        height: AfSpacing.s20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AfColors.textSecondary,
                        ),
                      )
                    : Icon(
                        isPlaying ? LucideIcons.pause : LucideIcons.play,
                        size: AfIconSizes.sm,
                        color: AfColors.textPrimary,
                      ),
              ),
            ),
          ),
        ),
        Semantics(
          label: 'Next track',
          button: true,
          child: PressScale(
            ensureHitTarget: false,
            onTap: () => ref.read(playerServiceProvider).skipToNext(),
            child: const SizedBox(
              width: AfSpacing.minHitTarget,
              height: AfSpacing.minHitTarget,
              child: Center(
                child: Icon(
                  LucideIcons.skipForward,
                  size: AfIconSizes.sm,
                  color: AfColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
