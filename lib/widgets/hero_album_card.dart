import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import 'artwork.dart';
import 'press_scale.dart';

/// Album card for the home screen carousel with artwork, title, and play pill.
class HeroAlbumCard extends StatelessWidget {
  const HeroAlbumCard({
    super.key,
    required this.album,
    this.pillLabel = 'New Album',
    this.onTap,
    this.onPlay,
  });
  final AfAlbum album;
  final String pillLabel;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final hasArt = album.imageUrl != null && album.imageUrl!.isNotEmpty;

    return FocusPressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Album: ${album.name} by ${album.artistName}',
        hint: 'Double tap to open album',
        child: Container(
          constraints: const BoxConstraints(minHeight: 192),
          margin: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          decoration: BoxDecoration(
            borderRadius: AfRadii.borderLg,
            color: hasArt ? null : AfColors.surfaceRaised,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (hasArt)
                Positioned.fill(
                  child: Artwork(
                    url: album.imageUrl,
                    size: double.infinity,
                    fit: BoxFit.cover,
                    radius: AfRadii.borderNone,
                  ),
                ),
              // Gradient scrim
              Positioned.fill(
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          AfColors.surfaceCanvas.withValues(alpha: 0.92),
                          AfColors.surfaceCanvas.withValues(alpha: 0.40),
                          AfColors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s16,
                  AfSpacing.s16,
                  AfSpacing.s16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s8,
                        vertical: AfSpacing.s4,
                      ),
                      decoration: BoxDecoration(
                        color: AfColors.surfaceCanvas.withValues(alpha: 0.55),
                        borderRadius: AfRadii.borderPill,
                      ),
                      child: Text(
                        pillLabel,
                        style: AfTypography.caption.copyWith(
                          color: AfColors.textOnPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AfSpacing.s12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          album.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AfTypography.titleLarge.copyWith(
                            color: AfColors.textOnPrimary,
                          ),
                        ),
                        const SizedBox(height: AfSpacing.s2),
                        Text(
                          album.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.textOnPrimary.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _PlayPill(albumName: album.name, onTap: onPlay),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayPill extends StatelessWidget {
  const _PlayPill({required this.albumName, this.onTap});
  final String albumName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FocusPressScale(
        ensureHitTarget: false,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s16,
            vertical: AfSpacing.s8,
          ),
          decoration: const BoxDecoration(
            color: AfColors.textOnPrimary,
            borderRadius: AfRadii.borderPill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.play,
                color: AfColors.surfaceCanvas,
                size: 18,
              ),
              const SizedBox(width: AfSpacing.s4),
              Text(
                'Play',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.surfaceCanvas,
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
