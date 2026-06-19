import 'dart:async' show StreamSubscription;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/log.dart';
import '../../utils/time_format.dart';
import '../../widgets/audio_visual_scrubber.dart';

/// Reactive progress bar with audio visualizer scrubber.
///
/// Watches [positionStreamProvider] — the only widget that does.
/// Rebuilds at position tick rate; everything above is unaffected.
///
/// Scrub architecture:
///   onScrub    → local preview only (no seek, no audio pipeline churn)
///   onScrubEnd → single committed seek
class ReactiveProgress extends ConsumerStatefulWidget {
  const ReactiveProgress({super.key, required this.track});
  final AfTrack track;

  @override
  ConsumerState<ReactiveProgress> createState() => _ReactiveProgressState();
}

class _ReactiveProgressState extends ConsumerState<ReactiveProgress> {
  double? _scrubPreview;
  bool _isDragging = false;
  double _bufferedPercent = 0.0;
  Duration _prefetchDuration = Duration.zero;
  StreamSubscription<double>? _bufferSub;
  StreamSubscription<Duration>? _prefetchSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final svc = ref.read(playerServiceProvider);
      _bufferSub = svc.bufferingPercentageStream.listen((pct) {
        if (mounted) setState(() => _bufferedPercent = pct.clamp(0.0, 100.0));
      });
      _prefetchSub = svc.prefetchCacheDurationStream.listen((dur) {
        if (mounted) setState(() => _prefetchDuration = dur);
      });
    });
  }

  @override
  void dispose() {
    _bufferSub?.cancel();
    _prefetchSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReactiveProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _isDragging = false;
      _scrubPreview = null;
      _bufferedPercent = 0.0;
      _prefetchDuration = Duration.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionStreamProvider);
    final energy = ref.watch(currentSpectralProvider.select((s) => s.energy));
    final mpvDuration = ref.watch(durationStreamProvider);
    final loadedTrackId = ref.watch(mpvLoadedTrackIdProvider);
    final isTransitioning = widget.track.id != loadedTrackId;
    final duration = mpvDuration > Duration.zero
        ? mpvDuration
        : widget.track.duration;

    final effectivePosition = isTransitioning ? Duration.zero : position;

    final engineProgress = duration.inMilliseconds == 0
        ? 0.0
        : (effectivePosition.inMilliseconds / duration.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    final displayProgress = _isDragging
        ? (_scrubPreview ?? engineProgress)
        : engineProgress;

    final displayPosition = _isDragging && _scrubPreview != null
        ? Duration(
            milliseconds: (_scrubPreview! * duration.inMilliseconds).round(),
          )
        : effectivePosition;
    final remaining = duration > displayPosition
        ? duration - displayPosition
        : Duration.zero;

    final positionLabel =
        '${displayPosition.inMinutes}:${(displayPosition.inSeconds % 60).toString().padLeft(2, '0')}';
    final durationLabel =
        '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Semantics(
      liveRegion: true,
      label: 'Seek',
      value: '$positionLabel of $durationLabel',
      child: RepaintBoundary(
        child: Column(
          children: [
            AudioVisualScrubber(
              progress: displayProgress,
              playedColor: energy,
              height: AfLayout.scrubberHeight,
              onScrub: (p) => setState(() {
                _isDragging = true;
                _scrubPreview = p;
              }),
              onScrubEnd: (p) async {
                final newPos = Duration(
                  milliseconds: (p * duration.inMilliseconds).round(),
                );
                final svc = ref.read(playerServiceProvider);
                final wasCompletedAtEnd = svc.isCompleted && svc.isUserPaused;
                try {
                  await svc.seek(newPos).timeout(const Duration(seconds: 2));
                  if (wasCompletedAtEnd && mounted) {
                    await svc.play().timeout(const Duration(seconds: 2));
                  }
                } catch (e, stack) {
                  afLog(
                    'error',
                    'Seek during drag failed',
                    error: e,
                    stackTrace: stack,
                  );
                }
                if (mounted) {
                  setState(() {
                    _isDragging = false;
                    _scrubPreview = null;
                  });
                }
              },
            ),
            const SizedBox(height: AfSpacing.s4),
            // ── Buffered range bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s4),
              child: SizedBox(
                height: 3,
                child: ClipRRect(
                  borderRadius: AfRadii.borderPill,
                  child: Stack(
                    children: [
                      // Track background
                      Positioned.fill(
                        child: ColoredBox(
                          color: AfColors.textTertiary.withValues(alpha: 0.10),
                        ),
                      ),
                      // Buffered fill
                      FractionallySizedBox(
                        widthFactor: (_bufferedPercent / 100.0).clamp(0.0, 1.0),
                        child: const ColoredBox(
                          color: AfColors.glassFillMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AfSpacing.s4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatTrackDuration(displayPosition),
                    style: AfTypography.mono.copyWith(
                      color: AfColors.textSecondary,
                    ),
                  ),
                  // ── Prefetch duration indicator ──
                  if (_prefetchDuration > Duration.zero &&
                      _prefetchDuration < duration)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s8,
                        vertical: AfSpacing.s2,
                      ),
                      decoration: const BoxDecoration(
                        color: AfColors.glassFillStrong,
                        borderRadius: AfRadii.borderPill,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.cloudDownload,
                            size: 10,
                            color: AfColors.textTertiary,
                          ),
                          const SizedBox(width: AfSpacing.s2),
                          Text(
                            '${_prefetchDuration.inSeconds}s',
                            style: AfTypography.overline.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    formatRemaining(remaining),
                    style: AfTypography.mono.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
