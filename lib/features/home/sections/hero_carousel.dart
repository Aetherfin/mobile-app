import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/stagger_reveal.dart';
import '../../../core/audio/play_actions.dart';

/// Swipeable carousel of hero album cards with spring bounce + blur morph.
class HeroAlbumCarousel extends ConsumerStatefulWidget {
  const HeroAlbumCarousel({super.key, required this.albums});
  final List<AfAlbum> albums;

  @override
  ConsumerState<HeroAlbumCarousel> createState() => _HeroAlbumCarouselState();
}

class _HeroAlbumCarouselState extends ConsumerState<HeroAlbumCarousel> {
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(0);
  final PageController _pageController = PageController(viewportFraction: 0.85);

  @override
  void dispose() {
    _currentPage.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albums = widget.albums.take(5).toList();
    if (albums.isEmpty) return const SizedBox.shrink();
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (energy: s.energy, shadow: s.shadow),
      ),
    );

    return StaggerReveal(
      children: [
        Column(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).width > AfLayout.compact
                  ? 280
                  : 240,
              child: AnimatedBuilder(
                animation: _pageController,
                builder: (context, _) {
                  final currentPage = _pageController.hasClients
                      ? (_pageController.page ?? 0)
                      : 0.0;
                  return PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    itemCount: albums.length,
                    onPageChanged: (i) => _currentPage.value = i,
                    itemBuilder: (context, i) => _HeroCard(
                      album: albums[i],
                      index: i,
                      currentPage: currentPage,
                      spectral: spectral,
                    ),
                  );
                },
              ),
            ),
            if (albums.length > 1)
              ValueListenableBuilder<int>(
                valueListenable: _currentPage,
                builder: (context, page, _) => Padding(
                  padding: const EdgeInsets.only(top: AfSpacing.s12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      albums.length,
                      (i) => AnimatedContainer(
                        duration: AfDurations.bounce,
                        curve: AfCurves.easeOutBack,
                        margin: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s4,
                        ),
                        width: page == i ? 24 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          gradient: page == i
                              ? LinearGradient(
                                  colors: [spectral.energy, spectral.shadow],
                                )
                              : null,
                          color: page == i ? null : AfColors.surfaceMax,
                          borderRadius: AfRadii.borderPill,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Pre-computed saturation matrix (avoids alloc per frame) ──────────────

/// 40% saturation (s=0.4) — computed once at startup.
final Float64List _kSaturateLow = _buildSaturationMatrix(0.4);

Float64List _buildSaturationMatrix(double s) => Float64List.fromList([
  0.213 + 0.787 * s,
  0.715 - 0.715 * s,
  0.072 - 0.072 * s,
  0,
  0,
  0.213 - 0.213 * s,
  0.715 + 0.285 * s,
  0.072 - 0.072 * s,
  0,
  0,
  0.213 - 0.213 * s,
  0.715 - 0.715 * s,
  0.072 + 0.928 * s,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

/// Single hero album card with layered parallax + blur morph.
///
/// Extracted to its own widget so Flutter can diff + repaint independently
/// instead of rebuilding the entire carousel tree per frame.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.album,
    required this.index,
    required this.currentPage,
    required this.spectral,
  });

  final AfAlbum album;
  final int index;
  final double currentPage;
  final ({Color energy, Color shadow}) spectral;

  @override
  Widget build(BuildContext context) {
    final distance = (index - currentPage).abs();
    final clamped = distance.clamp(0.0, 1.0);
    final isCentered = clamped < 0.3;

    // ── Card-level transforms ──
    final scale = lerpDouble(1.0, 0.82, clamped)!;
    final opacity = lerpDouble(1.0, 0.55, clamped)!;
    final rotateYDeg = lerpDouble(0.0, 8.0, clamped)!;

    // ── Layered parallax ──
    final rawOffset = (index - currentPage) * 30;
    final artworkX = rawOffset * 1.2;
    final artworkScale = lerpDouble(1.05, 1.12, clamped)!;
    final artworkTranslateY = clamped > 0.3 ? -6.0 : 0.0;
    final metadataX = rawOffset * 0.8;
    final metadataTranslateY = clamped > 0.3 ? 10.0 : 0.0;
    final titleTranslateY = clamped > 0.3 ? 4.0 : 0.0;
    final artistTranslateY = clamped > 0.3 ? 8.0 : 0.0;

    final perspective = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateY(rotateYDeg * pi / 180);

    // ── Skip expensive filters when near-center ──
    final useBlur = !isCentered;
    final useDesat = !isCentered;

    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: 'Album: ${album.name} by ${album.artistName}',
        hint: 'Double tap to open album',
        child: FocusPressScale(
          ensureHitTarget: false,
          onTap: () => context.push('/album/${album.id}'),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Transform(
                alignment: Alignment.center,
                transform: perspective,
                child: ClipRRect(
                  borderRadius: AfRadii.borderXl,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── Artwork layer: 1.2× parallax ──
                      _ArtworkLayer(
                        url: album.imageUrl,
                        parallaxX: artworkX,
                        translateY: artworkTranslateY,
                        scale: artworkScale,
                        applyBlur: useBlur,
                        applyDesat: useDesat,
                      ),
                      // ── Spectral glow: active card only ──
                      if (isCentered)
                        Positioned(
                          left: -AfSpacing.s40,
                          bottom: -AfSpacing.s40,
                          width: AfLayout.heroGlowSize,
                          height: AfLayout.heroGlowSize,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  spectral.energy.withValues(alpha: 0.3),
                                  AfColors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      // ── Gradient scrim ──
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AfColors.transparent,
                                AfColors.surfaceCanvas.withValues(alpha: 0.95),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // ── Metadata layer: 0.8× parallax ──
                      Transform.translate(
                        offset: Offset(metadataX, metadataTranslateY),
                        child: Padding(
                          padding: const EdgeInsets.all(AfSpacing.s16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Spacer(),
                              Transform.translate(
                                offset: Offset(0, titleTranslateY),
                                child: Text(
                                  album.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AfTypography.titleLarge.copyWith(
                                    color: AfColors.textOnPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AfSpacing.s4),
                              Transform.translate(
                                offset: Offset(0, artistTranslateY),
                                child: Text(
                                  album.artistName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AfTypography.bodyLarge.copyWith(
                                    color: AfColors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AfSpacing.s16),
                              _PlayButton(album: album, spectral: spectral),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Artwork layer — conditionally wraps in blur + desaturation.
///
/// When [applyBlur] and [applyDesat] are false (center card),
/// skips the expensive ImageFilter wrappers entirely.
class _ArtworkLayer extends StatelessWidget {
  const _ArtworkLayer({
    required this.url,
    required this.parallaxX,
    required this.translateY,
    required this.scale,
    required this.applyBlur,
    required this.applyDesat,
  });

  final String? url;
  final double parallaxX;
  final double translateY;
  final double scale;
  final bool applyBlur;
  final bool applyDesat;

  @override
  Widget build(BuildContext context) {
    Widget child = Artwork(
      url: url,
      size: double.infinity,
      radius: AfRadii.borderNone,
      fit: BoxFit.cover,
    );

    // Only wrap in ColorFiltered when desaturation is needed.
    if (applyDesat) {
      child = ColorFiltered(
        colorFilter: ColorFilter.matrix(_kSaturateLow),
        child: child,
      );
    }

    // Only wrap in ImageFiltered when blur is needed.
    if (applyBlur) {
      child = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: AfRadii.borderXl,
      child: Transform.translate(
        offset: Offset(parallaxX, translateY),
        child: Transform.scale(scale: scale, child: child),
      ),
    );
  }
}

/// Play button with spectral gradient.
class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.album, required this.spectral});

  final AfAlbum album;
  final ({Color energy, Color shadow}) spectral;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FocusPressScale(
      ensureHitTarget: false,
      onTap: () async {
        final tracks = ref.read(playActionsProvider);
        final detail = await ref.read(albumDetailProvider(album.id).future);
        if (detail != null) {
          await tracks.playAlbum(detail.tracks);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s20,
          vertical: AfSpacing.s12,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [spectral.energy, spectral.energy.withValues(alpha: 0.7)],
          ),
          borderRadius: AfRadii.borderPill,
          boxShadow: [
            BoxShadow(
              color: spectral.energy.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.play,
              color: AfColors.textOnPrimary,
              size: 20,
            ),
            const SizedBox(width: AfSpacing.s8),
            Text(
              'Play',
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textOnPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
