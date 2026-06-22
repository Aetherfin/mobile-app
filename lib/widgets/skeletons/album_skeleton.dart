import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../skeleton.dart';
import 'track_row_skeleton.dart';

/// Shimmer skeleton for the album detail screen.
///
/// Full-width artwork block, title/subtitle bars, divider, and track rows.
class AlbumSkeleton extends StatelessWidget {
  const AlbumSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return SingleChildScrollView(
      child: Column(
        children: [
          SkeletonBlock(
            width: screenWidth,
            height: screenWidth,
            borderRadius: AfRadii.borderNone,
          ),
          const SizedBox(height: AfSpacing.s16),
          const Padding(
            padding: AfSpacing.pageHorizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Album title
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: SkeletonBar(height: 20),
                ),
                SizedBox(height: AfSpacing.s8),
                // Artist name
                FractionallySizedBox(
                  widthFactor: 0.4,
                  child: SkeletonBar(height: 16),
                ),
                SizedBox(height: AfSpacing.s16),
                Divider(color: AfColors.surfaceHigh),
                SizedBox(height: AfSpacing.s8),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
