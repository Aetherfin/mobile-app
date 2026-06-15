import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
///
/// Supports horizontal swipe-to-skip (left → previous, right → next)
/// with logarithmic drag sensitivity and animated snap-back.
/// Uses a single pan recognizer with direction detection to avoid
/// gesture arena conflicts between vertical and horizontal drags.
class _MiniPlayerContent extends ConsumerStatefulWidget {
  const _MiniPlayerContent({required this.track});
  final AfTrack track;

  @override
  ConsumerState<_MiniPlayerContent> createState() => _MiniPlayerContentState();
}

class _MiniPlayerContentState extends ConsumerState<_MiniPlayerContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snapCtrl;
  double _dragOffset = 0;
  double _dragOffsetY = 0;
  double _snapFrom = 0;
  double _snapFromY = 0;

  static const double _skipThreshold = 80;
  static const double _dismissThreshold = 80;

  /// Logarithmic sensitivity: saturates for large drags, dampens small ones.
  static double _logSensitivity(double dx) => dx / (1 + math.exp(-0.05 * dx));

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(vsync: this, duration: AfDurations.quick)
      ..addListener(_onSnapTick);
  }

  @override
  void dispose() {
    _snapCtrl
      ..removeListener(_onSnapTick)
      ..dispose();
    super.dispose();
  }

  void _onSnapTick() {
    setState(() {
      _dragOffset = _snapFrom * (1 - _snapCtrl.value);
      _dragOffsetY = _snapFromY * (1 - _snapCtrl.value);
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_snapCtrl.isAnimating) return;
    setState(() {
      _dragOffset += details.delta.dx;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final effective = _logSensitivity(_dragOffset);
    if (effective.abs() > _skipThreshold) {
      HapticFeedback.lightImpact();
      final svc = ref.read(playerServiceProvider);
      if (effective > 0) {
        svc.skipToNext();
      } else {
        svc.skipToPrevious();
      }
    }
    _snapFrom = _dragOffset;
    _snapCtrl.forward(from: 0);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_snapCtrl.isAnimating) return;
    setState(() {
      _dragOffsetY += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffsetY.abs() > _dismissThreshold) {
      ref.read(playerServiceProvider).stopAndClear();
    } else {
      _snapFromY = _dragOffsetY;
      _snapCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final isBuffering = ref.watch(isBufferingProvider);
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, shadow: s.shadow),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {},
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: PressScale(
        onTap: () => context.push('/now-playing'),
        child: Transform.translate(
          offset: Offset(_dragOffset, _dragOffsetY),
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
                  _ArtworkRing(track: widget.track, accent: spectral.primary),
                  const SizedBox(width: AfSpacing.s8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AfSpacing.s2),
                        Text(
                          widget.track.artistName,
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
              radius: BorderRadius.circular(AfSpacing.s24),
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
