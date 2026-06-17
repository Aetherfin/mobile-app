import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../state/radio_providers.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/artwork.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_row.dart';
import '../../widgets/stagger_reveal.dart';

class ArtistActionRow extends StatelessWidget {
  const ArtistActionRow({
    super.key,
    required this.onPlay,
    required this.onRadio,
  });
  final VoidCallback? onPlay;
  final VoidCallback? onRadio;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onPlay,
            icon: const Icon(
              LucideIcons.play,
              color: AfColors.textOnPrimary,
              size: AfIconSizes.sm,
            ),
            label: const Text('Play'),
          ),
        ),
        if (onRadio != null) ...[
          const SizedBox(width: AfSpacing.s12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRadio,
              style: AfTypography.outlinedAction,
              icon: const Icon(LucideIcons.radio, size: 20),
              label: const Text('Artist Radio'),
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> startArtistRadio(
  BuildContext context,
  WidgetRef ref,
  String artistName,
  String artistId,
) async {
  final spectral = ref.read(currentSpectralProvider);
  unawaited(
    showBlurDialog(
      context: context,
      barrierDismissible: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spectral.primary,
            ),
          ),
          const SizedBox(width: AfSpacing.s16),
          Text(
            'Generating Artist Radio...',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );

  try {
    final generator = ref.read(radioGeneratorProvider);
    final queue = await generator.generateArtistRadio(artistName, artistId);

    if (context.mounted) context.pop(); // Close loading HUD

    if (queue.isNotEmpty) {
      await ref.read(playActionsProvider).playQueue(queue, startIndex: 0);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate similar artist radio queue.'),
          ),
        );
      }
    }
  } on Exception catch (e) {
    if (context.mounted) context.pop(); // Close loading HUD
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start radio: $e')));
    }
  }
}

/// Top songs slivers for the artist screen.
/// Strip play counts and subscriber counts from carousel subtitles.
/// "2Pac · 5.2M subscribers" → "2Pac"
/// "Album · 975K plays" → "Album"
List<Widget> buildArtistTopSongsSlivers({
  required List<AfTrack> topTracks,
  required String? activeId,
  required bool isBuffering,
  required Color activeAccent,
  required void Function(int index) onTap,
  required void Function(AfTrack track) onLongPress,
  VoidCallback? onMoreTap,
}) {
  if (topTracks.isEmpty) return [];
  final displayedTracks = topTracks.take(5).toList();
  return [
    const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s32)),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.gutterGenerous,
        ),
        child: SectionHeader(
          title: 'Top Songs',
          actionLabel: onMoreTap != null ? 'More' : null,
          onActionTap: onMoreTap,
          spectralPrimary: activeAccent,
        ),
      ),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s8)),
    SliverToBoxAdapter(
      child: StaggerReveal(
        children: [
          for (var i = 0; i < displayedTracks.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: TrackRow(
                track: displayedTracks[i],
                leadingNumber: i + 1,
                isActive: displayedTracks[i].id == activeId,
                isBuffering: displayedTracks[i].id == activeId && isBuffering,
                activeAccent: activeAccent,
                onTap: () => onTap(i),
                onLongPress: () => onLongPress(displayedTracks[i]),
              ),
            ),
        ],
      ),
    ),
  ];
}

/// Discography slivers for the artist screen.
List<Widget> buildArtistDiscographySlivers(
  List<AfAlbum> albums, {
  VoidCallback? onMoreTap,
  Color? activeAccent,
}) {
  if (albums.isEmpty) return const [];
  final displayedAlbums = albums.take(5).toList();
  return [
    const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s24)),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.gutterGenerous,
        ),
        child: SectionHeader(
          title: 'Discography',
          actionLabel: onMoreTap != null && albums.length > 5 ? 'More' : null,
          onActionTap: onMoreTap,
          spectralPrimary: activeAccent,
        ),
      ),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s8)),
    SliverToBoxAdapter(
      child: SizedBox(
        height: 240,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          itemCount: displayedAlbums.length,
          separatorBuilder: (context, index) =>
              const SizedBox(width: AfSpacing.s12),
          itemBuilder: (context, i) {
            final a = displayedAlbums[i];
            return PressScale(
              onTap: () => context.push('/album/${a.id}'),
              child: SizedBox(
                width: 152,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Artwork(
                      url: a.imageUrl,
                      size: 152,
                      radius: BorderRadius.zero,
                    ),
                    const SizedBox(height: AfSpacing.s8),
                    Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      a.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  ];
}

class ArtistBiographyPanel extends ConsumerStatefulWidget {
  const ArtistBiographyPanel({
    super.key,
    required this.bio,
    this.listeners,
    this.playCount,
  });
  final String bio;
  final String? listeners;
  final String? playCount;

  @override
  ConsumerState<ArtistBiographyPanel> createState() =>
      _ArtistBiographyPanelState();
}

class _ArtistBiographyPanelState extends ConsumerState<ArtistBiographyPanel> {
  bool _expanded = false;

  String _cleanHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  String _formatNumber(String? numStr) {
    if (numStr == null) return '';
    final n = int.tryParse(numStr);
    if (n == null) return numStr;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final cleanText = _cleanHtml(widget.bio);
    if (cleanText.isEmpty) return const SizedBox();

    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final stats = <String>[];
    if (widget.listeners != null) {
      stats.add('${_formatNumber(widget.listeners)} listeners');
    }
    if (widget.playCount != null) {
      stats.add('${_formatNumber(widget.playCount)} plays');
    }

    return Container(
      padding: const EdgeInsets.all(AfSpacing.s16),
      decoration: const BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: AfRadii.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Biography', style: AfTypography.titleSmall),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: AfSpacing.s4),
            Text(
              stats.join(' · '),
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: AfSpacing.s12),
          Text(
            cleanText,
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AfSpacing.s8),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Semantics(
              button: true,
              label: _expanded ? 'Collapse biography' : 'Expand biography',
              child: Text(
                _expanded ? 'Show less' : 'Read more',
                style: AfTypography.bodySmall.copyWith(
                  color: spectral,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
