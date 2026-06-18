import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../utils/log.dart';
import '../../widgets/artwork.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';

/// Builds the parallax hero artwork for the album screen.
Widget buildAlbumHeroArtwork({
  required ValueNotifier<double> scrollOffset,
  required double heroHeight,
  required double width,
  required String? imageUrl,
}) {
  return ValueListenableBuilder<double>(
    valueListenable: scrollOffset,
    builder: (context, offset, _) {
      final scaleProgress = (offset / heroHeight).clamp(0.0, 1.0);
      final scale = 1.0 - (scaleProgress * 0.08);

      return Positioned(
        top: -offset * 0.5,
        left: 0,
        right: 0,
        child: SizedBox(
          height: heroHeight,
          child: Transform.scale(
            scale: scale,
            child: ShaderMask(
              shaderCallback: (rect) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.6, 1.0],
                  colors: [AfColors.textOnPrimary, Colors.transparent],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: Artwork(
                url: imageUrl,
                size: width,
                height: heroHeight,
                radius: BorderRadius.zero,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class AlbumActionRow extends ConsumerStatefulWidget {
  const AlbumActionRow({
    required this.onPlay,
    required this.onMore,
    required this.album,
    required this.tracks,
    super.key,
  });
  final VoidCallback onPlay;
  final VoidCallback onMore;
  final AfAlbum album;
  final List<AfTrack> tracks;

  @override
  ConsumerState<AlbumActionRow> createState() => _AlbumActionRowState();
}

class _AlbumActionRowState extends ConsumerState<AlbumActionRow> {
  late bool _isFavorite;
  bool _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.album.isFavorite;
  }

  @override
  void didUpdateWidget(covariant AlbumActionRow old) {
    super.didUpdateWidget(old);
    if (!_favoriteBusy && old.album.isFavorite != widget.album.isFavorite) {
      _isFavorite = widget.album.isFavorite;
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;
    setState(() {
      _favoriteBusy = true;
      _isFavorite = !_isFavorite;
    });
    try {
      await backend.setFavorite(widget.album.id, _isFavorite);
      afLog(
        'data',
        'albumFavorite source=live '
            'id=${widget.album.id} isFavorite=$_isFavorite',
      );
      ref.invalidate(favoriteAlbumsProvider);
      ref.invalidate(albumDetailProvider(widget.album.id));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _isFavorite = !_isFavorite);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayError(e, prefix: 'Could not update favorite')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Action icons row ──────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconCircle(
              icon: LucideIcons.heart,
              color: _isFavorite ? AfColors.semanticError : null,
              onTap: _toggleFavorite,
            ),
            const SizedBox(width: AfSpacing.s12),
            IconCircle(icon: LucideIcons.ellipsis, onTap: widget.onMore),
          ],
        ),
        const SizedBox(height: AfSpacing.s16),
        // ── Play All + Shuffle ────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.onPlay,
                icon: const Icon(
                  LucideIcons.play,
                  color: AfColors.textOnPrimary,
                  size: AfIconSizes.sm,
                ),
                label: const Text('Play All'),
              ),
            ),
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  final shuffled = List<AfTrack>.from(widget.tracks)..shuffle();
                  ref.read(playActionsProvider).playQueue(shuffled);
                },
                style: AfTypography.outlinedAction,
                icon: const Icon(LucideIcons.shuffle, size: AfIconSizes.sm),
                label: const Text('Shuffle'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class IconCircle extends StatelessWidget {
  const IconCircle({
    required this.icon,
    required this.onTap,
    this.color,
    super.key,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AfColors.surfaceRaised,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: AfIconSizes.sm,
          color: color ?? AfColors.textPrimary,
        ),
      ),
    );
  }
}

/// Track row wrapper that watches playback state providers internally.
/// Prevents the entire AlbumScreen root from rebuilding on every
/// buffering/spectral change — only this leaf widget rebuilds.
class AlbumTrackRowItem extends ConsumerWidget {
  const AlbumTrackRowItem({
    required this.track,
    required this.index,
    required this.activeId,
    required this.tracks,
    super.key,
  });

  final AfTrack track;
  final int index;
  final String? activeId;
  final List<AfTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );
    final isActive = track.id == activeId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: TrackRow(
        track: track,
        leadingNumber: index + 1,
        isActive: isActive,
        isBuffering: isActive && isBuffering,
        activeAccent: activeAccent,
        onTap: () =>
            ref.read(playActionsProvider).playQueue(tracks, startIndex: index),
        onLongPress: () => showTrackContextMenu(context, ref, track),
      ),
    );
  }
}

class AlbumWikiPanel extends ConsumerStatefulWidget {
  const AlbumWikiPanel({
    required this.wiki,
    this.listeners,
    this.playCount,
    super.key,
  });
  final String wiki;
  final String? listeners;
  final String? playCount;

  @override
  ConsumerState<AlbumWikiPanel> createState() => _AlbumWikiPanelState();
}

class _AlbumWikiPanelState extends ConsumerState<AlbumWikiPanel> {
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
    final cleanText = _cleanHtml(widget.wiki);
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
          Text('About this Album', style: AfTypography.titleSmall),
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
          ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AfSpacing.minHitTarget,
              minHeight: AfSpacing.minHitTarget,
            ),
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Semantics(
                button: true,
                label: _expanded
                    ? 'Collapse album description'
                    : 'Expand album description',
                child: Text(
                  _expanded ? 'Show less' : 'Read more',
                  style: AfTypography.bodySmall.copyWith(
                    color: spectral,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
