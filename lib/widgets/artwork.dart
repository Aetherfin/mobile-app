import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Network artwork that gracefully degrades to a deterministic indigo
/// gradient when the URL is null or fails to load. Used everywhere we
/// need an album/playlist/track cover.
class Artwork extends StatelessWidget {
  final String? url;
  final double size;
  final double? height;
  final BorderRadius radius;
  final BoxFit fit;
  final String? semanticLabel;

  const Artwork({
    super.key,
    required this.url,
    this.size = 56,
    this.height,
    this.radius = AfRadii.borderMd,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = height ?? size;
    // `size` / `height` can come from `double.infinity` when Artwork
    // is dropped into an unbounded constraint (Expanded, Flexible,
    // ConstrainedBox with no max). `Infinity.round()` throws, so any
    // memCache hint must be guarded.
    final wFinite = w.isFinite ? w : null;
    final hFinite = h.isFinite ? h : null;
    final placeholder = Container(
      width: wFinite,
      height: hFinite,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AfColors.indigo800, AfColors.indigo950],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          color: AfColors.indigo300,
          size: 28,
        ),
      ),
    );
    if (url == null || url!.isEmpty) {
      return Semantics(label: semanticLabel, child: placeholder);
    }
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    int? clampedCachePx(double? logicalPx) {
      if (logicalPx == null) return null;
      final physical = (logicalPx * dpr).round();
      // Hard ceiling so a misconfigured giant artwork (e.g. 4096px
      // wide page hero) doesn't decode an obscene bitmap.
      if (physical <= 0) return null;
      return physical > 1024 ? 1024 : physical;
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: wFinite,
        height: hFinite,
        child: CachedNetworkImage(
          imageUrl: url!,
          fit: fit,
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
          fadeInDuration: AfDurations.quick,
          memCacheWidth: clampedCachePx(wFinite),
          memCacheHeight: clampedCachePx(hFinite),
        ),
      ),
    );
  }
}

/// Circular variant for artist tiles.
class CircularArtwork extends StatelessWidget {
  final String? url;
  final double size;
  final String? semanticLabel;

  const CircularArtwork({
    super.key,
    required this.url,
    this.size = 64,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => Artwork(
        url: url,
        size: size,
        radius: BorderRadius.circular(size / 2),
        semanticLabel: semanticLabel,
      );
}
