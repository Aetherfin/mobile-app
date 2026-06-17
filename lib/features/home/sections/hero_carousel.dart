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

/// Swipeable carousel of hero album cards with a dot indicator.
class HeroAlbumCarousel extends ConsumerStatefulWidget {
  const HeroAlbumCarousel({super.key, required this.albums});
  final List<AfAlbum> albums;

  @override
  ConsumerState<HeroAlbumCarousel> createState() => _HeroAlbumCarouselState();
}

class _HeroAlbumCarouselState extends ConsumerState<HeroAlbumCarousel> {
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(0);
  final PageController _pageController = PageController(viewportFraction: 0.92);

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
              height: 240,
              child: PageView.builder(
                controller: _pageController,
                itemCount: albums.length,
                onPageChanged: (i) => _currentPage.value = i,
                itemBuilder: (context, i) {
                  final album = albums[i];
                  return Semantics(
                    button: true,
                    label: 'Album: ${album.name} by ${album.artistName}',
                    hint: 'Double tap to open album',
                    child: FocusPressScale(
                      ensureHitTarget: false,
                      onTap: () => context.push('/album/${album.id}'),
                      child: Container(
                        decoration: const BoxDecoration(
                          borderRadius: AfRadii.borderXl,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Artwork
                            Artwork(
                              url: album.imageUrl,
                              size: double.infinity,
                              radius: BorderRadius.zero,
                              fit: BoxFit.cover,
                            ),
                            // Spectral glow accent
                            Positioned(
                              left: -40,
                              bottom: -40,
                              width: 160,
                              height: 160,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      spectral.energy.withValues(alpha: 0.3),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Gradient scrim for text readability
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      AfColors.surfaceCanvas.withValues(
                                        alpha: 0.95,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Content
                            Padding(
                              padding: const EdgeInsets.all(AfSpacing.s16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Spacer(),
                                  // Album title — dramatic sizing
                                  Text(
                                    album.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AfTypography.titleLarge.copyWith(
                                      color: AfColors.textOnPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: AfSpacing.s4),
                                  Text(
                                    album.artistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AfTypography.bodyLarge.copyWith(
                                      color: AfColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: AfSpacing.s16),
                                  // Play button with warm glow
                                  FocusPressScale(
                                    ensureHitTarget: false,
                                    onTap: () async {
                                      final tracks = ref.read(
                                        playActionsProvider,
                                      );
                                      final detail = await ref.read(
                                        albumDetailProvider(album.id).future,
                                      );
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
                                          colors: [
                                            spectral.energy,
                                            spectral.energy.withValues(
                                              alpha: 0.7,
                                            ),
                                          ],
                                        ),
                                        borderRadius: AfRadii.borderPill,
                                        boxShadow: [
                                          BoxShadow(
                                            color: spectral.energy.withValues(
                                              alpha: 0.35,
                                            ),
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
                                            style: AfTypography.bodyMedium
                                                .copyWith(
                                                  color: AfColors.textOnPrimary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Dot indicators
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
                        duration: AfDurations.quick,
                        curve: AfCurves.easeStandard,
                        margin: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s4,
                        ),
                        width: page == i ? 20 : 6,
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
