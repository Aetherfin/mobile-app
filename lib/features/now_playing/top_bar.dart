import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../widgets/af_loading_indicator.dart';
import '../../state/providers.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/press_scale.dart';
import 'lyrics_panel.dart';

/// Frosted-glass top bar with expandable lyrics panel.
class FrostedTopBar extends ConsumerStatefulWidget {
  const FrostedTopBar({
    super.key,
    required this.track,
    required this.lyricsExpanded,
    required this.onToggleLyrics,
  });
  final AfTrack track;
  final ValueNotifier<bool> lyricsExpanded;
  final VoidCallback onToggleLyrics;

  @override
  ConsumerState<FrostedTopBar> createState() => _FrostedTopBarState();
}

class _FrostedTopBarState extends ConsumerState<FrostedTopBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: AfDurations.expressive,
      reverseDuration: AfDurations.quick,
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: AfCurves.easeEmphasized,
    );
    widget.lyricsExpanded.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant FrostedTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(0);
      }
    }
  }

  void _onChanged() {
    if (widget.lyricsExpanded.value) {
      _expandCtrl.forward();
    } else {
      _expandCtrl.reverse();
    }
  }

  @override
  void dispose() {
    widget.lyricsExpanded.removeListener(_onChanged);
    _expandCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider.select((s) => s.energy));
    final track = widget.track;

    final lrcAsync = ref.watch(lyricsProvider(track.id));
    final lyricsResult = lrcAsync.maybeWhen(data: (p) => p, orElse: () => null);
    final lrc = lyricsResult?.lrc;
    final lyricsSource = lyricsResult?.source;
    final isSynced =
        lrc != null && lrc.lines.any((l) => l.start > Duration.zero);

    return AnimatedBuilder(
      animation: _expandAnim,
      builder: (context, _) {
        final radius = BorderRadius.circular(
          ui.lerpDouble(AfRadii.xl, AfRadii.lg, _expandAnim.value)!,
        ); // 36→24dp xl, closest token

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s16,
            vertical: AfSpacing.s8,
          ),
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 200 &&
                  widget.lyricsExpanded.value) {
                widget.onToggleLyrics();
              }
            },
            child: Semantics(
              button: true,
              label: 'Swipe down to close lyrics',
              child: GlassCard(
                borderRadius: radius,
                blurSigma: 30,
                color: AfColors.glassFillHeavy,
                borderColor: AfColors.glassBorderEmphasis,
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
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
                              size: AfIconSizes.sm,
                            ),
                            tooltip: 'Close',
                            onPressed: () => context.pop(),
                          ),
                          const SizedBox(width: AfSpacing.s8),
                          Expanded(
                            child: PressScale(
                              ensureHitTarget: false,
                              onTap: track.albumId == null
                                  ? null
                                  : () =>
                                        context.push('/album/${track.albumId}'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AfSpacing.s4,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      track.albumName.isNotEmpty
                                          ? 'PLAYING FROM ALBUM'
                                          : 'NOW PLAYING',
                                      style: AfTypography.overline.copyWith(
                                        color: AfColors.textSecondary,
                                      ),
                                    ),
                                    MarqueeText(
                                      text: track.albumName.isNotEmpty
                                          ? track.albumName
                                          : 'Aetherfin',
                                      style: AfTypography.titleSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AfSpacing.s8),
                          IconButton(
                            icon: Icon(
                              LucideIcons.mic2,
                              color: widget.lyricsExpanded.value
                                  ? spectral
                                  : AfColors.textPrimary,
                              size: 20,
                            ),
                            tooltip: 'Lyrics',
                            onPressed: widget.onToggleLyrics,
                          ),
                        ],
                      ),
                    ),
                    SizeTransition(
                      sizeFactor: _expandAnim,
                      child: FadeTransition(
                        opacity: _expandAnim,
                        child: lrc != null && lrc.lines.isNotEmpty
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
                                            lyricsSource.label,
                                            style: AfTypography.caption
                                                .copyWith(
                                                  color: AfColors.textTertiary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  LyricsList(
                                    lrc: lrc,
                                    spectralEnergy: spectral,
                                    scrollController: _scrollCtrl,
                                    isSynced: isSynced,
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
