import 'package:flutter/material.dart';

/// Aetherfin color tokens — Dark Moody palette.
///
/// Deep blacks, ocean blue accents, album-art-driven atmosphere.
/// The runtime-extracted spectral accent lives in [Spectral] and is
/// exposed via the `spectralProvider` Riverpod family — never embed
/// spectral values here.
abstract final class AfColors {
  // ---------------------------------------------------------------------------
  // Surface scale — Cool blue-grey, no warm tint
  // Depth via tone, NOT blur, NOT shadow-as-decoration.
  //
  // Spaced ≥12 per channel so any 2-stop gradient between adjacent tokens
  // produces smooth transitions on 8-bit displays without extra stops.
  // ---------------------------------------------------------------------------
  static const surfaceCanvas = Color(0xFF0A0B0E);
  static const surfaceLow = Color(0xFF14161A);
  static const surfaceBase = Color(0xFF1E2028);
  static const surfaceRaised = Color(0xFF282A34);
  static const surfaceHigh = Color(0xFF343640);
  static const surfaceMax = Color(0xFF40424E);
  static const surfaceScrim = Color(0xCC000000);

  // ---------------------------------------------------------------------------
  // Foreground (text on dark canvas)
  // APCA targets: body Lc ≥ 60, secondary ≥ 45, tertiary ≥ 30.
  // ---------------------------------------------------------------------------
  static const textPrimary = Color(0xFFE8ECF2);
  static const textSecondary = Color(0xFF9AA0AD);
  static const textTertiary = Color(0xFF7C8290);
  static const textDisabled = Color(0xFF4A4E58);
  static const textOnPrimary = Color(0xFFF0F4F8);
  static const textLink = Color(0xFF5B9BD5);

  /// Label contrast — use where textTertiary fails WCAG AA at small sizes
  /// (section headers, uppercase labels, captions).
  static const labelContrast = Color(0xFF9AA0AD); // same as textSecondary

  // ---------------------------------------------------------------------------
  // Accent — Ocean blue
  // ---------------------------------------------------------------------------
  static const accentPrimary = Color(
    0xFF2E6FA8,
  ); // Darker ocean blue (WCAG AA 4.80:1)
  static const accentSecondary = Color(0xFF3A7CA5); // Deep blue
  static const accentMuted = Color(0xFF6B8FA3); // Muted blue

  // Indigo scale kept for spectral fallback only
  static const indigo300 = Color(0xFFA89DEC);
  static const indigo400 = Color(0xFF8276E0);
  static const indigo500 = Color(0xFF6657D7);
  static const indigo600 = Color(0xFF5644C9);
  static const indigo900 = Color(0xFF251F58);

  // ---------------------------------------------------------------------------
  // Semantic
  // ---------------------------------------------------------------------------
  static const semanticSuccess = Color(0xFF7DB88F);
  static const semanticWarning = Color(0xFF5B9BD5);
  static const semanticError = Color(0xFFD4735A);
  static const semanticInfo = Color(0xFF7BA3B8);
  static const semanticOffline = Color(0xFF706A64);

  // ---------------------------------------------------------------------------
  // EQ band colors — frequency-coded for parametric EQ visualization.
  // Used by frequency_response_painter and parametric_eq_curve.
  // ---------------------------------------------------------------------------
  static const eqBand1 = Color(0xFF2196F3); // blue
  static const eqBand2 = Color(0xFF009688); // teal
  static const eqBand3 = Color(0xFFFF9800); // orange
  static const eqBand4 = Color(0xFF9C27B0); // purple
  static const eqBand5 = Color(0xFFE91E63); // pink

  // ---------------------------------------------------------------------------
  // Glass morphism — translucent white overlays for frosted surfaces.
  // Used by mini-player, now-playing top bar, cast button, track rows.
  // ---------------------------------------------------------------------------
  static const glassFillSubtle = Color(0x0AFFFFFF); // white @ 4%
  static const glassFill = Color(0x0FFFFFFF); // white @ 6%
  static const glassFillStrong = Color(0x14FFFFFF); // white @ 8%
  static const glassFillMedium = Color(0x45FFFFFF); // white @ 27%
  static const glassFillHeavy = Color(0x8C0A0A0A); // surfaceCanvas @ 55%
  static const glassBorder = Color(0x0FFFFFFF); // white @ 6%
  static const glassBorderStrong = Color(0x14FFFFFF); // white @ 8%
  static const glassBorderEmphasis = Color(0x1AFFFFFF); // white @ 10%
}

/// Genre-specific gradient pairs for genre cards.
///
/// Each genre maps to a [List<Color>] of 2 stops for a [LinearGradient].
/// These are curated to feel distinct while staying within the dark moody
/// palette. Fallback uses the server-provided tint via [parseHexColor].
abstract final class AfGenreColors {
  static const List<Color> electronic = [Color(0xFF9C27B0), Color(0xFF673AB7)];
  static const List<Color> rock = [Color(0xFFF44336), Color(0xFFFF5722)];
  static const List<Color> hipHop = [Color(0xFFFF9800), Color(0xFFFFC107)];
  static const List<Color> rap = [Color(0xFFFF9800), Color(0xFFFFC107)];
  static const List<Color> pop = [Color(0xFFE91E63), Color(0xFFFF4081)];
  static const List<Color> jazz = [Color(0xFF009688), Color(0xFF00BCD4)];
  static const List<Color> classical = [Color(0xFF3F51B5), Color(0xFF2196F3)];
  static const List<Color> rnb = [Color(0xFF673AB7), Color(0xFF9C27B0)];
  static const List<Color> country = [Color(0xFF795548), Color(0xFFFF9800)];
  static const List<Color> metal = [Color(0xFF9E9E9E), Color(0xFF607D8B)];
  static const List<Color> indie = [Color(0xFF4CAF50), Color(0xFF009688)];
  static const List<Color> alternative = [Color(0xFF00BCD4), Color(0xFF2196F3)];
  static const List<Color> soul = [Color(0xFFFFC107), Color(0xFFFF9800)];
  static const List<Color> funk = [Color(0xFFE91E63), Color(0xFF673AB7)];
  static const List<Color> reggae = [Color(0xFF4CAF50), Color(0xFFFFEB3B)];
  static const List<Color> blues = [Color(0xFF2196F3), Color(0xFF3F51B5)];
  static const List<Color> folk = [Color(0xFF795548), Color(0xFF4CAF50)];
  static const List<Color> ambient = [Color(0xFF607D8B), Color(0xFF009688)];
  static const List<Color> techno = [Color(0xFF00BCD4), Color(0xFF2196F3)];
  static const List<Color> house = [Color(0xFF673AB7), Color(0xFF9C27B0)];
  static const List<Color> disco = [Color(0xFFE91E63), Color(0xFFFF9800)];

  /// Returns the gradient for [genre], or `null` if unknown.
  static List<Color>? of(String genre) => switch (genre.toLowerCase()) {
    'electronic' => electronic,
    'rock' => rock,
    'hip hop' => hipHop,
    'rap' => rap,
    'pop' => pop,
    'jazz' => jazz,
    'classical' => classical,
    'r&b' || 'rnb' => rnb,
    'country' => country,
    'metal' => metal,
    'indie' => indie,
    'alternative' => alternative,
    'soul' => soul,
    'funk' => funk,
    'reggae' => reggae,
    'blues' => blues,
    'folk' => folk,
    'ambient' => ambient,
    'techno' => techno,
    'house' => house,
    'disco' => disco,
    _ => null,
  };
}

/// Spectral accent palette, extracted from current artwork at runtime.
///
/// Every accent color in the app derives from artwork's dominant hue.
/// The three legacy tokens (energy/shadow/glow) plus the new full-palette
/// tokens (primary/secondary/muted/link/warning) all share the same hue —
/// they vary only in lightness and chroma.
///
/// Naming convention:
///   - `energy/shadow/glow` → now-playing specific (waveform, gradient, glow)
///   - `primary/secondary/muted/link/warning` → app-wide accent replacements
@immutable
class Spectral {
  const Spectral({
    required this.energy,
    required this.shadow,
    required this.glow,
    required this.primary,
    required this.secondary,
    required this.muted,
    required this.link,
    required this.warning,
    this.surfaceCanvas = const Color(0xFF0A0B0E),
    this.surfaceLow = const Color(0xFF14161A),
    this.surfaceBase = const Color(0xFF1E2028),
    this.surfaceRaised = const Color(0xFF282A34),
    this.surfaceHigh = const Color(0xFF343640),
    this.surfaceMax = const Color(0xFF40424E),
    this.textPrimary = const Color(0xFFE8ECF2),
    this.textSecondary = const Color(0xFF9AA0AD),
    this.textTertiary = const Color(0xFF6B7280),
    this.textDisabled = const Color(0xFF4A4E58),
    this.textOnPrimary = const Color(0xFFF0F4F8),
  });

  // ── Now-playing specific ──
  final Color energy; // waveform peak fill, lyric highlight
  final Color shadow; // Now Playing bottom gradient stop
  final Color glow; // play-button outer glow on Now Playing

  // ── App-wide accent palette ──
  final Color primary; // theme primary: buttons, switches, sliders, focus
  final Color secondary; // secondary actions, badges, chips
  final Color muted; // subtle accents: chip bg, icon tint, disabled state
  final Color link; // text links, interactive text
  final Color warning; // semantic warning (same hue, not red)

  // ── Dynamic surface palette (hue-shifted from artwork) ──
  final Color surfaceCanvas;
  final Color surfaceLow;
  final Color surfaceBase;
  final Color surfaceRaised;
  final Color surfaceHigh;
  final Color surfaceMax;

  // ── Dynamic text palette (contrasts against shifted surfaces) ──
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color textOnPrimary;

  /// Default — used until artwork is parsed. Matches AfColors defaults.
  ///
  /// This is the initial color palette shown before any track artwork is loaded.
  /// It uses the ocean-blue accent colors from [AfColors] to maintain visual
  /// consistency. Once artwork is parsed by `spectral_extractor.dart`, the
  /// palette transitions to artwork-derived colors via [AnimatedSpectralScope].
  ///
  /// The fallback ensures the app always has a valid color palette, even during:
  /// - Initial boot before first track plays
  /// - Network errors preventing artwork download
  /// - Local files without embedded artwork
  /// - Queue transitions between tracks
  static const fallback = Spectral(
    energy: Color(0xFF2E6FA8),
    shadow: Color(0xFF0D1B2A),
    glow: Color(0xFF7EC8E3),
    primary: Color(0xFF2E6FA8),
    secondary: Color(0xFF3A7CA5),
    muted: Color(0xFF6B8FA3),
    link: Color(0xFF2E6FA8),
    warning: Color(0xFF2E6FA8),
  );

  @override
  bool operator ==(Object other) =>
      other is Spectral &&
      other.energy == energy &&
      other.shadow == shadow &&
      other.glow == glow &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.muted == muted &&
      other.link == link &&
      other.warning == warning &&
      other.surfaceCanvas == surfaceCanvas &&
      other.surfaceLow == surfaceLow &&
      other.surfaceBase == surfaceBase &&
      other.surfaceRaised == surfaceRaised &&
      other.surfaceHigh == surfaceHigh &&
      other.surfaceMax == surfaceMax &&
      other.textPrimary == textPrimary &&
      other.textSecondary == textSecondary &&
      other.textTertiary == textTertiary &&
      other.textDisabled == textDisabled &&
      other.textOnPrimary == textOnPrimary;

  @override
  int get hashCode => Object.hash(
    energy,
    shadow,
    glow,
    primary,
    secondary,
    muted,
    link,
    warning,
    surfaceCanvas,
    surfaceLow,
    surfaceBase,
    surfaceRaised,
    surfaceHigh,
    surfaceMax,
    textPrimary,
    textSecondary,
    textTertiary,
    textDisabled,
    textOnPrimary,
  );
}
