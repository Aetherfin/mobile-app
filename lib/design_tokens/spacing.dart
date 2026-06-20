import 'package:flutter/widgets.dart';

/// Spatial grid — Dark Moody edition.
///
/// 4dp base, 8dp default sibling rhythm, 24dp section gap,
/// 16dp gutters (24 for "generous" surfaces — Now Playing, Lyrics).
/// 48dp minimum hit-target.
abstract final class AfSpacing {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s56 = 56;
  static const double s64 = 64;
  static const double s72 = 72;
  static const double s96 = 96;
  static const double s136 = 136;

  /// Standard gutter.
  static const double gutter = s16;

  /// "Generous" gutter for Now Playing, Lyrics.
  static const double gutterGenerous = s24;

  /// Default vertical rhythm between siblings.
  static const double rhythm = s8;

  /// Vertical margin between track rows in lists.
  static const double trackRowVertical = s4;

  /// Default vertical rhythm between sections.
  static const double sectionGap = s24;

  /// Minimum hit target. Anything tappable must have a 48×48 hit region.
  static const double minHitTarget = s48;

  /// Bottom-nav height (excluding gesture inset).
  static const double bottomNavHeight = 64;

  /// Mini-player height above the bottom nav.
  static const double miniPlayerHeight = 64;

  /// Total bottom inset for scrollables when mini-player + bottom-nav present.
  static const double bottomInsetWithMiniAndNav =
      bottomNavHeight + miniPlayerHeight;

  /// Now Playing play button diameter.
  static const double playButtonSize = s64;

  /// Profile avatar diameter.
  static const double avatarSize = s96;

  /// Search filter chip height.
  static const double filterChipHeight = 44;

  /// Padding presets.
  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(
    horizontal: s16,
  );

  static const EdgeInsets pageHorizontalGenerous = EdgeInsets.symmetric(
    horizontal: s24,
  );
}

/// Icon size grid — Dark Moody edition.
///
/// Four tiers. New code MUST use these values. Existing 22dp and 26dp
/// icons are legacy — migrate to nearest tier on next touch.
abstract final class AfIconSizes {
  /// 16dp — compact UI (settings icon containers, inline badges).
  static const double xs = 16;

  /// 20dp — secondary controls (shuffle, loop, filter icons).
  static const double sm = 20;

  /// 24dp — default (app bar icons, list tile leading, standard actions).
  static const double md = 24;

  /// 28dp — primary emphasis (play button icon, hero artwork placeholder).
  static const double lg = 28;
}
