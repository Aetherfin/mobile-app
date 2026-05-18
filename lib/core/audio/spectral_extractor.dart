import 'dart:io';
import 'dart:ui' show Color;

import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/painting.dart' show FileImage, ImageProvider;
import 'package:palette_generator_master/palette_generator_master.dart';

import '../../design_tokens/colors.dart';
import '../../utils/log.dart';
import '../../utils/oklch.dart';
import '../../utils/url.dart';

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
  /// In-memory cache of previously-extracted spectral palettes, keyed by
  /// `imageUrl`. Palette extraction decodes the artwork bitmap and runs
  /// the k-means-ish algorithm in `palette_generator` — ~30 ms per call
  /// on a mid-range Android. Track skip → spectral re-run → 30 ms hitch
  /// per skip without this cache. Headers don't go into the key because
  /// the same image bytes give the same palette regardless of which
  /// `Authorization` header fetched them.
  ///
  /// Bounded to 64 entries (~64 album covers' worth of palette data is
  /// a few KB total). Once full we evict the oldest entry — LinkedHashMap
  /// preserves insertion order, so the head is the least-recently-added.
  static const int _cacheLimit = 64;
  final Map<String, Spectral> _cache = <String, Spectral>{};

  Future<Spectral> fromImageUrl(
    String imageUrl, {
    Map<String, String>? headers,
  }) async {
    // Subsonic cover-art URLs carry a fresh salt + md5 token on every
    // call, so keying the in-memory palette cache by the raw URL would
    // miss for every track even when the underlying bytes are identical.
    // The disk-cache key on `CachedNetworkImageProvider` below has the
    // same problem — match it so we share the cache slot.
    final key = stableImageCacheKey(imageUrl);
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
      final palette = await PaletteGeneratorMaster.fromImageProvider(
        provider,
        maximumColorCount: 16,
      );
      final samples = palette.colors.toList(growable: false);
      Spectral result;
      if (samples.isEmpty) {
        result = Spectral.fallback;
      } else {
        final hue = pickSpectralHue(samples);
        if (hue == null) {
          result = Spectral.fallback;
        } else {
          final triple = buildSpectralTriple(hue.h);
          result = Spectral(
            energy: triple.energy,
            shadow: triple.shadow,
            glow: triple.glow,
          );
        }
      }
      _cache[key] = result;
      // Evict oldest (head) entry when over limit.
      if (_cache.length > _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    } catch (e) {
      // Redact `api_key`/`t`/`s`/`u` etc. — Subsonic cover-art URLs
      // embed the user's auth token as query params (same as stream
      // URLs), and Jellyfin image URLs may carry `api_key` too. Without
      // this, a logcat capture from a server-side image failure would
      // emit the token verbatim.
      afLog('spectral',
          'palette extraction failed for ${redactSensitiveQueryParams(imageUrl)}',
          error: e);
      return Spectral.fallback;
    }
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
