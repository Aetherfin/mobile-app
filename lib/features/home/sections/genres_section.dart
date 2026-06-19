import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../utils/color_parse.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/skeleton.dart';
import '../../library/library_screen.dart' show SongsPill, songsPillProvider;

/// Expressive genres section — YouTube Music style.
///
/// Features:
/// - 2-column grid with bold gradient cards
/// - Genre-specific icons
/// - Spectral accent colors
class GenresSection extends ConsumerWidget {
  const GenresSection({super.key, required this.isLocal});
  final bool isLocal;

  // Genre icon mapping
  static const Map<String, IconData> _genreIcons = {
    'electronic': LucideIcons.zap,
    'rock': LucideIcons.guitar,
    'hip hop': LucideIcons.mic,
    'rap': LucideIcons.mic,
    'pop': LucideIcons.star,
    'jazz': LucideIcons.music,
    'classical': LucideIcons.music2,
    'r&b': LucideIcons.heart,
    'rnb': LucideIcons.heart,
    'country': LucideIcons.sun,
    'metal': LucideIcons.flame,
    'indie': LucideIcons.leaf,
    'alternative': LucideIcons.compass,
    'soul': LucideIcons.sunrise,
    'funk': LucideIcons.sparkles,
    'reggae': LucideIcons.treePalm,
    'blues': LucideIcons.cloudRain,
    'folk': LucideIcons.mountain,
    'ambient': LucideIcons.cloud,
    'techno': LucideIcons.circuitBoard,
    'house': LucideIcons.home,
    'disco': LucideIcons.disc,
  };

  // Genre gradients are now in AfGenreColors (design_tokens/colors.dart).

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectralPrimary = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final genresAsync = isLocal
        ? ref.watch(localGenresProvider)
        : ref.watch(allGenresProvider);

    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: AfSpacing.sectionGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'Browse Genres',
            actionLabel: 'See all',
            onActionTap: () {
              ref.read(songsPillProvider.notifier).set(SongsPill.genres);
              context.go('/library');
            },
            spectralPrimary: spectralPrimary,
          ),
        ),
        const SizedBox(height: AfSpacing.s12),
        genresAsync.when(
          data: (genres) {
            if (genres.isEmpty) {
              return SizedBox(
                height: AfLayout.genreCardHeight,
                child: Center(
                  child: Text('No genres yet', style: AfTypography.bodySmall),
                ),
              );
            }

            // Show first 6 genres in 2-column grid
            final displayGenres = genres.take(6).toList();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: AfLayout.genreGridMaxTileExtent,
                  childAspectRatio: 1.2,
                  mainAxisSpacing: AfSpacing.s8,
                  crossAxisSpacing: AfSpacing.s8,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayGenres.length,
                itemBuilder: (context, index) {
                  final g = displayGenres[index];
                  final tint = parseHexColor(g.tint);
                  final gradient =
                      AfGenreColors.of(g.name) ??
                      [tint, tint.withValues(alpha: 0.7)];
                  final icon =
                      _genreIcons[g.name.toLowerCase()] ?? LucideIcons.music;

                  return _ExpressiveGenreCard(
                    key: ValueKey(g.name),
                    label: g.name,
                    icon: icon,
                    gradient: gradient,
                    onTap: () =>
                        context.push('/genre/${Uri.encodeComponent(g.name)}'),
                  );
                },
              ),
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: AfLayout.genreGridMaxTileExtent,
                childAspectRatio: 1.2,
                mainAxisSpacing: AfSpacing.s8,
                crossAxisSpacing: AfSpacing.s8,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 6,
              itemBuilder: (_, i) => SkeletonBlock(
                key: ValueKey('genre-skel-$i'),
                width: 160,
                height: 80,
                borderRadius: AfRadii.borderMd,
              ),
            ),
          ),
          error: (e, _) => AsyncErrorView.compact(
            label: 'Couldn\'t load genres',
            error: e,
            height: AfLayout.genreCardHeight,
            onRetry: () => ref.invalidate(
              isLocal ? localGenresProvider : allGenresProvider,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Expressive genre card with bold gradient and icon.
class _ExpressiveGenreCard extends StatelessWidget {
  const _ExpressiveGenreCard({
    super.key,
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Genre: $label',
      hint: 'Double tap to open genre',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AfSpacing.s16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            borderRadius: AfRadii.borderMd,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: AfColors.textOnPrimary),
              const SizedBox(height: AfSpacing.s8),
              Text(
                label,
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textOnPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
