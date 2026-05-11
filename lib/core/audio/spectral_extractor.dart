import 'dart:ui' show Color;

import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:palette_generator/palette_generator.dart';

import '../../design_tokens/colors.dart';
import '../../utils/oklch.dart';

/// Extracts the spectral accent triple from an artwork URL.
///
/// Sampling strategy:
///   1. Use `palette_generator` to grab up to 16 dominant colors over the
///      whole image (it does the down-sampling for us).
///   2. Pass those colors through the OKLCH classifier in `utils/oklch.dart`
///      (discards greys, near-black, near-white).
///   3. Pick the highest-chroma remaining sample.
///   4. If no sample qualifies, fall back to indigo.500.
///
/// We feed [PaletteGenerator] a [CachedNetworkImageProvider] (instead of
/// a plain `NetworkImage`) so the artwork bytes are reused from the same
/// on-disk cache that `cached_network_image` writes for the cover-art
/// widgets. Without this, every track change triggered a second HTTP
/// fetch of artwork that was already on disk.
class SpectralExtractor {
  Future<Spectral> fromImageUrl(
    String imageUrl, {
    Map<String, String>? headers,
  }) async {
    final palette = await PaletteGenerator.fromImageProvider(
      CachedNetworkImageProvider(imageUrl, headers: headers),
      maximumColorCount: 16,
    );
    final samples = palette.colors.toList(growable: false);
    if (samples.isEmpty) return Spectral.fallback;
    final hue = pickSpectralHue(samples);
    if (hue == null) return Spectral.fallback;
    final triple = buildSpectralTriple(hue.h);
    return Spectral(
      energy: triple.energy,
      shadow: triple.shadow,
      glow: triple.glow,
    );
  }

  /// Synchronous fallback used in widget tests / preview mode.
  Spectral fromColors(Iterable<Color> samples) {
    final hue = pickSpectralHue(samples);
    if (hue == null) return Spectral.fallback;
    final triple = buildSpectralTriple(hue.h);
    return Spectral(
      energy: triple.energy,
      shadow: triple.shadow,
      glow: triple.glow,
    );
  }
}
