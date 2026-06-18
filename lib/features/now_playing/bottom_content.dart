import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/artwork.dart';
import '../../widgets/favorite_heart_button.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/press_scale.dart';
import '../sleep_timer/sleep_timer_screen.dart';
import 'artist_navigation.dart';
import 'more_menu.dart';
import 'reactive_progress.dart';
import 'transport_widgets.dart';

/// Bottom content zone — metadata, scrubber, transport, expandable queue.
///
/// Swipe up on non-scrubber area to reveal the up-next queue panel.
class BottomContent extends ConsumerStatefulWidget {
  const BottomContent({
    super.key,
    required this.track,
    required this.expandedNotifier,
  });
  final AfTrack track;
  final ValueNotifier<bool> expandedNotifier;

  @override
  ConsumerState<BottomContent> createState() => _BottomContentState();
}

class _BottomContentState extends ConsumerState<BottomContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: AfDurations.standard,
      reverseDuration: AfDurations.quick,
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: AfCurves.easeEmphasized,
    );
    widget.expandedNotifier.addListener(_onExpandChanged);
  }

  void _onExpandChanged() {
    final target = widget.expandedNotifier.value;
    if (target != _expanded) {
      setState(() => _expanded = target);
      if (_expanded) {
        _expandCtrl.forward();
      } else {
        _expandCtrl.reverse();
      }
    }
  }

  @override
  void didUpdateWidget(covariant BottomContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id && _expanded) {
      _toggleExpand();
    }
  }

  @override
  void dispose() {
    widget.expandedNotifier.removeListener(_onExpandChanged);
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    widget.expandedNotifier.value = !widget.expandedNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(playerServiceProvider).currentQueue;
    final currentIndex = ref.watch(playerServiceProvider).currentIndex;

    // Up-next queue: items after the current track (computed once per rebuild)
    final queueLen = queue.length;
    final upNext = queueLen > 1
        ? queue.sublist(currentIndex + 1).take(20).toList(growable: false)
        : <AfTrack>[];

    return AnimatedBuilder(
      animation: _expandAnim,
      builder: (context, _) {
        // Interpolate max height: compact ~36% → expanded ~70% (below top bar)
        final screenH = MediaQuery.sizeOf(context).height;
        final compactH = screenH * 0.36;
        final expandedH = screenH - kToolbarHeight - 80; // below top bar
        final currentH = compactH + (expandedH - compactH) * _expandAnim.value;

        return SizedBox(
          height: currentH,
          child: Semantics(
            label: 'Now playing bottom content',
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: (details) {
                final vy = details.primaryVelocity ?? 0;
                if (vy < -200 || (vy < 0 && !_expanded)) {
                  if (!_expanded) _toggleExpand();
                } else if (vy > 200 || (vy > 0 && _expanded)) {
                  if (_expanded) _toggleExpand();
                }
              },
              child: GlassCard(
                // ponytail: top-only corner, no matching AfRadii token
                borderRadius: const BorderRadius.vertical(top: AfRadii.rLg),
                blurSigma: 30,
                color: AfColors.glassFillHeavy,
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AfSpacing.s16,
                        AfSpacing.s12,
                        AfSpacing.s16,
                        AfSpacing.s8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Metadata overlay (title + artist) ──
                          RepaintBoundary(
                            child: MetadataOverlay(track: widget.track),
                          ),
                          const SizedBox(height: AfSpacing.s12),
                          // ── Progress bar ──
                          ReactiveProgress(track: widget.track),
                          const SizedBox(height: AfSpacing.s12),
                          // ── Transport controls ──
                          ReactiveTransport(track: widget.track),
                        ],
                      ),
                    ),

                    // ── Expandable queue section ──
                    if (_expanded && upNext.isNotEmpty) ...[
                      const Divider(height: 1, color: AfColors.surfaceHigh),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16,
                          vertical: AfSpacing.s8,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Up Next',
                              style: AfTypography.titleSmall.copyWith(
                                color: AfColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: AfSpacing.s8),
                            Text(
                              '${upNext.length} tracks',
                              style: AfTypography.caption.copyWith(
                                color: AfColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: AfSpacing.s8),
                          itemCount: upNext.length,
                          itemBuilder: (context, index) {
                            final t = upNext[index];
                            return PressScale(
                              key: ValueKey(t.id),
                              onTap: () {
                                unawaited(
                                  ref
                                      .read(playerServiceProvider)
                                      .skipToQueueItem(queue.indexOf(t)),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AfSpacing.s16,
                                  vertical: AfSpacing.s4,
                                ),
                                child: Row(
                                  children: [
                                    Artwork(
                                      url: t.imageUrl,
                                      size: 20,
                                      radius: AfRadii.borderSm,
                                    ),
                                    const SizedBox(width: AfSpacing.s8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            t.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AfTypography.bodyMedium,
                                          ),
                                          const SizedBox(height: AfSpacing.s2),
                                          Text(
                                            t.artistName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AfTypography.caption
                                                .copyWith(
                                                  color: AfColors.textTertiary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: AfSpacing.s8),
                                    Text(
                                      formatTrackDuration(t.duration),
                                      style: AfTypography.caption.copyWith(
                                        color: AfColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Title + artist row with heart toggle, quality badge, and more menu.
class MetadataOverlay extends ConsumerWidget {
  const MetadataOverlay({super.key, required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => (link: s.link, muted: s.muted)),
    );
    final sleepRemaining = ref.watch(sleepTimerRemainingProvider);
    final loadedTrackId = ref.watch(mpvLoadedTrackIdProvider);
    final isTransitioning = track.id != loadedTrackId;
    return Row(
      children: [
        // Title + artist
        Expanded(
          child: AnimatedOpacity(
            opacity: isTransitioning ? 0.5 : 1.0,
            duration: AfDurations.quick,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MarqueeText(text: track.title, style: AfTypography.titleMedium),
                const SizedBox(height: AfSpacing.s4),
                PressScale(
                  ensureHitTarget: false,
                  onTap: () => navigateToArtist(
                    context,
                    ref,
                    artistId: track.artistId,
                    artistName: track.artistName,
                  ),
                  child: Semantics(
                    label: 'Go to artist ${track.artistName}',
                    button: true,
                    child: Text(
                      track.artistName,
                      style: AfTypography.bodySmall.copyWith(
                        color: spectral.link,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AfSpacing.s12),
        // Heart toggle
        FavoriteHeartButton(track: track, size: AfIconSizes.sm),
        // Dynamic badge: sleep timer countdown or quality
        if (sleepRemaining != null) ...[
          const SizedBox(width: AfSpacing.s4),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s8,
              vertical: AfSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: spectral.muted.withValues(alpha: 0.2),
              borderRadius: AfRadii.borderPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.timer,
                  size: 12,
                  color: AfColors.textSecondary,
                ),
                const SizedBox(width: AfSpacing.s2),
                Text(
                  _formatRemaining(sleepRemaining),
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ] else if (track.quality != null) ...[
          const SizedBox(width: AfSpacing.s4),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s8,
              vertical: AfSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: spectral.muted.withValues(alpha: 0.2),
              borderRadius: AfRadii.borderPill,
            ),
            child: Text(
              track.quality!.chipLabel,
              style: AfTypography.caption.copyWith(color: AfColors.textPrimary),
            ),
          ),
        ],
        // More menu (vertical dots)
        IconButton(
          icon: const Icon(
            LucideIcons.ellipsisVertical,
            size: AfIconSizes.sm,
            color: AfColors.textSecondary,
          ),
          tooltip: 'More options',
          onPressed: () => showMoreSheet(context, ref),
        ),
      ],
    );
  }
}

/// Format sleep timer remaining as "12:34" or "1h 23m" depending on magnitude.
String _formatRemaining(Duration d) {
  final totalMinutes = d.inMinutes;
  if (totalMinutes >= 60) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
  final mm = totalMinutes.toString().padLeft(2, '0');
  final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}
