import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../widgets/track_row.dart';

/// Playlist track list with drag-to-reorder and swipe-to-remove.
///
/// Wraps content in a surfaceRaised container with rounded top corners.
/// Returns [SizedBox.shrink] when tracks are empty — caller handles empty state.
class PlaylistTrackList extends StatelessWidget {
  const PlaylistTrackList({
    super.key,
    required this.tracks,
    required this.hasBackend,
    required this.activeId,
    required this.isBuffering,
    required this.activeAccent,
    required this.spectral,
    required this.onReorder,
    required this.confirmDismiss,
    required this.onDismissed,
    required this.onTap,
    required this.onLongPress,
  });

  final List<AfTrack> tracks;
  final bool hasBackend;
  final String? activeId;
  final bool isBuffering;
  final Color? activeAccent;
  final Color spectral;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Future<bool> Function(String title) confirmDismiss;
  final void Function(int index) onDismissed;
  final void Function(int index) onTap;
  final void Function(AfTrack track) onLongPress;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: AfColors.surfaceRaised,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AfRadii.xl),
          topRight: Radius.circular(AfRadii.xl),
        ),
      ),
      child: hasBackend ? _buildReorderable(context) : _buildStatic(context),
    );
  }

  Widget _buildReorderable(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      buildDefaultDragHandles: false,
      itemCount: tracks.length,
      onReorder: onReorder,
      itemBuilder: (context, i) =>
          _buildTrackTile(context, i, dismissible: true),
    );
  }

  Widget _buildStatic(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      itemCount: tracks.length,
      itemBuilder: _buildTrackTile,
    );
  }

  Widget _buildTrackTile(
    BuildContext context,
    int i, {
    bool dismissible = false,
  }) {
    final t = tracks[i];
    final isActive = t.id == activeId;

    Widget tile = Container(
      decoration: BoxDecoration(
        color: isActive ? spectral.withValues(alpha: 0.08) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AfSpacing.s2),
        child: Row(
          children: [
            // Overline track number.
            SizedBox(
              width: AfSpacing.s32,
              child: Text(
                '${i + 1}',
                style: AfTypography.overline.copyWith(
                  color: isActive ? spectral : AfColors.textDisabled,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: TrackRow(
                track: t,
                isActive: isActive,
                isBuffering: t.id == activeId && isBuffering,
                activeAccent: activeAccent,
                onTap: () => onTap(i),
                onLongPress: () => onLongPress(t),
              ),
            ),
            if (dismissible)
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AfSpacing.s8),
                  child: Icon(
                    LucideIcons.gripVertical,
                    color: AfColors.textDisabled,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (dismissible) {
      tile = Dismissible(
        key: ValueKey('${t.id}-$i'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: AfSpacing.s16),
          color: AfColors.semanticError.withValues(alpha: 0.25),
          child: const Icon(LucideIcons.trash2, color: AfColors.semanticError),
        ),
        confirmDismiss: (_) => confirmDismiss(t.title),
        onDismissed: (_) => onDismissed(i),
        child: tile,
      );
    }

    return tile;
  }
}
