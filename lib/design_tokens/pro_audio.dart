import 'package:flutter/material.dart';

/// Professional audio design tokens for the dedicated EQ screen.
///
/// Dark rack-panel aesthetic: tight spacing, sharp corners, frequency-coded
/// colors. Separate from the main AfColors/AfTypography tokens which use
/// the app's moody palette.
abstract final class ProAudioColors {
  // ── Backgrounds ──────────────────────────────────────────────────────────
  /// Main canvas.
  static const bgPrimary = Color(0xFF1A1A1E);

  /// Rack panels.
  static const bgPanel = Color(0xFF12141A);

  /// Hover/active states.
  static const bgSurface = Color(0xFF22242A);

  /// Deepest layer.
  static const bgOverlay = Color(0xFF0A0B0E);

  // ── Grid & Subtle ────────────────────────────────────────────────────────
  /// 10% white grid lines.
  static const gridLine = Color(0x1AFFFFFF);

  /// 30% white center line (0 dB).
  static const gridLineCenter = Color(0x4DFFFFFF);

  /// 45% white dim text.
  static const textDim = Color(0x73FFFFFF);

  /// 90% white bright text.
  static const textBright = Color(0xFFE0E0E0);

  // ── EQ Curve (FabFilter gold) ────────────────────────────────────────────
  /// Active EQ curve — gold.
  static const curveActive = Color(0xFFFFD700);

  /// 20% gold glow.
  static const curveGlow = Color(0x33FFD700);

  /// Inactive EQ curve — 30% white.
  static const curveInactive = Color(0x4DFFFFFF);

  // ── Band Colors (frequency-coded) ────────────────────────────────────────
  /// Red — bass.
  static const bandLow = Color(0xFFFF4444);

  /// Orange — low-mid.
  static const bandLowMid = Color(0xFFFF8844);

  /// Yellow — mid.
  static const bandMid = Color(0xFFFFCC44);

  /// Green — high-mid.
  static const bandHighMid = Color(0xFF44CC44);

  /// Blue — treble.
  static const bandHigh = Color(0xFF4488FF);

  /// 18-band palette for parametric EQ per-band coloring.
  static const List<Color> bandColors = [
    Color(0xFF5B9BD5),
    Color(0xFF7DB88F),
    Color(0xFFE8A87C),
    Color(0xFFB39DDB),
    Color(0xFFEF9A9A),
    Color(0xFF80CBC4),
    Color(0xFFFFCC80),
    Color(0xFF9FA8DA),
    Color(0xFFA5D6A7),
    Color(0xFFFFAB91),
    Color(0xFF80DEEA),
    Color(0xFFCE93D8),
    Color(0xFFC5E1A5),
    Color(0xFFFFF176),
    Color(0xFF81D4FA),
    Color(0xFFF48FB1),
    Color(0xFFBCAAA4),
    Color(0xFF80CBC4),
  ];

  // ── Meter Zones ──────────────────────────────────────────────────────────
  /// Green zone: -∞ to -6 dB.
  static const meterGreen = Color(0xFF4CAF50);

  /// Yellow zone: -6 to 0 dB.
  static const meterYellow = Color(0xFFFFC107);

  /// Red zone: 0 to +3 dB.
  static const meterRed = Color(0xFFFF5252);

  // ── Active/Selected ──────────────────────────────────────────────────────
  /// White when selected.
  static const activeNode = Color(0xFFFFFFFF);

  /// Gray when not selected.
  static const inactiveNode = Color(0xFFAAAAAA);

  /// Light blue for focus.
  static const accentFocus = Color(0xFF64B5F6);
}

/// Professional audio typography for the dedicated EQ screen.
abstract final class ProAudioTypography {
  /// Parameter values (readout) — JetBrains Mono 13px medium, tabular figures.
  static const readout = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Color(0xFFE0E0E0),
  );

  /// Frequency labels — JetBrains Mono 9px.
  static const freqLabel = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 9,
    color: Color(0x73FFFFFF),
  );

  /// dB labels — JetBrains Mono 8px.
  static const dbLabel = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 8,
    color: Color(0x73FFFFFF),
  );

  /// Section headers — Inter 11px bold, letter-spacing 0.1.
  static const sectionHeader = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
    color: Color(0xFFE0E0E0),
  );

  /// Control labels — Inter 10px medium.
  static const controlLabel = TextStyle(
    fontFamily: 'Inter',
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: Color(0x99FFFFFF),
  );

  /// Large value display — JetBrains Mono 18px semi-bold, tabular figures.
  static const valueLarge = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Color(0xFFE0E0E0),
  );
}

/// Professional audio spacing for the dedicated EQ screen.
///
/// Tighter than the main app spacing: 2dp between controls, sharp corners,
/// rack-panel aesthetic.
abstract final class ProAudioSpacing {
  /// Between sliders.
  static const double controlGap = 2.0;

  /// Between sections.
  static const double sectionGap = 8.0;

  /// Inside panels.
  static const double panelPadding = 8.0;

  /// Between panels.
  static const double panelMargin = 4.0;

  /// Section panel radius.
  static const double panelRadius = 2.0;

  /// Sliders, buttons.
  static const double controlRadius = 1.0;

  /// EQ bars.
  static const double barRadius = 1.0;

  /// Band handles (base).
  static const double nodeRadius = 7.0;

  /// Band handles (hover).
  static const double nodeRadiusHover = 8.0;

  /// Band handles (active).
  static const double nodeRadiusActive = 9.0;
}
