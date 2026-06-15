import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/spectral_extractor.dart';
import '../design_tokens/colors.dart';
import '../utils/log.dart';
import '../utils/oklch.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'player_providers.dart';

final spectralExtractorProvider = Provider<SpectralExtractor>((ref) {
  return SpectralExtractor();
});

/// Holds the last successfully extracted spectral — used to preserve
/// colors during artwork transitions instead of flashing to fallback.
Spectral _lastSpectral = Spectral.fallback;

final currentSpectralProvider = Provider<Spectral>((ref) {
  final track = ref.watch(currentTrackProvider);
  final imageUrl = track?.imageUrl;
  final async = ref.watch(spectralFromUrlProvider(imageUrl));
  return async.maybeWhen(
    data: (s) {
      _lastSpectral = s;
      return s;
    },
    // Loading or error — keep previous spectral (no flash to fallback).
    orElse: () => _lastSpectral,
  );
});

/// Provider that gets spectralHue from DB for a track.
/// Returns null if track is not in DB or has no pre-computed hue.
final spectralHueFromDbProvider = FutureProvider.autoDispose
    .family<double?, String?>((ref, trackId) async {
      if (trackId == null) return null;
      try {
        final db = ref.watch(appDatabaseProvider);
        final rows =
            await (db.select(db.tracks)
                  ..where((t) => t.id.equals(trackId))
                  ..limit(1))
                .get();
        if (rows.isEmpty) return null;
        return rows.first.spectralHue;
      } on Exception catch (e) {
        afLog('spectral', 'DB hue lookup failed', error: e);
        return null;
      }
    });

final spectralFromUrlProvider = FutureProvider.autoDispose
    .family<Spectral, String?>((ref, imageUrl) async {
      if (imageUrl == null) return Spectral.fallback;

      // For local tracks, try to get pre-computed hue from DB first
      if (imageUrl.startsWith('file://')) {
        final track = ref.read(currentTrackProvider);
        if (track != null) {
          final dbHue = ref.watch(spectralHueFromDbProvider(track.id));
          final hue = dbHue.value;
          if (hue != null) {
            // Reconstruct Spectral from pre-computed hue
            return _buildSpectralFromHue(hue);
          }
        }
      }

      // Fall back to live extraction
      final headers = ref.watch(
        musicBackendProvider.select((b) => b?.authHeaders),
      );
      try {
        return await ref
            .watch(spectralExtractorProvider)
            .fromImageUrl(imageUrl, headers: headers);
      } on Exception catch (e) {
        afLog('spectral', 'spectral extraction failed', error: e);
        // Return fallback but do NOT overwrite _lastSpectral — preserves the
        // last successful palette so animated transitions keep working.
        return Spectral.fallback;
      }
    });

/// Reconstruct a full Spectral palette from just the hue value.
/// Uses the same logic as SpectralExtractor._buildFromSample.
Spectral _buildSpectralFromHue(double h) {
  // Use default lightness and chroma values from the extraction strategy
  const defaultL = 0.55;
  const defaultC = 0.12;
  return _buildFromSample(OklchColor(defaultL, defaultC, h));
}

/// Builds the full spectral palette from an actual OKLCH sample.
/// Same logic as SpectralExtractor._buildFromSample.
Spectral _buildFromSample(OklchColor sample) {
  final h = sample.h;
  final c = sample.c;

  // Energy: boost chroma, clamp lightness for contrast.
  final energyL = sample.l.clamp(0.45, 0.72);
  final energyC = c > 0.10 ? c : 0.10;
  final energy = OklchColor(energyL, energyC, h).toColor();

  // Shadow: same hue, very dark, low chroma.
  final shadow = OklchColor(0.18, c * 0.35, h).toColor();

  // Glow: same hue, light, moderate chroma.
  final glowL = sample.l + 0.15 > 0.85 ? 0.85 : sample.l + 0.15;
  final glow = OklchColor(glowL, c * 0.55, h).toColor();

  // Primary: same as energy — main UI accent for theme.
  final primary = energy;

  // Secondary: hue-shifted +20°, slightly lower chroma.
  final secondaryHue = (h + 20) % 360;
  final secondary = OklchColor(
    energyL.clamp(0.40, 0.65),
    energyC * 0.75 > 0.08 ? energyC * 0.75 : 0.08,
    secondaryHue,
  ).toColor();

  // Muted: same hue, low chroma, medium lightness.
  final muted = OklchColor(0.45, c * 0.30, h).toColor();

  // Link: same hue, lighter than primary, moderate chroma.
  final linkL = energyL + 0.12 > 0.78 ? 0.78 : energyL + 0.12;
  final link = OklchColor(linkL, energyC * 0.85, h).toColor();

  // Warning: same hue as energy (replaces static semanticWarning).
  final warning = energy;

  // Surface palette — very dark hue-tinted surfaces
  final surfaceCanvas = OklchColor(0.04, 0.010, h).toColor();
  final surfaceLow = OklchColor(0.09, 0.012, h).toColor();
  final surfaceBase = OklchColor(0.14, 0.015, h).toColor();
  final surfaceRaised = OklchColor(0.18, 0.018, h).toColor();
  final surfaceHigh = OklchColor(0.23, 0.020, h).toColor();
  final surfaceMax = OklchColor(0.28, 0.022, h).toColor();

  // Text palette — neutral with slight hue tint for cohesion
  final textPrimary = OklchColor(0.91, 0.008, h).toColor();
  final textSecondary = OklchColor(0.62, 0.012, h).toColor();
  final textTertiary = OklchColor(0.45, 0.015, h).toColor();
  final textDisabled = OklchColor(0.30, 0.010, h).toColor();
  final textOnPrimary = OklchColor(0.95, 0.005, h).toColor();

  return Spectral(
    energy: energy,
    shadow: shadow,
    glow: glow,
    primary: primary,
    secondary: secondary,
    muted: muted,
    link: link,
    warning: warning,
    surfaceCanvas: surfaceCanvas,
    surfaceLow: surfaceLow,
    surfaceBase: surfaceBase,
    surfaceRaised: surfaceRaised,
    surfaceHigh: surfaceHigh,
    surfaceMax: surfaceMax,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textTertiary: textTertiary,
    textDisabled: textDisabled,
    textOnPrimary: textOnPrimary,
  );
}

/// Pastel accent colour derived from the current artwork's spectral energy.
/// Converts the vibrant energy to OKLCH, then shifts it to a pastel profile
/// (lightness ~0.78, chroma ~0.08) for a soft, muted accent.
final pastelAccentColorProvider = Provider<Color>((ref) {
  final spectral = ref.watch(currentSpectralProvider);
  final energy = spectral.energy;
  final oklch = srgbToOklch(energy);
  final triple = buildPastelTriple(oklch.h);
  return triple.accent;
});
