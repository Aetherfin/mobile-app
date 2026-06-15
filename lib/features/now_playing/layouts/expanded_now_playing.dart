import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/jellyfin/models/items.dart';
import '../../../core/lyrics/lrc_parser.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/favorite_heart_button.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/marquee_text.dart';
import '../../../widgets/press_scale.dart';
import '../lyrics_panel.dart';
import '../reactive_artwork.dart';
import '../reactive_progress.dart';
import '../transport_widgets.dart';

/// Expanded layout — large tablets and desktops > 840dp.
///
/// Three-column Row:
///   Left:   Artwork card (33%)
///   Center: Metadata, scrubber, transport (33%)
///   Right:  Lyrics panel or queue list (33%)
class ExpandedNowPlaying extends ConsumerStatefulWidget {
  const ExpandedNowPlaying({
    super.key,
    required this.track,
    required this.lyricsExpandedNotifier,
  });

  final AfTrack track;
  final ValueNotifier<bool> lyricsExpandedNotifier;

  @override
  ConsumerState<ExpandedNowPlaying> createState() => _ExpandedNowPlayingState();
}

class _ExpandedNowPlayingState extends ConsumerState<ExpandedNowPlaying> {
  final _scrollCtrl = ScrollController();
  bool _showLyrics = true;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final spectral = ref.watch(currentSpectralProvider.select((s) => s.energy));

    final lrcAsync = ref.watch(lyricsProvider(track.id));
    final lyricsResult = lrcAsync.maybeWhen(data: (p) => p, orElse: () => null);
    final lrc = lyricsResult?.lrc;
    final lyricsSource = lyricsResult?.source;
    final isSynced =
        lrc != null && lrc.lines.any((l) => l.start > Duration.zero);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Left: Artwork ──
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(AfSpacing.s24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: RepaintBoundary(child: ReactiveArtwork(track: track)),
                ),
              ),
            ),
          ),
        ),

        // ── Center: Controls ──
        Expanded(
          flex: 3,
          child: SafeArea(
            left: false,
            right: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s24,
                vertical: AfSpacing.s32,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  Semantics(
                    liveRegion: true,
                    child: MarqueeText(
                      text: track.title,
                      style: AfTypography.titleExtraLarge,
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s4),
                  // Artist
                  PressScale(
                    ensureHitTarget: false,
                    onTap: track.artistId == null
                        ? null
                        : () => context.push('/artist/${track.artistId}'),
                    child: Text(
                      track.artistName,
                      style: AfTypography.bodyLarge.copyWith(
                        color: track.artistId == null
                            ? AfColors.textSecondary
                            : spectral,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (track.albumName.isNotEmpty) ...[
                    const SizedBox(height: AfSpacing.s4),
                    PressScale(
                      ensureHitTarget: false,
                      onTap: track.albumId == null
                          ? null
                          : () => context.push('/album/${track.albumId}'),
                      child: Text(
                        track.albumName,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(height: AfSpacing.s24),

                  // Scrubber
                  ReactiveProgress(track: track),
                  const SizedBox(height: AfSpacing.s24),

                  // Transport
                  ReactiveTransport(track: track),
                  const SizedBox(height: AfSpacing.s24),

                  // Favorite
                  FavoriteHeartButton(track: track),
                ],
              ),
            ),
          ),
        ),

        // ── Right: Lyrics / Queue toggle ──
        Expanded(
          flex: 3,
          child: SafeArea(
            left: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
                vertical: AfSpacing.s16,
              ),
              child: Column(
                children: [
                  // Toggle row
                  Row(
                    children: [
                      _TabButton(
                        label: 'Lyrics',
                        icon: LucideIcons.mic2,
                        isActive: _showLyrics,
                        accent: spectral,
                        onTap: () => setState(() => _showLyrics = true),
                      ),
                      const SizedBox(width: AfSpacing.s8),
                      _TabButton(
                        label: 'Queue',
                        icon: LucideIcons.listMusic,
                        isActive: !_showLyrics,
                        accent: spectral,
                        onTap: () => setState(() => _showLyrics = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: AfSpacing.s12),

                  // Content
                  Expanded(
                    child: _showLyrics
                        ? _LyricsPane(
                            lrcAsync: lrcAsync,
                            lrc: lrc,
                            lyricsSource: lyricsSource,
                            isSynced: isSynced,
                            spectral: spectral,
                            track: track,
                            scrollCtrl: _scrollCtrl,
                          )
                        : _QueuePane(track: track, accent: spectral),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tab toggle button for the right panel.
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AfSpacing.s8),
          decoration: BoxDecoration(
            color: isActive
                ? accent.withValues(alpha: 0.15)
                : AfColors.surfaceHigh.withValues(alpha: 0.3),
            borderRadius: AfRadii.borderSm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? accent : AfColors.textTertiary,
              ),
              const SizedBox(width: AfSpacing.s4),
              Text(
                label,
                style: AfTypography.label.copyWith(
                  color: isActive ? accent : AfColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lyrics panel for expanded layout.
class _LyricsPane extends StatelessWidget {
  const _LyricsPane({
    required this.lrcAsync,
    required this.lrc,
    required this.lyricsSource,
    required this.isSynced,
    required this.spectral,
    required this.track,
    required this.scrollCtrl,
  });

  final AsyncValue<LyricsResult?> lrcAsync;
  final Lrc? lrc;
  final LyricsSource? lyricsSource;
  final bool isSynced;
  final Color spectral;
  final AfTrack track;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: AfRadii.borderMd,
      blurSigma: 20,
      color: AfColors.glassFillHeavy,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AfRadii.borderMd,
        child: lrc != null && lrc!.lines.isNotEmpty
            ? Column(
                children: [
                  if (lyricsSource != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AfSpacing.s16,
                        AfSpacing.s8,
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
                            lyricsSource!.label,
                            style: AfTypography.caption.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: LyricsList(
                      lrc: lrc!,
                      spectralEnergy: spectral,
                      scrollController: scrollCtrl,
                      isSynced: isSynced,
                    ),
                  ),
                ],
              )
            : lrcAsync.isLoading
            ? const Padding(
                padding: EdgeInsets.all(AfSpacing.s24),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AfColors.textTertiary,
                  ),
                ),
              )
            : EmptyLyrics(track: track),
      ),
    );
  }
}

/// Queue panel for expanded layout.
class _QueuePane extends ConsumerWidget {
  const _QueuePane({required this.track, required this.accent});

  final AfTrack track;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playerServiceProvider).currentQueue;
    final currentIndex = ref.watch(playerServiceProvider).currentIndex;
    final queueLen = queue.length;

    if (queueLen <= 1) {
      return Center(
        child: Text(
          'No upcoming tracks',
          style: AfTypography.bodyMedium.copyWith(color: AfColors.textTertiary),
        ),
      );
    }

    final upNext = queue.sublist(currentIndex + 1).take(30).toList();

    return GlassCard(
      borderRadius: AfRadii.borderMd,
      blurSigma: 20,
      color: AfColors.glassFillHeavy,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              AfSpacing.s12,
              AfSpacing.s16,
              AfSpacing.s4,
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
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: AfSpacing.s8),
              itemCount: upNext.length,
              itemBuilder: (context, index) {
                final t = upNext[index];
                final isCurrent = t.id == track.id;
                return PressScale(
                  onTap: () {
                    ref
                        .read(playerServiceProvider)
                        .skipToQueueItem(queue.indexOf(t));
                  },
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Text(
                      '${index + 1}',
                      style: AfTypography.caption.copyWith(
                        color: isCurrent ? accent : AfColors.textTertiary,
                      ),
                    ),
                    title: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.bodyMedium.copyWith(
                        color: isCurrent ? accent : AfColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      t.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.caption.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
