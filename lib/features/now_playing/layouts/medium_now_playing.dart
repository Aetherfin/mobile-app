import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/jellyfin/models/items.dart';
import '../../../core/lyrics/lrc_parser.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/af_loading_indicator.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/marquee_text.dart';
import '../../../widgets/press_scale.dart';
import '../lyrics_panel.dart';
import '../reactive_artwork.dart';
import '../reactive_progress.dart';
import '../transport_widgets.dart';

/// Medium layout — foldables and small tablets 600–840dp.
///
/// Side-by-side: artwork card left 50%, controls column right 50%.
/// Right column contains: metadata, scrubber, transport, lyrics panel.
class MediumNowPlaying extends ConsumerStatefulWidget {
  const MediumNowPlaying({
    super.key,
    required this.track,
    required this.lyricsExpandedNotifier,
  });

  final AfTrack track;
  final ValueNotifier<bool> lyricsExpandedNotifier;

  @override
  ConsumerState<MediumNowPlaying> createState() => _MediumNowPlayingState();
}

class _MediumNowPlayingState extends ConsumerState<MediumNowPlaying>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lyricsCtrl;
  late final Animation<double> _lyricsAnim;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _lyricsCtrl = AnimationController(
      vsync: this,
      duration: AfDurations.standard,
      reverseDuration: AfDurations.quick,
    );
    _lyricsAnim = CurvedAnimation(
      parent: _lyricsCtrl,
      curve: AfCurves.easeEmphasized,
    );
    widget.lyricsExpandedNotifier.addListener(_onLyricsChanged);
  }

  void _onLyricsChanged() {
    if (widget.lyricsExpandedNotifier.value) {
      _lyricsCtrl.forward();
    } else {
      _lyricsCtrl.reverse();
    }
  }

  @override
  void dispose() {
    widget.lyricsExpandedNotifier.removeListener(_onLyricsChanged);
    _lyricsCtrl.dispose();
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
        // ── Left: Artwork card ──
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.all(AfSpacing.s24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: RepaintBoundary(child: ReactiveArtwork(track: track)),
                ),
              ),
            ),
          ),
        ),

        // ── Right: Controls column ──
        Expanded(
          flex: 5,
          child: SafeArea(
            left: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s24,
                vertical: AfSpacing.s16,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Metadata ──
                  _MediumMetadata(track: track, spectral: spectral),
                  const SizedBox(height: AfSpacing.s20),

                  // ── Scrubber ──
                  ReactiveProgress(track: track),
                  const SizedBox(height: AfSpacing.s20),

                  // ── Transport ──
                  ReactiveTransport(track: track),
                  const SizedBox(height: AfSpacing.s20),

                  // ── Lyrics toggle + panel ──
                  _LyricsToggleSection(
                    lrcAsync: lrcAsync,
                    lrc: lrc,
                    lyricsSource: lyricsSource,
                    isSynced: isSynced,
                    spectral: spectral,
                    track: track,
                    lyricsAnim: _lyricsAnim,
                    scrollCtrl: _scrollCtrl,
                    onToggleLyrics: () {
                      widget.lyricsExpandedNotifier.value =
                          !widget.lyricsExpandedNotifier.value;
                    },
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

/// Metadata row for medium layout — title, artist, album with spectral links.
class _MediumMetadata extends ConsumerWidget {
  const _MediumMetadata({required this.track, required this.spectral});

  final AfTrack track;
  final Color spectral;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        Semantics(
          liveRegion: true,
          child: MarqueeText(text: track.title, style: AfTypography.titleLarge),
        ),
        const SizedBox(height: AfSpacing.s4),
        // Artist
        PressScale(
          ensureHitTarget: false,
          onTap: track.artistId == null
              ? null
              : () => context.push('/artist/${track.artistId}'),
          child: Semantics(
            label: track.artistId == null
                ? null
                : 'Go to artist ${track.artistName}',
            button: track.artistId != null,
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
        ),
        // Album
        if (track.albumName.isNotEmpty) ...[
          const SizedBox(height: AfSpacing.s2),
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
      ],
    );
  }
}

/// Lyrics section for medium layout — toggle button + collapsible lyrics.
class _LyricsToggleSection extends StatelessWidget {
  const _LyricsToggleSection({
    required this.lrcAsync,
    required this.lrc,
    required this.lyricsSource,
    required this.isSynced,
    required this.spectral,
    required this.track,
    required this.lyricsAnim,
    required this.scrollCtrl,
    required this.onToggleLyrics,
  });

  final AsyncValue<LyricsResult?> lrcAsync;
  final Lrc? lrc;
  final LyricsSource? lyricsSource;
  final bool isSynced;
  final Color spectral;
  final AfTrack track;
  final Animation<double> lyricsAnim;
  final ScrollController scrollCtrl;
  final VoidCallback onToggleLyrics;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle button
          GestureDetector(
            onTap: onToggleLyrics,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.mic2,
                  size: 16,
                  color: lyricsAnim.value > 0
                      ? spectral
                      : AfColors.textSecondary,
                ),
                const SizedBox(width: AfSpacing.s4),
                Text(
                  'Lyrics',
                  style: AfTypography.label.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AfSpacing.s8),

          // Lyrics panel
          AnimatedBuilder(
            animation: lyricsAnim,
            builder: (context, _) {
              if (lyricsAnim.value == 0) {
                return const SizedBox.shrink();
              }
              return Opacity(
                opacity: lyricsAnim.value,
                child: GlassCard(
                  borderRadius: AfRadii.borderMd,
                  blurSigma: 20,
                  color: AfColors.glassFillHeavy,
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: AfRadii.borderMd,
                    child: lrc != null && lrc!.lines.isNotEmpty
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
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
                              child: AfLoadingIndicator(
                                strokeWidth: 2,
                                color: AfColors.textTertiary,
                              ),
                            ),
                          )
                        : EmptyLyrics(track: track),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
