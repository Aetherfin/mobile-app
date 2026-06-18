import 'package:flutter/material.dart';

import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../bottom_content.dart';
import '../reactive_artwork.dart';
import '../top_bar.dart';

/// Compact layout — phones up to ~600dp.
///
/// Full-bleed immersive Stack:
///   ├── Centered artwork card (swipe up to expand queue)
///   ├── Gradient scrim (bottom content zone)
///   ├── FrostedTopBar (top, expandable lyrics)
///   └── BottomContent (metadata, scrubber, transport, queue)
class CompactNowPlaying extends StatelessWidget {
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

  // Layout constants — derived from top-bar compact height + artwork ratios.
  static const double _topBarCompactHeight = 76;
  static const double _artworkHorizontalMargin = 32;
  static const double _contentHeightRatio = 0.36;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Centered artwork card (swipe up to expand queue) ──
        Positioned(
          top: _topBarCompactHeight,
          bottom: MediaQuery.of(context).size.height * _contentHeightRatio,
          left: _artworkHorizontalMargin,
          right: _artworkHorizontalMargin,
          child: Semantics(
            button: true,
            label: 'Now playing artwork',
            child: GestureDetector(
              onTap: () {
                if (lyricsExpandedNotifier.value) {
                  lyricsExpandedNotifier.value = false;
                }
              },
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -200) {
                  expandedNotifier.value = true;
                }
              },
              behavior: HitTestBehavior.translucent,
              child: RepaintBoundary(child: ReactiveArtwork(track: track)),
            ),
          ),
        ),

        // ── Gradient scrim (bottom content zone only) ──
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: MediaQuery.of(context).size.height * _contentHeightRatio,
          child: RepaintBoundary(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        spectral.surfaceCanvas.withValues(alpha: 0.6),
                        spectral.surfaceCanvas,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Top bar ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: FrostedTopBar(
              track: track,
              lyricsExpanded: lyricsExpandedNotifier,
              onToggleLyrics: onToggleLyrics,
            ),
          ),
        ),

        // ── Bottom content zone ──
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: BottomContent(
              track: track,
              expandedNotifier: expandedNotifier,
            ),
          ),
        ),
      ],
    );
  }
}
