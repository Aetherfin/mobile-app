import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';

/// Card-style artwork for the now-playing screen.
///
/// Displays the album art as a centered, rounded-corner card with a spectral
/// shadow/glow beneath it. The card floats over the reactive background
/// gradient rather than filling the screen edge-to-edge.
///
/// This widget returns the card content only. The parent [Stack] is
/// responsible for positioning it (e.g. [Positioned] with top/bottom
/// offsets) so the artwork stays fixed when the bottom content expands.
class ReactiveArtwork extends ConsumerWidget {
  const ReactiveArtwork({super.key, required this.track});

  final AfTrack track;

  /// Border radius of the artwork card.
  static const double _cardRadius = AfRadii.xl;

  /// Blur radius of the spectral glow beneath the card.
  static const double _glowBlur = 48;

  /// Spread radius of the spectral glow.
  static const double _glowSpread = AfSpacing.s8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artworkUri = ref.watch(currentArtworkUriProvider);
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => (energy: s.energy, glow: s.glow)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Card fills the available space (square), clamped by parent.
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final cardSize = (w < h) ? w : h;

        return RepaintBoundary(
          child: Center(
            child: SizedBox(
              width: cardSize,
              height: cardSize,
              child: _ArtworkCard(
                track: track,
                artworkUri: artworkUri,
                spectralEnergy: spectral.energy,
                spectralGlow: spectral.glow,
                cardRadius: _cardRadius,
                glowBlur: _glowBlur,
                glowSpread: _glowSpread,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The actual artwork card with shadow and spectral glow.
class _ArtworkCard extends ConsumerWidget {
  const _ArtworkCard({
    required this.track,
    required this.artworkUri,
    required this.spectralEnergy,
    required this.spectralGlow,
    required this.cardRadius,
    required this.glowBlur,
    required this.glowSpread,
  });

  final AfTrack track;
  final Uri? artworkUri;
  final Color spectralEnergy;
  final Color spectralGlow;
  final double cardRadius;
  final double glowBlur;
  final double glowSpread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // ── Spectral glow beneath the card ──
        Positioned(
          top: AfSpacing.s12,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.6,
            height: MediaQuery.of(context).size.width * 0.6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: spectralEnergy.withValues(alpha: 0.30),
                  blurRadius: glowBlur,
                  spreadRadius: glowSpread,
                ),
                BoxShadow(
                  color: spectralGlow.withValues(alpha: 0.12),
                  blurRadius: glowBlur * 1.5,
                  spreadRadius: glowSpread * 1.5,
                ),
              ],
            ),
          ),
        ),

        // ── Artwork card ──
        Hero(
          tag: 'now-playing-artwork',
          child: Semantics(
            image: true,
            label: '${track.title} by ${track.artistName}',
            child: ClipRRect(
              borderRadius: AfRadii.borderXl,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: AfRadii.borderXl,
                  boxShadow: [
                    BoxShadow(
                      color: AfColors.surfaceCanvas.withValues(alpha: 0.4),
                      blurRadius: 32,
                      offset: const Offset(0, AfSpacing.s12),
                    ),
                    BoxShadow(
                      color: AfColors.surfaceCanvas.withValues(alpha: 0.2),
                      blurRadius: AfSpacing.s8,
                      offset: const Offset(0, AfSpacing.s4),
                    ),
                  ],
                ),
                child: Artwork(
                  // Prefer the HTTP imageUrl from the track metadata when
                  // available — it is always valid and avoids showing a
                  // stale/expired local file URI from a previously played
                  // track. Only fall back to artworkUri (a file:// path
                  // written by mpv or the notification downloader) when
                  // the track has no HTTP imageUrl (e.g. local-mode files).
                  url:
                      (track.imageUrl != null &&
                          !track.imageUrl!.startsWith('file://'))
                      ? track.imageUrl
                      : (artworkUri?.toString() ?? track.imageUrl),
                  size: double.infinity,
                  radius: AfRadii.borderXl,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
