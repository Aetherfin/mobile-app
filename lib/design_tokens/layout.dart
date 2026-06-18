/// Responsive layout tokens — Breakpoints, grid config, content constraints.
///
/// Aetherfin targets Android phones (360dp+), foldables, and tablets.
/// This file provides the breakpoint system and grid tile extents
/// used by adaptive [SliverGridDelegateWithMaxCrossAxisExtent] layouts.
abstract final class AfLayout {
  // ---------------------------------------------------------------------------
  // Breakpoints — Android form factors
  // ---------------------------------------------------------------------------

  /// Compact: phones up to ~600dp width (single-pane).
  static const double compact = 600;

  /// Medium: foldables and small tablets 600–840dp (may use side-by-side).
  static const double medium = 840;

  /// Expanded: large tablets and desktops > 840dp (multi-pane).
  // (expanded is implicit: width >= medium)

  /// Returns the current screen size tier based on [width].
  static AfScreenSize screenSize(double width) {
    if (width < compact) return AfScreenSize.compact;
    if (width < medium) return AfScreenSize.medium;
    return AfScreenSize.expanded;
  }

  // ---------------------------------------------------------------------------
  // Content constraints
  // ---------------------------------------------------------------------------

  /// Maximum content width for tab screens. Content is centered and
  /// constrained on wider screens to prevent edge-to-edge stretching.
  /// On medium/expanded screens, content breathes wider.
  static double maxContentWidthFor(double screenWidth) {
    if (screenWidth >= medium) return 720;
    if (screenWidth >= compact) return 640;
    return 600;
  }

  /// Legacy constant — prefer [maxContentWidthFor] for responsive layouts.
  static const double maxContentWidth = 600;

  /// Maximum dialog width.
  static const double dialogMaxWidth = 560;

  // ---------------------------------------------------------------------------
  // Grid tile extents — Used with SliverGridDelegateWithMaxCrossAxisExtent
  // ---------------------------------------------------------------------------

  /// Maximum tile width for album grids. Produces:
  /// - 2 columns at 360dp
  /// - 3 columns at 600dp
  /// - 4 columns at 800dp
  static const double albumGridMaxTileExtent = 200;

  /// Maximum tile width for artist grids (circular cards).
  static const double artistGridMaxTileExtent = 160;

  /// Maximum tile width for genre grids (wide rectangular cards).
  static const double genreGridMaxTileExtent = 280;

  // ---------------------------------------------------------------------------
  // Page padding
  // ---------------------------------------------------------------------------

  /// Wide page horizontal padding for tablet content.
  static const double pageHorizontalWide = 32;

  // ---------------------------------------------------------------------------
  // Mini player
  // ---------------------------------------------------------------------------

  /// Mini player height (artwork + progress ring + transport).
  static const double miniPlayerHeight = 64;
}

/// Screen size tiers for adaptive layouts.
enum AfScreenSize {
  /// Phones up to ~600dp width. Single-pane, stacked layout.
  compact,

  /// Foldables and small tablets 600–840dp. May use side-by-side layout.
  medium,

  /// Large tablets and desktops > 840dp. Multi-pane layout.
  expanded,
}
