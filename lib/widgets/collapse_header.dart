import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Fixed collapsing header for tab screens (Home, Library, Playlists, Profile).
///
/// Renders above the scroll view — content never scrolls behind it.
/// Expands/collapses based on scroll offset.
class CollapseHeader extends StatelessWidget {
  const CollapseHeader({
    super.key,
    required this.title,
    required this.spectral,
    required this.scrollController,
    this.action,
  });

  final String title;
  final ({Color primary, Color secondary}) spectral;
  final ScrollController scrollController;
  final Widget? action;

  static const double _collapseThreshold = 80.0;

  static const double _expandedHeight = 80.0;
  static const double _collapsedHeight = 44.0;

  double _getCollapseProgress() {
    if (!scrollController.hasClients) return 0.0;
    return (scrollController.offset / _collapseThreshold).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scrollController,
      builder: (context, _) {
        final t = _getCollapseProgress();
        final fontSize =
            AfTypography.display.fontSize! -
            t *
                (AfTypography.display.fontSize! -
                    AfTypography.titleMedium.fontSize!);
        final iconScale = fontSize / AfTypography.display.fontSize!;
        final barHeight = lerpDouble(_expandedHeight, _collapsedHeight, t)!;
        final verticalPad = lerpDouble(AfSpacing.s8, AfSpacing.s2, t)!;

        return SizedBox(
          height: barHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AfSpacing.s16,
              verticalPad,
              AfSpacing.s16,
              verticalPad,
            ),
            child: Row(
              children: [
                Expanded(
                  child: ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [spectral.primary, spectral.secondary],
                    ).createShader(bounds),
                    child: Text(
                      title,
                      style: AfTypography.display.copyWith(
                        fontSize: fontSize,
                        color: AfColors.textOnPrimary,
                      ),
                    ),
                  ),
                ),
                if (action != null)
                  Transform.scale(scale: iconScale, child: action),
              ],
            ),
          ),
        );
      },
    );
  }
}
