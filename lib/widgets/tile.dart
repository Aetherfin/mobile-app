import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';
import 'artwork.dart';
import 'press_scale.dart';

enum TileVariant { album, playlist, artist }

/// Square-artwork tile — used everywhere we render a horizontal-scroll
/// row of albums/playlists/artists, or in 2-col grids on Library / Search.
class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.title,
    required this.variant,
    this.subtitle,
    this.imageUrl,
    this.size = 152,
    this.onTap,
    this.onLongPress,
  });
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final double size;
  final TileVariant variant;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final art = Artwork(
      url: imageUrl,
      size: size,
      radius: BorderRadius.circular(AfRadii.lg),
    );

    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: variant == TileVariant.artist
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AfRadii.lg),
                border: Border.all(
                  color: AfColors.surfaceHigh.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: art,
            ),
            const SizedBox(height: AfSpacing.s8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: variant == TileVariant.artist
                  ? TextAlign.center
                  : TextAlign.left,
              style: AfTypography.titleSmall.copyWith(
                color: AfColors.textPrimary,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: variant == TileVariant.artist
                      ? TextAlign.center
                      : TextAlign.left,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Genre tile — artwork background with gradient overlay, or solid color fallback.
class GenreTile extends StatelessWidget {
  const GenreTile({
    super.key,
    required this.name,
    required this.tint,
    this.imageUrl,
    this.onTap,
    this.width = 152,
    this.height = 96,
  });
  final String name;
  final Color tint;
  final String? imageUrl;
  final VoidCallback? onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: tint, borderRadius: AfRadii.borderMd),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Artwork background (if available)
            if (imageUrl != null)
              Artwork(
                url: imageUrl,
                size: width > height ? width : height,
                radius: BorderRadius.zero,
                fit: BoxFit.cover,
              ),
            // Solid scrim for text readability
            Container(
              decoration: BoxDecoration(
                color: imageUrl != null
                    ? tint.withValues(alpha: 0.65)
                    : Colors.transparent,
              ),
            ),
            // Genre name
            Positioned(
              left: AfSpacing.s12,
              right: AfSpacing.s12,
              bottom: AfSpacing.s12,
              child: Text(
                name,
                style: AfTypography.titleSmall.copyWith(
                  color: AfColors.textOnPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
