import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/bottom_sheet.dart';
import 'empty_state.dart';
import 'layouts/compact_now_playing.dart';
import 'layouts/expanded_now_playing.dart';
import 'layouts/medium_now_playing.dart';
import 'reactive_background.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NowPlayingScreen — thin orchestrator
//
// Uses LayoutBuilder to select responsive layout variant:
//   Compact  (< 600dp):  Full-bleed immersive Stack (artwork top, controls bottom)
//   Medium   (600-840dp): Side-by-side (artwork left, controls right)
//   Expanded (> 840dp):   Three-column (artwork, controls, lyrics/queue)
//
// All layouts use ReactiveBackground for spectral-derived color fill.
// High-frequency streams (position, FFT) are isolated to leaf widgets
// so they never trigger rebuilds of the artwork, gradient, or metadata.
// ─────────────────────────────────────────────────────────────────────────────

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  final _expandedNotifier = ValueNotifier<bool>(false);
  final _lyricsExpandedNotifier = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _expandedNotifier.dispose();
    _lyricsExpandedNotifier.dispose();
    super.dispose();
  }

  /// Collapse queue, then expand lyrics (or toggle if already expanded).
  void _toggleLyrics() {
    if (_expandedNotifier.value) {
      _expandedNotifier.value = false;
    }
    _lyricsExpandedNotifier.value = !_lyricsExpandedNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    final spectral = ref.watch(currentSpectralProvider);

    if (track == null) {
      return const NowPlayingEmptyState();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Top-most overlay sheet (e.g. "more" menu) must close first.
        if (blurSheetCount.value > 0) {
          blurSheetDismiss.value?.call();
          return;
        }
        // If the bottom bar is expanded, collapse it instead of popping.
        if (_expandedNotifier.value) {
          _expandedNotifier.value = false;
        } else if (_lyricsExpandedNotifier.value) {
          _lyricsExpandedNotifier.value = false;
        } else {
          if (context.canPop()) context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: RepaintBoundary(
          child: ReactiveBackground(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final screenSize = AfLayout.screenSize(constraints.maxWidth);
                return switch (screenSize) {
                  AfScreenSize.compact => CompactNowPlaying(
                    track: track,
                    spectral: spectral,
                    expandedNotifier: _expandedNotifier,
                    lyricsExpandedNotifier: _lyricsExpandedNotifier,
                    onToggleLyrics: _toggleLyrics,
                  ),
                  AfScreenSize.medium => MediumNowPlaying(
                    track: track,
                    lyricsExpandedNotifier: _lyricsExpandedNotifier,
                  ),
                  AfScreenSize.expanded => ExpandedNowPlaying(
                    track: track,
                    lyricsExpandedNotifier: _lyricsExpandedNotifier,
                  ),
                };
              },
            ),
          ),
        ),
      ),
    );
  }
}
