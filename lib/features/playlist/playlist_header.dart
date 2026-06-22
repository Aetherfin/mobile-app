import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/press_scale.dart';

/// Playlist hero header with artwork, name, and stat badges.
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({
    super.key,
    required this.playlist,
    required this.tracks,
    required this.primaryColor,
  });
  final AfPlaylist playlist;
  final List<AfTrack> tracks;
  final Color primaryColor;

  String _formatDuration(Duration d) {
    final totalMinutes = d.inMinutes;
    if (totalMinutes < 1) return '${d.inSeconds}s';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    final seconds = d.inSeconds % 60;
    return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final totalDuration = tracks.fold<Duration>(
      Duration.zero,
      (sum, t) => sum + t.duration,
    );
    final artistCount = tracks.map((t) => t.artistName).toSet().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        AfSpacing.s8,
        AfSpacing.s16,
        AfSpacing.s16,
      ),
      child: Column(
        children: [
          // Centered hero artwork 128dp.
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              borderRadius: AfRadii.borderXl,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primaryColor.withValues(alpha: 0.3),
                  AfColors.surfaceLow,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.15),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(LucideIcons.listMusic, color: primaryColor, size: 56),
          ),
          const SizedBox(height: AfSpacing.s16),

          // Centered playlist name — serif headline.
          Text(
            playlist.name,
            style: AfTypography.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AfSpacing.s12),

          // Mono stat badges.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatBadge(
                label:
                    '${tracks.length} ${tracks.length == 1 ? "track" : "tracks"}',
              ),
              const SizedBox(width: AfSpacing.s8),
              _StatBadge(label: _formatDuration(totalDuration)),
              const SizedBox(width: AfSpacing.s8),
              _StatBadge(
                label:
                    '$artistCount ${artistCount == 1 ? "artist" : "artists"}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Play / Shuffle action row for the playlist header.
class PlaylistActionRow extends StatelessWidget {
  const PlaylistActionRow({
    super.key,
    required this.tracks,
    required this.onPlay,
    required this.onShuffle,
  });
  final List<AfTrack> tracks;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: _SegmentedControl(
        onLeft: tracks.isEmpty ? null : onPlay,
        onRight: tracks.isEmpty ? null : onShuffle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Design-system widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Mono stat badge used in the playlist hero header.
class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s12,
        vertical: AfSpacing.s4,
      ),
      decoration: const BoxDecoration(
        color: AfColors.surfaceLow,
        borderRadius: AfRadii.borderSm,
        border: Border.fromBorderSide(BorderSide(color: AfColors.surfaceHigh)),
      ),
      child: Text(
        label,
        style: AfTypography.monoSmall.copyWith(color: AfColors.textTertiary),
      ),
    );
  }
}

/// Play / Shuffle segmented control.
class _SegmentedControl extends ConsumerStatefulWidget {
  const _SegmentedControl({required this.onLeft, required this.onRight});
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  @override
  ConsumerState<_SegmentedControl> createState() => _SegmentedControlState();
}

class _SegmentedControlState extends ConsumerState<_SegmentedControl> {
  bool _isRightSelected = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AfColors.surfaceLow,
        borderRadius: AfRadii.borderPill,
        border: Border.fromBorderSide(BorderSide(color: AfColors.surfaceHigh)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(child: _buildOption(isRight: false)),
          Expanded(child: _buildOption(isRight: true)),
        ],
      ),
    );
  }

  Widget _buildOption({required bool isRight}) {
    final isSelected = _isRightSelected == isRight;
    final label = isRight ? 'Shuffle' : 'Play';
    final icon = isRight ? LucideIcons.shuffle : LucideIcons.play;
    final onTap = isRight ? widget.onRight : widget.onLeft;

    return AnimatedContainer(
      duration: AfDurations.quick,
      curve: AfCurves.easeStandard,
      decoration: BoxDecoration(
        color: isSelected
            ? ref.read(currentSpectralProvider).primary
            : AfColors.transparent,
      ),
      child: PressScale(
        ensureHitTarget: false,
        onTap: onTap == null
            ? null
            : () {
                setState(() => _isRightSelected = isRight);
                onTap();
              },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? AfColors.surfaceCanvas
                  : AfColors.textTertiary,
            ),
            const SizedBox(width: AfSpacing.s8),
            Text(
              label,
              style: AfTypography.bodyMedium.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AfColors.surfaceCanvas
                    : AfColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
