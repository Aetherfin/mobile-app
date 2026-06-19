import 'package:flutter/animation.dart';

/// Aetherfin motion easing curves — Dark Moody edition.
///
/// EIGHT curves total. The original design spec called for five core curves,
/// plus three standard Flutter curves for common UI patterns.
///
/// Audio-coupled animations (waveform, progress ring, lyric scroll) use
/// `linear` ALWAYS. Easing audio time lies about playback position.
abstract final class AfCurves {
  /// `cubic-bezier(0.16, 1, 0.3, 1)` — smooth deceleration.
  /// Page transitions, tab switches.
  static const Curve easeStandard = Cubic(0.16, 1, 0.3, 1);

  /// `cubic-bezier(0.22, 1, 0.36, 1)` — dramatic spatial moves.
  /// Mini-player → Now Playing expand, hero artwork handoff.
  static const Curve easeEmphasized = Cubic(0.22, 1, 0.36, 1);

  /// `cubic-bezier(0.175, 0.885, 0.32, 1.045)` — iOS-like spring present.
  /// Gentle start → slight overshoot → smooth settle.
  /// Bottom sheet open, dialog open, modal present.
  static const Curve springPresent = Cubic(0.175, 0.885, 0.32, 1.045);

  /// `cubic-bezier(0.55, 0.055, 0.675, 0.19)` — iOS-like spring dismiss.
  /// Slow start → accelerate out → no overshoot.
  /// Bottom sheet close, dialog close, modal dismiss.
  static const Curve springDismiss = Cubic(0.55, 0.055, 0.675, 0.19);

  /// `cubic-bezier(0, 0, 0.2, 1)` — entries.
  static const Curve easeOut = Curves.easeOut;

  /// `cubic-bezier(0.5, 0, 1, 1)` — exits.
  static const Curve easeIn = Curves.easeIn;

  /// `cubic-bezier(0.42, 0, 0.58, 1)` — smooth in-out.
  /// Play button bounce, icon morph transitions.
  static const Curve easeInOut = Curves.easeInOut;

  /// `linear` — audio-coupled only.
  /// Waveform fill, progress ring sweep, lyric scroll position.
  static const Curve linear = Curves.linear;

  /// `easeOutBack` — overshoot settle.
  /// Stats card bounce-in, library tab indicator.
  static const Curve easeOutBack = Curves.easeOutBack;
}

/// Aetherfin motion duration tiers — Dark Moody edition.
///
/// iOS-like feel: heavier, springier, more deliberate than stock Material.
/// NEVER use raw ms values — always reference these tiers.
abstract final class AfDurations {
  /// 80 ms — color/opacity micro-feedback (icon press tint).
  static const Duration instant = Duration(milliseconds: 80);

  /// 180 ms — small element transitions, hover states, heart pop.
  static const Duration quick = Duration(milliseconds: 180);

  /// 350 ms — default page/sheet transitions, dialog open.
  static const Duration standard = Duration(milliseconds: 350);

  /// 500 ms — Now Playing expand, hero handoff, sheet open.
  static const Duration expressive = Duration(milliseconds: 500);

  /// 700 ms — onboarding intro animation only.
  static const Duration long = Duration(milliseconds: 700);

  /// 250 ms — play button bounce, icon morph, dialog/sheet reverse dismiss.
  static const Duration bounce = Duration(milliseconds: 250);

  /// 1200 ms — ambient pulse glow, breathing animations.
  static const Duration ambient = Duration(milliseconds: 1200);

  /// 1500 ms — skeleton shimmer sweep.
  static const Duration shimmer = Duration(milliseconds: 1500);

  /// 800 ms — spectral color crossfade.
  static const Duration spectral = Duration(milliseconds: 800);

  /// 833 ms — server pill dot pulse (1.2 Hz).
  static const Duration pulse = Duration(milliseconds: 833);

  /// 2000 ms — info SnackBar (action confirmed, item added/removed).
  static const Duration snackBarInfo = Duration(seconds: 2);

  /// 4000 ms — error SnackBar (operation failed, network error).
  static const Duration snackBarError = Duration(seconds: 4);

  /// 4000 ms — onboarding breath animation only.
  static const Duration longBreath = Duration(milliseconds: 4000);

  /// 3000 ms — onboarding glow breath animation only.
  static const Duration glowBreath = Duration(milliseconds: 3000);
}

/// Stagger conventions for grid / list reveals.
abstract final class AfStagger {
  /// 40 ms per item. Top-left → bottom-right (grids) or top → bottom (lists).
  static const Duration perItem = Duration(milliseconds: 40);

  /// 8 items max — items 9+ all run at the same offset as item 8.
  static const int maxStaggered = 8;

  /// Per-item animation duration (fade + 12dp translate).
  static const Duration itemDuration = AfDurations.quick;
}
