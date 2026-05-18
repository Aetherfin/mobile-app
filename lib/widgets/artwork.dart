import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/url.dart';

/// Network artwork that gracefully degrades to a deterministic indigo
/// gradient when the URL is null or fails to load. Used everywhere we
/// need an album/playlist/track cover.
///
/// The widget reads `jellyfinClientProvider` so it can send the active
/// `Authorization` header alongside the image fetch. The token used to
/// ride in the URL as `?api_key=…`; review S2 moved it to a header,
/// which means Jellyfin servers with auth-required image endpoints
/// would 401 here without this wiring.
class Artwork extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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

    final backend = ref.watch(musicBackendProvider);
    final headers = backend?.authHeaders;

    // Local files: load from disk directly.
    if (url!.startsWith('file://')) {
      final filePath = url!.substring('file://'.length);
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: wFinite,
          height: hFinite,
          child: Image.file(
            File(filePath),
            fit: fit,
            width: wFinite,
            height: hFinite,
            errorBuilder: (context, error, stack) => placeholder,
            cacheWidth: clampedCachePx(wFinite),
            cacheHeight: clampedCachePx(hFinite),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: wFinite,
        height: hFinite,
        child: CachedNetworkImage(
          // `cacheKey` strips Subsonic per-request salt/token (`u`, `t`,
          // `s`) and Jellyfin `api_key` from the URL so the disk cache
          // hits across requests. Without this, every list refresh
          // regenerates the auth params and re-downloads the same
          // bytes. The unsanitized URL is still used for `imageUrl` so
          // the actual HTTP fetch carries the live auth.
          cacheKey: stableImageCacheKey(url!),
          imageUrl: url!,
          httpHeaders: headers,
          fit: fit,
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) => placeholder,
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
