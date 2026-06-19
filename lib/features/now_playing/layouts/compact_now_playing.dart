import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/jellyfin/models/items.dart';
import '../../../core/lyrics/lrc_parser.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/af_loading_indicator.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/favorite_heart_button.dart';
import '../../../widgets/marquee_text.dart';
import '../../../widgets/press_scale.dart';
import '../artist_navigation.dart';
import '../lyrics_panel.dart';
import '../more_menu.dart';
import '../reactive_artwork.dart';
import '../reactive_progress.dart';
import '../transport_widgets.dart';

/// Compact layout — phones up to ~600dp.
///
/// Clean, spacious, Apple Music-inspired:
///   ├── Minimal top row (back, heart, more)
///   ├── Large artwork with spectral glow (shrinks when lyrics/queue open)
///   ├── Lyrics or Queue panel (when toggled)
///   ├── Metadata (title, artist)
///   ├── AudioVisualScrubber (FFT + progress)
///   ├── Transport controls (spacious)
///   └── Secondary actions (lyrics, queue)
class CompactNowPlaying extends ConsumerStatefulWidget {
  const CompactNowPlaying({
    super.key,
    required this.track,
    required this.spectral,
    required this.expandedNotifier,
    required this.lyricsExpandedNotifier,
    required this.onToggleLyrics,
  });

  final AfTrack track;
  final Spectral spectral;
  final ValueNotifier<bool> expandedNotifier;
  final ValueNotifier<bool> lyricsExpandedNotifier;
  final VoidCallback onToggleLyrics;

  @override
  ConsumerState<CompactNowPlaying> createState() => _CompactNowPlayingState();
}

class _CompactNowPlayingState extends ConsumerState<CompactNowPlaying> {
  final _scrollCtrl = ScrollController();
  bool _showLyrics = false;
  bool _showQueue = false;

  @override
  void initState() {
    super.initState();
    widget.lyricsExpandedNotifier.addListener(_onLyricsChanged);
    widget.expandedNotifier.addListener(_onQueueChanged);
  }

  void _onLyricsChanged() {
    final target = widget.lyricsExpandedNotifier.value;
    setState(() {
      _showLyrics = target;
      if (target) _showQueue = false;
    });
    if (target) widget.expandedNotifier.value = false;
  }

  void _onQueueChanged() {
    final target = widget.expandedNotifier.value;
    setState(() {
      _showQueue = target;
      if (target) _showLyrics = false;
    });
    if (target) widget.lyricsExpandedNotifier.value = false;
  }

  @override
  void didUpdateWidget(covariant CompactNowPlaying oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _showLyrics = false;
      _showQueue = false;
      widget.lyricsExpandedNotifier.value = false;
      widget.expandedNotifier.value = false;
    }
  }

  @override
  void dispose() {
    widget.lyricsExpandedNotifier.removeListener(_onLyricsChanged);
    widget.expandedNotifier.removeListener(_onQueueChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final spectral = widget.spectral;

    final lrcAsync = ref.watch(lyricsProvider(track.id));
    final lyricsResult = lrcAsync.maybeWhen(data: (p) => p, orElse: () => null);
    final lrc = lyricsResult?.lrc;
    final lyricsSource = lyricsResult?.source;
    final isSynced =
        lrc != null && lrc.lines.any((l) => l.start > Duration.zero);

    final queue = ref.watch(playerServiceProvider).currentQueue;
    final currentIndex = ref.watch(playerServiceProvider).currentIndex;
    final upNext = queue.length > 1
        ? queue.sublist(currentIndex + 1).take(20).toList(growable: false)
        : <AfTrack>[];

    return Column(
      children: [
        // ── Minimal top row ──
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s8,
              vertical: AfSpacing.s4,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    LucideIcons.chevronDown,
                    color: AfColors.textPrimary,
                    size: AfIconSizes.md,
                  ),
                  tooltip: 'Close',
                  onPressed: () {
                    if (context.canPop()) context.pop();
                  },
                ),
                const Spacer(),
                FavoriteHeartButton(track: track, size: AfIconSizes.sm),
                const SizedBox(width: AfSpacing.s8),
                IconButton(
                  icon: const Icon(
                    LucideIcons.ellipsisVertical,
                    color: AfColors.textSecondary,
                    size: AfIconSizes.sm,
                  ),
                  tooltip: 'More options',
                  onPressed: () => showMoreSheet(context, ref),
                ),
              ],
            ),
          ),
        ),

        // ── Artwork / Lyrics / Queue (same slot, crossfade) ──
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: AnimatedSwitcher(
              duration: AfDurations.standard,
              switchInCurve: AfCurves.easeEmphasized,
              switchOutCurve: AfCurves.easeEmphasized,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _showLyrics
                  ? KeyedSubtree(
                      key: const ValueKey('lyrics'),
                      child: _buildLyricsPanel(
                        lrcAsync: lrcAsync,
                        lrc: lrc,
                        lyricsSource: lyricsSource,
                        isSynced: isSynced,
                        spectral: spectral.energy,
                        track: track,
                      ),
                    )
                  : _showQueue
                  ? KeyedSubtree(
                      key: const ValueKey('queue'),
                      child: _buildQueuePanel(
                        upNext: upNext,
                        queue: queue,
                        track: track,
                        accent: spectral.energy,
                      ),
                    )
                  : Semantics(
                      key: const ValueKey('artwork'),
                      button: true,
                      label: 'Now playing artwork',
                      child: GestureDetector(
                        onTap: () {
                          if (widget.lyricsExpandedNotifier.value) {
                            widget.lyricsExpandedNotifier.value = false;
                          }
                        },
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) < -200) {
                            widget.expandedNotifier.value = true;
                          }
                        },
                        behavior: HitTestBehavior.translucent,
                        child: RepaintBoundary(
                          child: ReactiveArtwork(track: track),
                        ),
                      ),
                    ),
            ),
          ),
        ),

        // ── Metadata ──
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
              MarqueeText(text: track.title, style: AfTypography.titleLarge),
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
                    style: AfTypography.bodyLarge.copyWith(
                      color: AfColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── AudioVisualScrubber ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: ReactiveProgress(track: track),
        ),

        const SizedBox(height: AfSpacing.s12),

        // ── Transport controls ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s24),
          child: ReactiveTransport(track: track),
        ),

        const SizedBox(height: AfSpacing.s12),

        // ── Secondary actions ──
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AfSpacing.s32,
            0,
            AfSpacing.s32,
            AfSpacing.s12,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SecondaryButton(
                icon: LucideIcons.mic2,
                label: 'Lyrics',
                isActive: _showLyrics,
                onTap: widget.onToggleLyrics,
              ),
              const SizedBox(width: AfSpacing.s24),
              _SecondaryButton(
                icon: LucideIcons.listMusic,
                label: 'Queue',
                isActive: _showQueue,
                onTap: () {
                  widget.expandedNotifier.value =
                      !widget.expandedNotifier.value;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsPanel({
    required AsyncValue<LyricsResult?> lrcAsync,
    required Lrc? lrc,
    required LyricsSource? lyricsSource,
    required bool isSynced,
    required Color spectral,
    required AfTrack track,
  }) {
    return Column(
      children: [
        if (lyricsSource != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              AfSpacing.s4,
              AfSpacing.s16,
              0,
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.radio,
                  size: 12,
                  color: AfColors.textTertiary,
                ),
                const SizedBox(width: AfSpacing.s4),
                Text(
                  lyricsSource.label,
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: lrc != null && lrc.lines.isNotEmpty
              ? LyricsList(
                  lrc: lrc,
                  spectralEnergy: spectral,
                  scrollController: _scrollCtrl,
                  isSynced: isSynced,
                )
              : lrcAsync.isLoading
              ? const Center(
                  child: AfLoadingIndicator(
                    strokeWidth: 2,
                    color: AfColors.textTertiary,
                  ),
                )
              : Center(
                  child: Text(
                    'No lyrics available',
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildQueuePanel({
    required List<AfTrack> upNext,
    required List<AfTrack> queue,
    required AfTrack track,
    required Color accent,
  }) {
    if (upNext.isEmpty) {
      return Center(
        child: Text(
          'No upcoming tracks',
          style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s16,
            vertical: AfSpacing.s4,
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
        const Divider(height: 1, color: AfColors.surfaceHigh),
        Expanded(
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
                        size: 28,
                        radius: AfRadii.borderSm,
                      ),
                      const SizedBox(width: AfSpacing.s8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                              style: AfTypography.caption.copyWith(
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
            },
          ),
        ),
      ],
    );
  }
}

/// Secondary action button (icon beside label).
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: AfIconSizes.sm,
            color: isActive ? AfColors.accentPrimary : AfColors.textSecondary,
          ),
          const SizedBox(width: AfSpacing.s4),
          Text(
            label,
            style: AfTypography.caption.copyWith(
              color: isActive ? AfColors.accentPrimary : AfColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
