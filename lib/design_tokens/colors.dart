import 'package:flutter/material.dart';

/// Aetherfin color tokens.
///
/// Derived from the OKLCH-based design system:
///   - 12-step indigo primary scale (hue 275°)
///   - 6-step surface depth (low-chroma indigo-tinted neutrals)
///   - Dedicated text scale on the Nocturne canvas
///   - Five semantic tokens
///
/// The runtime-extracted spectral accent lives in [Spectral] and is
/// exposed via the `spectralProvider` Riverpod family — never embed
/// spectral values here.
abstract final class AfColors {
  // ---------------------------------------------------------------------------
  // Indigo primary scale (hue 275°)
  // ---------------------------------------------------------------------------
  static const indigo50  = Color(0xFFF0F2FF);
  static const indigo100 = Color(0xFFE3E6FF);
  static const indigo200 = Color(0xFFCCD2FF);
  static const indigo300 = Color(0xFFA3B0FF);
  static const indigo400 = Color(0xFF8B93FF);
  static const indigo500 = Color(0xFF6C72FF);
  static const indigo600 = Color(0xFF5356FF); // Primary action
  static const indigo700 = Color(0xFF3F42E6); // Pressed
  static const indigo800 = Color(0xFF2B2EBE); // Hero card gradient base
  static const indigo900 = Color(0xFF1B1D9A); // Section-tinted surfaces
  static const indigo950 = Color(0xFF0C0E56); // Deep tint for sheets
  static const indigo1000 = Color(0xFF060733); // Reserved emergency depth

  // ---------------------------------------------------------------------------
  // Surface scale — Nocturne (dark)
  // Midnight Onyx: pure dark, no purple tint — depth via tone.
  // ---------------------------------------------------------------------------
  static const surfaceCanvas = Color(0xFF08090C);
  static const surfaceLow    = Color(0xFF0F1116);
  static const surfaceBase   = Color(0xFF151820);
  static const surfaceRaised = Color(0xFF1C202B);
  static const surfaceHigh   = Color(0xFF252A3A);
  static const surfaceMax    = Color(0xFF333A50);
  static const surfaceScrim  = Color(0x8F000000);

  // ---------------------------------------------------------------------------
  // Foreground (text on Nocturne canvas)
  // APCA targets: body Lc ≥ 60, secondary ≥ 45, tertiary ≥ 30.
  // ---------------------------------------------------------------------------
  static const textPrimary   = Color(0xFFF3F4F6);
  static const textSecondary = Color(0xFFD1D5DB);
  static const textTertiary  = Color(0xFF9CA3AF);
  static const textDisabled  = Color(0xFF6B7280);
  static const textOnPrimary = Color(0xFFFFFFFF);
  static const textLink      = Color(0xFF818CF8);

  // ---------------------------------------------------------------------------
  // Semantic
  // ---------------------------------------------------------------------------
  static const semanticSuccess = Color(0xFF5DCB87);
  static const semanticWarning = Color(0xFFD7B852);
  static const semanticError   = Color(0xFFE26A53);
  static const semanticInfo    = Color(0xFF6CB1D9);
  static const semanticOffline = Color(0xFF90909E);
}

/// Spectral accent triple, extracted from current artwork at runtime.
///
/// Three tokens for three uses — never collapse into a single color.
@immutable
class Spectral {
  // play-button outer glow on Now Playing

  const Spectral({
    required this.energy,
    required this.shadow,
    required this.glow,
  });
  final Color energy; // waveform peak fill, lyric highlight, heart glow
  final Color shadow; // Now Playing bottom gradient stop
  final Color glow;

  /// Default — used until artwork is parsed, on data-saver, on cellular,
  /// or whenever extraction can't surface a chromatic sample.
  static const fallback = Spectral(
    energy: Color(0xFF8276E0), // AfColors.indigo400
    shadow: Color(0xFF1E1E2E),
    glow: Color(0xFFA89DEC), // AfColors.indigo300
  );

  @override
  bool operator ==(Object other) =>
      other is Spectral &&
      other.energy == energy &&
      other.shadow == shadow &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(energy, shadow, glow);
}
