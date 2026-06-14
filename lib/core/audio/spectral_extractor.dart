import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color;

import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/painting.dart'
    show
        FileImage,
        ImageConfiguration,
        ImageInfo,
        ImageProvider,
        ImageStream,
        ImageStreamListener;
import 'package:palette_generator_master/palette_generator_master.dart';

import '../../design_tokens/colors.dart';
import '../../utils/log.dart';
import '../../utils/oklch.dart';
import '../../utils/url.dart';

/// Data bundle sent to the background isolate for palette extraction.
///
/// Contains raw RGBA pixel data produced by [ui.Image.toByteData] on the main
/// thread.  All fields are primitive / sendable across isolate boundaries.
class _PaletteRequest {
  const _PaletteRequest(this.rgbaBytes, this.width, this.height);

  /// Raw RGBA pixel data from [ui.ImageByteFormat.rawRgba].
  final Uint8List rgbaBytes;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;
}

/// Top-level function that runs palette extraction in a background isolate.
///
/// Creates an [EncodedImageMaster] from the raw RGBA bytes, runs
/// [PaletteGeneratorMaster.fromByteData] (the expensive quantization step),
/// then picks the best spectral palette using population-weighted chroma
/// scoring.  Must be top-level for isolate compatibility.
Future<Spectral?> _extractPaletteInBackground(_PaletteRequest request) async {
  final encodedImage = EncodedImageMaster(
    ByteData.view(request.rgbaBytes.buffer),
    width: request.width,
    height: request.height,
  );
  final palette = await PaletteGeneratorMaster.fromByteData(
    encodedImage,
    maximumColorCount: 16,
    colorSpace: ColorSpace.lab,
  );
  return _pickBestSpectral(palette);
}

/// Picks the best spectral color from the palette.
///
/// Strategy priority:
///   1. Dominant color — largest population, most representative of artwork
///   2. Vibrant color — only if it has significant population (>15%)
///   3. Best scored color — population-weighted chroma score
///   4. Fallback to default
Spectral _pickBestSpectral(PaletteGeneratorMaster palette) {
  final pColors = palette.paletteColors;
  if (pColors.isEmpty) return Spectral.fallback;

  final totalPopulation = pColors.fold<int>(0, (sum, c) => sum + c.population);
  if (totalPopulation == 0) return Spectral.fallback;

  // ── Strategy 1: Dominant color (largest population) ──
  final dominant = palette.dominantColor;
  if (dominant != null) {
    final oklch = srgbToOklch(dominant.color);
    if (oklch.c >= 0.04 && oklch.l >= 0.15 && oklch.l <= 0.85) {
      return _buildFromSample(oklch);
    }
  }

  // ── Strategy 2: Vibrant — only if significant population (>15%) ──
  final vibrant = palette.vibrantColor;
  if (vibrant != null) {
    final popShare = vibrant.population / totalPopulation;
    if (popShare > 0.15) {
      final oklch = srgbToOklch(vibrant.color);
      if (oklch.c >= 0.05 && oklch.l >= 0.15 && oklch.l <= 0.85) {
        return _buildFromSample(oklch);
      }
    }
  }

  // ── Strategy 3: Best population-weighted chroma score ──
  // Score = chroma² × population — heavily penalizes tiny accents.
  final candidates = <_ScoredColor>[];
  for (final pc in pColors) {
    final oklch = srgbToOklch(pc.color);
    if (oklch.c < 0.04) continue; // grey
    if (oklch.l < 0.12 || oklch.l > 0.88) continue; // near-black/white
    final popShare = pc.population / totalPopulation;
    final score = oklch.c * oklch.c * popShare;
    candidates.add(_ScoredColor(oklch, score));
  }

  if (candidates.isEmpty) return Spectral.fallback;
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final best = candidates.first;

  return _buildFromSample(best.oklch);
}

/// Builds the full spectral palette from an actual OKLCH sample.
///
/// All variants share the same hue — they differ only in lightness
/// and chroma, so the palette always feels cohesive.
Spectral _buildFromSample(OklchColor sample) {
  final h = sample.h;
  final c = sample.c;

  // Energy: boost chroma, clamp lightness for contrast.
  final energyL = sample.l.clamp(0.45, 0.72);
  final energyC = math.max(c, 0.10);
  final energy = OklchColor(energyL, energyC, h).toColor();

  // Shadow: same hue, very dark, low chroma.
  final shadow = OklchColor(0.18, c * 0.35, h).toColor();

  // Glow: same hue, light, moderate chroma.
  final glowL = math.min(sample.l + 0.15, 0.85);
  final glow = OklchColor(glowL, c * 0.55, h).toColor();

  // Primary: same as energy — main UI accent for theme.
  final primary = energy;

  // Secondary: hue-shifted +20°, slightly lower chroma.
  final secondaryHue = (h + 20) % 360;
  final secondary = OklchColor(
    energyL.clamp(0.40, 0.65),
    math.max(energyC * 0.75, 0.08),
    secondaryHue,
  ).toColor();

  // Muted: same hue, low chroma, medium lightness.
  final muted = OklchColor(0.45, c * 0.30, h).toColor();

  // Link: same hue, lighter than primary, moderate chroma.
  final linkL = math.min(energyL + 0.12, 0.78);
  final link = OklchColor(linkL, energyC * 0.85, h).toColor();

  // Warning: same hue as energy (replaces static semanticWarning).
  final warning = energy;

  // ── Surface palette — very dark hue-tinted surfaces ──
  // Chroma is kept very low (0.01–0.025) so the tint is felt, not seen.
  final surfaceCanvas = OklchColor(0.04, 0.010, h).toColor();
  final surfaceLow = OklchColor(0.09, 0.012, h).toColor();
  final surfaceBase = OklchColor(0.14, 0.015, h).toColor();
  final surfaceRaised = OklchColor(0.18, 0.018, h).toColor();
  final surfaceHigh = OklchColor(0.23, 0.020, h).toColor();
  final surfaceMax = OklchColor(0.28, 0.022, h).toColor();

  // ── Text palette — neutral with slight hue tint for cohesion ──
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

/// Extracts the spectral accent triple from an artwork URL.
///
/// Sampling strategy:
///   1. Use `PaletteGeneratorMaster` to get 16 quantized colors with
///      population counts, plus pre-computed targets (vibrant, muted, etc.)
///   2. Pick the best color using a composite score of chroma × population
///      weight — not just highest chroma (which picks tiny accent pixels).
///   3. Build the triple from the actual sampled L/C/H, not hardcoded values.
///   4. If no sample qualifies, fall back to the default spectral.
class SpectralExtractor {
  static const int _cacheLimit = 64;
  final Map<String, Spectral> _cache = <String, Spectral>{};
  final Map<String, Future<Spectral>> _inFlight = {};

  Future<Spectral> fromImageUrl(
    String imageUrl, {
    Map<String, String>? headers,
  }) async {
    final key = stableImageCacheKey(imageUrl);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _extract(key, imageUrl, headers);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      // ignore: unawaited_futures
      _inFlight.remove(key);
    }
  }

  Future<Spectral> _extract(
    String key,
    String imageUrl,
    Map<String, String>? headers,
  ) async {
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    try {
      final ImageProvider provider;
      if (imageUrl.startsWith('file://')) {
        provider = FileImage(File(imageUrl.substring('file://'.length)));
      } else {
        provider = CachedNetworkImageProvider(
          imageUrl,
          headers: headers,
          cacheKey: key,
        );
      }

      // Try background isolate extraction first.
      Spectral result;
      try {
        result = await _extractViaIsolate(provider);
      } catch (e, stack) {
        afLog(
          'spectral',
          'Isolate extraction failed, falling back to main thread',
          error: e,
          stackTrace: stack,
        );
        result = await _extractMainThread(provider);
      }

      _cache[key] = result;
      if (_cache.length > _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    } on Exception catch (e, stack) {
      afLog(
        'spectral',
        'palette extraction failed for ${redactSensitiveQueryParams(imageUrl)}',
        error: e,
        stackTrace: stack,
      );
      return Spectral.fallback;
    }
  }

  /// Resolves the [ImageProvider] to a [ui.Image], extracts raw RGBA bytes,
  /// then dispatches the heavy quantization to a background isolate via
  /// [Isolate.run].
  Future<Spectral> _extractViaIsolate(ImageProvider provider) async {
    // Step 1: resolve provider → ui.Image (main thread, engine-bound).
    final Completer<ui.Image> imageCompleter = Completer<ui.Image>();
    final ImageStream stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, _) {
        stream.removeListener(listener);
        if (!imageCompleter.isCompleted) {
          imageCompleter.complete(info.image);
        }
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        if (!imageCompleter.isCompleted) {
          imageCompleter.completeError(error, stack);
        }
      },
    );
    stream.addListener(listener);

    final ui.Image image = await imageCompleter.future;
    final int imageWidth = image.width;
    final int imageHeight = image.height;

    // Step 2: convert to raw RGBA bytes (main thread).
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    image.dispose();

    if (byteData == null) {
      throw StateError('Failed to encode image to RGBA bytes');
    }

    // Step 3: dispatch quantization + scoring to background isolate.
    final request = _PaletteRequest(
      byteData.buffer.asUint8List(),
      imageWidth,
      imageHeight,
    );

    final Spectral? result = await Isolate.run(
      () => _extractPaletteInBackground(request),
    );

    return result ?? Spectral.fallback;
  }

  /// Main-thread extraction path — identical to the original behavior before
  /// isolate offloading.  Used as a fallback when isolates are unavailable.
  Future<Spectral> _extractMainThread(ImageProvider provider) async {
    final palette = await PaletteGeneratorMaster.fromImageProvider(
      provider,
      maximumColorCount: 16,
      colorSpace: ColorSpace.lab,
    );
    return _pickBestSpectral(palette);
  }

  /// Synchronous fallback used in widget tests / preview mode.
  Spectral fromColors(Iterable<Color> samples) {
    final hue = pickSpectralHue(samples);
    if (hue == null) return Spectral.fallback;
    return _buildFromSample(OklchColor(hue.l, hue.c, hue.h));
  }

  /// Extract spectral hue from a local artwork file path.
  /// Returns the OKLCH hue (0-360) or null if extraction fails.
  /// Used during scan to pre-compute palettes for instant playback.
  Future<double?> extractHueFromArtwork(String artworkPath) async {
    try {
      final provider = FileImage(File(artworkPath));
      Spectral result;
      try {
        result = await _extractViaIsolate(provider);
      } catch (e, stack) {
        afLog(
          'spectral',
          'Isolate hue extraction failed, falling back to main thread',
          error: e,
          stackTrace: stack,
        );
        result = await _extractMainThread(provider);
      }
      // Extract hue from the spectral's energy color
      final oklch = srgbToOklch(result.energy);
      return oklch.h;
    } on Exception catch (e, stack) {
      afLog(
        'spectral',
        'hue extraction failed for $artworkPath',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }
}

class _ScoredColor {
  const _ScoredColor(this.oklch, this.score);
  final OklchColor oklch;
  final double score;
}
