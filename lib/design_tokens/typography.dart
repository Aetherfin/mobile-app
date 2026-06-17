import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Aetherfin type scale — Dark Moody edition.
///
/// Outfit for headlines/display (geometric, modern, premium).
/// DM Sans for body/UI (clean, characterful, excellent readability).
/// JetBrains Mono for technical readouts only.
///
/// All sizes in dp (logical pixels). Line height is in dp (NOT unitless).
abstract final class AfTypography {
  // ---------------------------------------------------------------------------
  // Public text styles — never hard-code these in widgets.
  // ---------------------------------------------------------------------------

  static TextStyle get display => _outfit(
    fontSize: 36,
    height: 40 / 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static TextStyle get titleExtraLarge => _outfit(
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  static TextStyle get titleLarge => _outfit(
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle get titleMedium => _dmSans(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static TextStyle get titleSmall => _dmSans(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static TextStyle get bodyLarge =>
      _dmSans(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400);

  static TextStyle get bodyMedium =>
      _dmSans(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);

  static TextStyle get bodySmall => _dmSans(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  /// Section header. UPPERCASE in widget; never bold; never accent.
  static TextStyle get label => _dmSans(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  static TextStyle get caption => _dmSans(
    fontSize: 10,
    height: 13 / 10,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  /// Between bodySmall(12) and bodyMedium(14).
  static TextStyle get bodyMediumSmall => _dmSans(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  /// Between titleMedium(22) and titleSmall(17).
  static TextStyle get titleMediumLarge => _dmSans(
    fontSize: 19,
    height: 24 / 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// Tiny label — overline, micro text, timestamps.
  static TextStyle get overline => _dmSans(
    fontSize: 9,
    height: 12 / 9,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
  );

  /// JetBrains Mono — bitrate, codec, hash readouts only.
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
    textStyle: const TextStyle(
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w500,
      color: AfColors.textPrimary,
    ),
  );

  /// JetBrains Mono — micro stat badges (smaller than mono).
  static TextStyle get monoSmall => GoogleFonts.jetBrainsMono(
    textStyle: const TextStyle(
      fontSize: 10,
      height: 13 / 10,
      fontWeight: FontWeight.w500,
      color: AfColors.textPrimary,
    ),
  );

  /// JetBrains Mono — EQ parameter readouts and text fields.
  static TextStyle get monoMedium => GoogleFonts.jetBrainsMono(
    textStyle: const TextStyle(
      fontSize: 13,
      height: 17 / 13,
      fontWeight: FontWeight.w500,
      color: AfColors.textPrimary,
    ),
  );

  /// JetBrains Mono — EQ curve axis labels and micro annotations.
  static TextStyle get monoXSmall => GoogleFonts.jetBrainsMono(
    textStyle: const TextStyle(
      fontSize: 9,
      height: 12 / 9,
      fontWeight: FontWeight.w500,
      color: AfColors.textPrimary,
    ),
  );

  /// Large initials for profile avatar.
  static TextStyle get avatarInitials => _outfit(
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  // ---------------------------------------------------------------------------
  // Scaled variants — apply system text scaler for accessibility.
  // Use via: AfTypography.displayScaled(MediaQuery.textScalerOf(context))
  // ---------------------------------------------------------------------------

  static TextStyle displayScaled(TextScaler scaler) => _outfit(
    fontSize: scaler.scale(36),
    height: 40 / 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static TextStyle titleExtraLargeScaled(TextScaler scaler) => _outfit(
    fontSize: scaler.scale(32),
    height: 38 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  static TextStyle titleLargeScaled(TextScaler scaler) => _outfit(
    fontSize: scaler.scale(28),
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle titleMediumScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(22),
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static TextStyle titleSmallScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(17),
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static TextStyle bodyLargeScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(16),
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  static TextStyle bodyMediumScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(14),
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  static TextStyle bodySmallScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(12),
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  static TextStyle labelScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(11),
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  static TextStyle captionScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(10),
    height: 13 / 10,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  static TextStyle bodyMediumSmallScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(13),
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  static TextStyle titleMediumLargeScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(19),
    height: 24 / 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static TextStyle overlineScaled(TextScaler scaler) => _dmSans(
    fontSize: scaler.scale(9),
    height: 12 / 9,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
  );

  static TextStyle monoScaled(TextScaler scaler) => GoogleFonts.jetBrainsMono(
    textStyle: TextStyle(
      fontSize: scaler.scale(11),
      height: 14 / 11,
      fontWeight: FontWeight.w500,
      color: AfColors.textPrimary,
    ),
  );

  static TextStyle monoSmallScaled(TextScaler scaler) =>
      GoogleFonts.jetBrainsMono(
        textStyle: TextStyle(
          fontSize: scaler.scale(10),
          height: 13 / 10,
          fontWeight: FontWeight.w500,
          color: AfColors.textPrimary,
        ),
      );

  static TextStyle avatarInitialsScaled(TextScaler scaler) => _outfit(
    fontSize: scaler.scale(32),
    height: 38 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  // ---------------------------------------------------------------------------
  // Shared button styles.
  // ---------------------------------------------------------------------------

  /// OutlinedButton style for action rows (Play All / Shuffle / Radio).
  static ButtonStyle get outlinedAction => OutlinedButton.styleFrom(
    side: const BorderSide(color: AfColors.accentPrimary, width: 1.5),
    foregroundColor: AfColors.accentPrimary,
  );

  // ---------------------------------------------------------------------------
  // Material 3 textTheme mapping.
  // ---------------------------------------------------------------------------

  static TextTheme get textTheme => textThemeFor(null);

  /// Builds a [TextTheme] with system text scaling applied.
  /// Use in widgets that need scaled text: `AfTypography.textThemeScaled(context)`.
  static TextTheme textThemeScaled(BuildContext context, {Spectral? s}) {
    final scaler = MediaQuery.textScalerOf(context);
    final tp = s?.textPrimary ?? AfColors.textPrimary;
    final ts = s?.textSecondary ?? AfColors.textSecondary;
    final tt = s?.textTertiary ?? AfColors.textTertiary;
    return TextTheme(
      displayLarge: displayScaled(scaler).copyWith(color: tp),
      displayMedium: displayScaled(scaler).copyWith(color: tp),
      displaySmall: titleLargeScaled(scaler).copyWith(color: tp),
      headlineLarge: titleLargeScaled(scaler).copyWith(color: tp),
      headlineMedium: titleLargeScaled(scaler).copyWith(color: tp),
      headlineSmall: titleMediumScaled(scaler).copyWith(color: tp),
      titleLarge: titleLargeScaled(scaler).copyWith(color: tp),
      titleMedium: titleMediumScaled(scaler).copyWith(color: tp),
      titleSmall: titleSmallScaled(scaler).copyWith(color: tp),
      bodyLarge: bodyLargeScaled(scaler).copyWith(color: tp),
      bodyMedium: bodyMediumScaled(scaler).copyWith(color: tp),
      bodySmall: bodySmallScaled(scaler).copyWith(color: ts),
      labelLarge: labelScaled(scaler).copyWith(color: ts),
      labelMedium: labelScaled(scaler).copyWith(color: ts),
      labelSmall: captionScaled(scaler).copyWith(color: tt),
    );
  }

  /// Builds a [TextTheme] using dynamic text colors from [Spectral].
  /// Falls back to static [AfColors] tokens when [s] is null.
  static TextTheme textThemeFor(Spectral? s) {
    final tp = s?.textPrimary ?? AfColors.textPrimary;
    final ts = s?.textSecondary ?? AfColors.textSecondary;
    final tt = s?.textTertiary ?? AfColors.textTertiary;
    return TextTheme(
      displayLarge: display.copyWith(color: tp),
      displayMedium: display.copyWith(color: tp),
      displaySmall: titleLarge.copyWith(color: tp),
      headlineLarge: titleLarge.copyWith(color: tp),
      headlineMedium: titleLarge.copyWith(color: tp),
      headlineSmall: titleMedium.copyWith(color: tp),
      titleLarge: titleLarge.copyWith(color: tp),
      titleMedium: titleMedium.copyWith(color: tp),
      titleSmall: titleSmall.copyWith(color: tp),
      bodyLarge: bodyLarge.copyWith(color: tp),
      bodyMedium: bodyMedium.copyWith(color: tp),
      bodySmall: bodySmall.copyWith(color: ts),
      labelLarge: label.copyWith(color: ts),
      labelMedium: label.copyWith(color: ts),
      labelSmall: caption.copyWith(color: tt),
    );
  }

  // ---------------------------------------------------------------------------
  // Internal helpers — Outfit (geometric display) + DM Sans (body/UI).
  // ---------------------------------------------------------------------------

  /// Outfit — geometric sans for headlines/display.
  static TextStyle _outfit({
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    double letterSpacing = 0,
  }) => GoogleFonts.outfit(
    textStyle: TextStyle(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: AfColors.textPrimary,
    ),
  );

  /// DM Sans — clean sans for body/UI.
  static TextStyle _dmSans({
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    double letterSpacing = 0,
  }) => GoogleFonts.dmSans(
    textStyle: TextStyle(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: AfColors.textPrimary,
    ),
  );
}
