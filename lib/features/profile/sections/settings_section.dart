import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/section_header.dart';

/// Quick stats row — two stat chips for artists and playlists.
class QuickStatsRow extends StatelessWidget {
  const QuickStatsRow({
    super.key,
    required this.artistCount,
    required this.playlistCount,
  });

  final String artistCount;
  final String playlistCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: Row(
        children: [
          Expanded(
            child: StatChip(
              icon: LucideIcons.user,
              label: 'Artists',
              value: artistCount,
            ),
          ),
          const SizedBox(width: AfSpacing.s12),
          Expanded(
            child: StatChip(
              icon: LucideIcons.listMusic,
              label: 'Playlists',
              value: playlistCount,
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual stat chip — icon + value + label.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AfSpacing.s12),
      decoration: const BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: AfRadii.borderMd,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AfColors.accentPrimary),
          const SizedBox(width: AfSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AfTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header for the "Pinned" albums row.
class PinnedSectionHeader extends StatelessWidget {
  const PinnedSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AfSpacing.s16,
        AfSpacing.s24,
        AfSpacing.s16,
        0,
      ),
      child: SectionHeader(title: 'Pinned', uppercase: true),
    );
  }
}

/// Horizontal row of pinned/favorite albums.
class PinnedAlbumsRow extends StatelessWidget {
  const PinnedAlbumsRow({super.key, required this.albums});

  final List<AfAlbum> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return Container(
        height: AfLayout.profileSectionCompact,
        margin: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        decoration: const BoxDecoration(
          color: AfColors.surfaceBase,
          borderRadius: AfRadii.borderMd,
        ),
        child: Center(
          child: Text(
            'Heart albums to pin them here',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: AfLayout.profileSectionTall,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: albums.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AfSpacing.s12),
        itemBuilder: (context, i) {
          final a = albums[i];
          return Semantics(
            button: true,
            label: 'Go to album ${a.name}',
            child: GestureDetector(
              onTap: () => context.push('/album/${a.id}'),
              child: SizedBox(
                width: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Album artwork
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: const BoxDecoration(
                          borderRadius: AfRadii.borderSm,
                          color: AfColors.surfaceRaised,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Artwork(
                          url: a.imageUrl,
                          size: 120,
                          radius: AfRadii.borderSm,
                        ),
                      ),
                    ),
                    const SizedBox(height: AfSpacing.s8),

                    // Album name
                    Text(
                      a.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
