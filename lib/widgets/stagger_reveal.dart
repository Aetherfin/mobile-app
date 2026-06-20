import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Wraps [children] in staggered fade+slide-up reveal animations using
/// [FadeInUp] from `animate_do`. Each child enters sequentially with a
/// per-item delay defined by [stagger]. Items beyond [maxStaggered] share
/// the last stagger slot so the total reveal time stays bounded.
class StaggerReveal extends StatelessWidget {
  const StaggerReveal({
    super.key,
    required this.children,
    this.stagger = AfStagger.perItem,
    this.maxStaggered = AfStagger.maxStaggered,
  });

  /// Widgets to reveal in order.
  final List<Widget> children;

  /// Delay between each child's entrance.
  final Duration stagger;

  /// Max index that gets a unique delay; items beyond share the last slot.
  final int maxStaggered;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++)
          FadeInUp(
            duration: AfDurations.standard,
            delay: stagger * (i < maxStaggered ? i : maxStaggered),
            curve: AfCurves.easeEmphasized,
            from: 24,
            child: children[i],
          ),
      ],
    );
  }
}
