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

        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              AfSpacing.s4,
              AfSpacing.s16,
              AfSpacing.s4,
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
