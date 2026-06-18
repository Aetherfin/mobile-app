import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Collapsing header delegate for tab screens (Home, Library, Playlists, Profile).
///
/// Transitions from a large spectral-gradient title (expanded) to a compact
/// solid-color title (collapsed) as the user scrolls. An optional [action]
/// widget stays pinned on the right (cast, search, import, settings).
///
/// Usage:
/// ```dart
/// SliverPersistentHeader(
///   pinned: true,
///   delegate: CollapseHeader(
///     title: 'Library',
///     spectral: (primary: primary, secondary: secondary),
///     action: _SearchButton(onTap: ...),
///   ),
/// ),
/// ```
class CollapseHeader extends SliverPersistentHeaderDelegate {
  const CollapseHeader({
    required this.title,
    required this.spectral,
    this.action,
  });

  final String title;
  final ({Color primary, Color secondary}) spectral;

  /// Trailing button widget (cast, search, import M3U, settings).
  /// Pass `null` for no action.
  final Widget? action;

  static const double _expandedHeight = 80.0;
  static const double _collapsedHeight = 56.0;
  static const double _collapseThreshold = 100.0;

  @override
  double get minExtent => _collapsedHeight;
  @override
  double get maxExtent => _expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final t = (shrinkOffset / _collapseThreshold).clamp(0.0, 1.0);
    final bgColor = Color.lerp(
      AfColors.surfaceCanvas.withValues(alpha: 0.82),
      AfColors.surfaceBase,
      t,
    )!;

    return Container(
      color: bgColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AfSpacing.s16,
            AfSpacing.s8 * (1 - t),
            AfSpacing.s16,
            AfSpacing.s8,
          ),
          child: Row(
            children: [
              if (t < 1.0)
                Expanded(
                  child: Opacity(
                    opacity: 1.0 - t,
                    child: Transform.scale(
                      scale: 1.0 - t * 0.15,
                      alignment: Alignment.centerLeft,
                      child: ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [spectral.primary, spectral.secondary],
                        ).createShader(bounds),
                        child: Text(
                          title,
                          style: AfTypography.display.copyWith(
                            color: AfColors.textOnPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (t >= 1.0)
                Expanded(
                  child: Text(
                    title,
                    style: AfTypography.titleMedium.copyWith(
                      color: AfColors.textPrimary,
                    ),
                  ),
                ),
              ?action,
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant CollapseHeader oldDelegate) {
    return title != oldDelegate.title ||
        spectral.primary != oldDelegate.spectral.primary ||
        spectral.secondary != oldDelegate.spectral.secondary;
  }
}
