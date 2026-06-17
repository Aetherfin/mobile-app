import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import 'track_row_skeleton.dart';

/// Shimmer skeleton for the queue screen.
///
/// A simple list of track row placeholders.
class QueueSkeleton extends StatelessWidget {
  const QueueSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
      itemCount: 8,
      itemBuilder: (_, _) => const TrackRowSkeleton(),
    );
  }
}
