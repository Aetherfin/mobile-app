import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../skeleton.dart';
import 'track_row_skeleton.dart';

/// Shimmer skeleton for the playlist detail screen.
///
/// Wide artwork header, title/subtitle bars, and track rows.
class PlaylistSkeleton extends StatelessWidget {
  const PlaylistSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return SingleChildScrollView(
      child: Column(
        children: [
          SkeletonBlock(
            width: screenWidth,
            height: AfLayout.albumGridMaxTileExtent,
            borderRadius: AfRadii.borderNone,
          ),
          const SizedBox(height: AfSpacing.s16),
          const Padding(
            padding: AfSpacing.pageHorizontal,
            child: Column(
              children: [
                // Playlist title
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: SkeletonBar(height: 22),
                ),
                SizedBox(height: AfSpacing.s8),
                // Playlist subtitle
                FractionallySizedBox(
                  widthFactor: 0.3,
                  child: SkeletonBar(height: 14),
                ),
                SizedBox(height: AfSpacing.s16),
                // Track rows
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
