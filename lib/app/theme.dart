import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens/tokens.dart';

/// Builds the Aetherfin "Nocturne" (dark) theme — Dark Moody edition.
///
/// Deep blacks, ocean blue accents, no Material ripple.
/// Per design spec:
///   - Material ripple is OFF globally (use scale/tint press states).
///   - Bouncy physics is OFF globally (use [ClampingScrollPhysics]).
///   - All text is theme-driven; no hard-coded colors in widgets.
ThemeData buildNocturneTheme() {
  return _buildTheme(Spectral.fallback);
}

/// Cache key: full spectral palette (all 19 fields).
int _spectralKey(Spectral s) => s.hashCode;

/// LRU cache for ThemeData keyed by spectral palette (max 8 entries).
final LinkedHashMap<int, ThemeData> _themeCache = LinkedHashMap();

/// Builds theme from a full [Spectral] palette extracted from artwork.
/// Surface and text colors shift with the artwork's dominant hue.
/// Caches ThemeData per spectral palette to avoid 48 rebuilds/transition.
ThemeData buildNocturneThemeFromSpectral(Spectral spectral) {
  final key = _spectralKey(spectral);
  final cached = _themeCache[key];
  if (cached != null) return cached;

  final theme = _buildTheme(spectral);
  _themeCache[key] = theme;
  if (_themeCache.length > 8) {
    _themeCache.remove(_themeCache.keys.first);
  }
  return theme;
}

/// Sub-themes that don't depend on Spectral — built once.
const _bottomSheetTheme = BottomSheetThemeData(
  backgroundColor: Colors.transparent,
  surfaceTintColor: Colors.transparent,
  modalBackgroundColor: Colors.transparent,
  modalBarrierColor: AfColors.surfaceScrim,
  // ponytail: top-only corner, no matching AfRadii token (add borderTopXl when needed)
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.only(
      topLeft: AfRadii.rXl,
      topRight: AfRadii.rXl,
    ),
  ),
  showDragHandle: false,
);

const _dialogTheme = DialogThemeData(
  backgroundColor: Colors.transparent,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: AfRadii.borderXl),
);

const _pageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: ZoomPageTransitionsBuilder(),
    TargetPlatform.iOS: _AfSlideUpTransition(),
    TargetPlatform.fuchsia: _AfSlideUpTransition(),
  },
);

const _switchTheme = SwitchThemeData(
  overlayColor: WidgetStatePropertyAll(Colors.transparent),
  splashRadius: 0,
);

const _sliderTheme = SliderThemeData(
  overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
);

const _errorBorder = OutlineInputBorder(
  borderRadius: AfRadii.borderLg,
  borderSide: BorderSide(color: AfColors.semanticError, width: 1),
);

ThemeData _buildTheme(Spectral s) {
  final primary = s.primary;
  final secondary = s.secondary;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: s.surfaceCanvas,
    canvasColor: s.surfaceCanvas,

    colorScheme: ColorScheme.dark(
      primary: primary,
      onPrimary: s.textOnPrimary,
      primaryContainer: primary.withValues(alpha: 0.25),
      onPrimaryContainer: s.textOnPrimary,
      secondary: secondary,
      onSecondary: s.surfaceCanvas,
      secondaryContainer: secondary.withValues(alpha: 0.20),
      onSecondaryContainer: s.textPrimary,
      tertiary: secondary,
      onTertiary: s.textOnPrimary,
      surface: s.surfaceBase,
      onSurface: s.textPrimary,
      onSurfaceVariant: s.textSecondary,
      surfaceContainerLowest: s.surfaceCanvas,
      surfaceContainerLow: s.surfaceLow,
      surfaceContainer: s.surfaceBase,
      surfaceContainerHigh: s.surfaceRaised,
      surfaceContainerHighest: s.surfaceHigh,
      error: AfColors.semanticError,
      onError: s.textOnPrimary,
      outline: s.surfaceMax,
      outlineVariant: s.surfaceHigh,
    ),

    textTheme: AfTypography.textThemeFor(s),
    primaryTextTheme: AfTypography.textThemeFor(s),

    // No Material ripple. Anywhere.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: AfColors.accentPrimary.withValues(alpha: 0.12),

    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) {
          return primary;
        }
        if (states.contains(WidgetState.hovered)) {
          return primary.withValues(alpha: 0.7);
        }
        return s.surfaceMax.withValues(alpha: 0.6);
      }),
      trackColor: WidgetStatePropertyAll(
        s.surfaceCanvas.withValues(alpha: 0.25),
      ),
      trackVisibility: const WidgetStatePropertyAll(false),
      thickness: const WidgetStatePropertyAll(10),
      radius: AfRadii.rPill,
      crossAxisMargin: 2,
      mainAxisMargin: 2,
    ),

    iconTheme: IconThemeData(color: s.textPrimary, size: 24),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: s.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      centerTitle: false,
    ),

    bottomSheetTheme: _bottomSheetTheme,

    dialogTheme: _dialogTheme,

    snackBarTheme: SnackBarThemeData(
      backgroundColor: s.surfaceHigh,
      contentTextStyle: AfTypography.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
    ),

    dividerTheme: DividerThemeData(color: s.surfaceLow, thickness: 1, space: 0),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: s.surfaceHigh,
      circularTrackColor: s.surfaceHigh,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.surfaceBase,
      hintStyle: AfTypography.bodyLarge.copyWith(color: s.textTertiary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s16,
        vertical: AfSpacing.s16,
      ),
      border: OutlineInputBorder(
        borderRadius: AfRadii.borderLg,
        borderSide: BorderSide(color: s.surfaceHigh, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AfRadii.borderLg,
        borderSide: BorderSide(color: s.surfaceHigh, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AfRadii.borderLg,
        borderSide: BorderSide(color: primary, width: 1),
      ),
      errorBorder: _errorBorder,
      labelStyle: AfTypography.bodyMedium.copyWith(color: s.textSecondary),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: s.textOnPrimary,
        textStyle: AfTypography.titleSmall,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderPill),
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s24,
          vertical: AfSpacing.s16,
        ),
        minimumSize: const Size(0, AfSpacing.minHitTarget),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: s.textPrimary,
        textStyle: AfTypography.titleSmall,
        shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderPill),
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s12,
        ),
        minimumSize: const Size(0, AfSpacing.minHitTarget),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: s.textPrimary,
        minimumSize: const Size(AfSpacing.minHitTarget, AfSpacing.minHitTarget),
        padding: const EdgeInsets.all(AfSpacing.s12),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: s.textSecondary,
      textColor: s.textPrimary,
      tileColor: s.surfaceBase,
      selectedTileColor: s.surfaceRaised,
      shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderMd),
    ),

    pageTransitionsTheme: _pageTransitionsTheme,

    // M3 Switch/Slider ignore global splashColor — force overlay off.
    switchTheme: _switchTheme,

    sliderTheme: _sliderTheme,
  );
}

/// Push: new page slides up from bottom with subtle scale + fade for depth.
/// Pop: reverses. Reduced-motion → instant fade only.
class _AfSlideUpTransition extends PageTransitionsBuilder {
  const _AfSlideUpTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced) {
      return FadeTransition(opacity: animation, child: child);
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: AfCurves.springPresent,
      reverseCurve: AfCurves.easeIn,
    );

    // Subtle fade: opacity goes from 0.0 → 1.0 (adds depth to slide).
    final fade = FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
      child: child,
    );

    // Subtle scale: incoming page starts at 97% and scales to 100%.
    final scale = ScaleTransition(
      scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
      child: fade,
    );

    // Slide from bottom (subtle — 15% of screen height).
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(curved),
      child: scale,
    );
  }
}
