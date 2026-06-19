import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/audio/play_actions.dart';
import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/af_dialog.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/skeletons/home_skeleton.dart';
import '../../artist/artist_screen_widgets.dart' show startArtistRadio;
import '../../library/library_screen.dart' show SongsPill, songsPillProvider;

/// Expressive artist section — YouTube Music style.
///
/// Features:
/// - Hero artist card with gradient overlay and action buttons
/// - 3-column artist grid with gradient ring borders
/// - Spectral accent colors throughout
class ArtistsSection extends ConsumerWidget {
  const ArtistsSection({super.key, required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Spectral spectral = ref.watch(currentSpectralProvider);
    final artistsAsync = isLocal
        ? ref.watch(localArtistsProvider)
        : ref.watch(allArtistsProvider);

    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: AfSpacing.sectionGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'Your Artists',
            actionLabel: 'See all',
            onActionTap: () {
              ref.read(songsPillProvider.notifier).set(SongsPill.artists);
              context.go('/library');
            },
            spectralPrimary: spectral.primary,
          ),
        ),
        const SizedBox(height: AfSpacing.s12),
        artistsAsync.when(
          loading: () => const HomeArtistsSkeleton(),
          error: (e, _) => AsyncErrorView.compact(
            label: 'Couldn\'t load artists',
            error: e,
            height: AfLayout.artistCircleScrollHeight,
            onRetry: () => ref.invalidate(
              isLocal ? localArtistsProvider : allArtistsProvider,
            ),
          ),
          data: (artists) {
            if (artists.isEmpty) {
              return SizedBox(
                height: AfLayout.artistCircleScrollHeight,
                child: Center(
                  child: Text('No artists yet', style: AfTypography.bodySmall),
                ),
              );
            }

            // Hero artist (first) + scrollable circles (rest)
            final hero = artists.first;
            final rest = artists.skip(1).toList();

            return Column(
              children: [
                // Hero artist card
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16,
                  ),
                  child: Semantics(
                    button: true,
                    label: 'Artist: ${hero.name}',
                    hint: 'Double tap to open artist',
                    child: FocusPressScale(
                      ensureHitTarget: false,
                      onTap: () => context.push('/artist/${hero.id}'),
                      child: _HeroArtistCard(artist: hero, spectral: spectral),
                    ),
                  ),
                ),

                // Artist circles — horizontal scroll
                if (rest.isNotEmpty) ...[
                  const SizedBox(height: AfSpacing.s12),
                  SizedBox(
                    height: AfLayout.recentAlbumArtworkSize,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s16,
                      ),
                      itemCount: rest.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AfSpacing.s12),
                      itemBuilder: (context, i) {
                        final a = rest[i];
                        return Semantics(
                          key: ValueKey(a.id),
                          button: true,
                          label: 'Artist: ${a.name}',
                          hint: 'Double tap to open artist',
                          child: FocusPressScale(
                            ensureHitTarget: false,
                            onTap: () => context.push('/artist/${a.id}'),
                            child: _ExpressiveArtistCard(
                              name: a.name,
                              imageUrl: a.imageUrl,
                              spectral: spectral,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ]),
    );
  }
}

/// Hero artist card with gradient overlay and action buttons.
class _HeroArtistCard extends ConsumerWidget {
  const _HeroArtistCard({required this.artist, required this.spectral});

  final AfArtist artist;
  final Spectral spectral;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: AfLayout.albumGridMaxTileExtent,
      decoration: BoxDecoration(
        borderRadius: AfRadii.borderLg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[spectral.primary, spectral.secondary],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background artwork
          if (artist.imageUrl != null)
            Artwork(url: artist.imageUrl, size: 200, radius: AfRadii.borderLg),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AfColors.surfaceCanvas.withValues(alpha: 0.95),
                ],
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(AfSpacing.s16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  style: AfTypography.titleLarge.copyWith(
                    color: AfColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AfSpacing.s12),

                // Action buttons
                Row(
                  children: [
                    // Play button
                    _CircleButton(
                      icon: LucideIcons.play,
                      filled: true,
                      onTap: () => _playArtist(ref, shuffle: false),
                    ),
                    const SizedBox(width: AfSpacing.s12),

                    // Shuffle button
                    _CircleButton(
                      icon: LucideIcons.shuffle,
                      onTap: () => _playArtist(ref, shuffle: true),
                    ),
                    const SizedBox(width: AfSpacing.s12),

                    // More button
                    _CircleButton(
                      icon: LucideIcons.moreHorizontal,
                      onTap: () => _showMoreMenu(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playArtist(WidgetRef ref, {required bool shuffle}) async {
    await HapticFeedback.mediumImpact();
    final topTracks = ref.read(artistTopTracksProvider(artist.id));
    final tracks = topTracks.value;
    if (tracks == null || tracks.isEmpty) return;

    final playActions = ref.read(playActionsProvider);
    if (shuffle) {
      await playActions.playQueue(tracks);
      final svc = ref.read(playerServiceProvider);
      if (!svc.isShuffleEnabled) {
        await svc.setAfShuffleMode(true);
      }
    } else {
      await playActions.playQueue(tracks);
    }
  }

  void _showMoreMenu(BuildContext context, WidgetRef ref) {
    unawaited(HapticFeedback.mediumImpact());
    showBlurDialog<void>(
      context: context,
      builder: (_, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
            ),
            child: Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AfTypography.titleSmall,
            ),
          ),
          const SizedBox(height: AfSpacing.s8),
          const Divider(height: 1, color: AfColors.surfaceHigh),
          _MenuItem(
            icon: LucideIcons.play,
            label: 'Play',
            onTap: () {
              dismiss();
              _playArtist(ref, shuffle: false);
            },
          ),
          _MenuItem(
            icon: LucideIcons.shuffle,
            label: 'Shuffle',
            onTap: () {
              dismiss();
              _playArtist(ref, shuffle: true);
            },
          ),
          _MenuItem(
            icon: LucideIcons.radio,
            label: 'Artist Radio',
            onTap: () {
              dismiss();
              startArtistRadio(context, ref, artist.name, artist.id);
            },
          ),
          _MenuItem(
            icon: LucideIcons.user,
            label: 'Go to artist',
            onTap: () {
              dismiss();
              context.push('/artist/${artist.id}');
            },
          ),
          const SizedBox(height: AfSpacing.s8),
        ],
      ),
    );
  }
}

/// Expressive artist card with gradient ring border.
class _ExpressiveArtistCard extends StatelessWidget {
  const _ExpressiveArtistCard({
    required this.name,
    this.imageUrl,
    required this.spectral,
  });

  final String name;
  final String? imageUrl;
  final Spectral spectral;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Circular artwork with gradient border
        Container(
          width: AfLayout.artistCircleSize,
          height: AfLayout.artistCircleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [spectral.primary, spectral.secondary],
            ),
          ),
          padding: const EdgeInsets.all(AfSpacing.s4),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AfColors.surfaceCanvas,
            ),
            child: ClipOval(
              child: imageUrl != null
                  ? Artwork(url: imageUrl, size: 94, radius: AfRadii.borderPill)
                  : const Center(
                      child: Icon(
                        LucideIcons.user,
                        size: 32,
                        color: AfColors.textTertiary,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),

        // Name
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AfTypography.bodySmall.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final label = filled
        ? 'Play'
        : (icon == LucideIcons.shuffle ? 'Shuffle' : 'More options');
    return Semantics(
      button: true,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AfSpacing.minHitTarget,
          minHeight: AfSpacing.minHitTarget,
        ),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AfSpacing.s8),
            decoration: BoxDecoration(
              color: filled ? AfColors.textPrimary : Colors.transparent,
              shape: BoxShape.circle,
              border: filled
                  ? null
                  : Border.all(color: AfColors.textSecondary, width: 1),
            ),
            child: Icon(
              icon,
              size: 20,
              color: filled ? AfColors.surfaceCanvas : AfColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PressScale(
        onTap: onTap,
        child: InkWell(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
              vertical: AfSpacing.s12,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AfColors.textPrimary),
                const SizedBox(width: AfSpacing.s12),
                Text(label, style: AfTypography.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
